// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "openzeppelin-contracts/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "circles-contracts-v2/groups/BaseMintPolicy.sol";
import "src/circles/Core.sol";
import "src/errors/Errors.sol";
import "src/operator/IOperator.sol";
import "src/policies/PolicyTypes.sol";
import "src/supergroup/OperatorRequests.sol";
import "src/supergroup/PolicyFingerprints.sol";
import "src/supergroup/ISupergroup.sol";

/// @notice Supergroups are opinionated liquidity clusters of valued Circles
///         Supergroups follow a pattern where the group avatar is a contract address
///         that registers itself as the group and acts as a policy at the same time.
///         This pattern allows the group to have transparant behaviour.
///         Furthermore, this supergroup contract is intended to be used as an implementation
///         for a (renounceable) proxy contract, so the constructor blocks
///         the mastercopy deployment, and the proxy should call setup to configure the state.
contract Supergroup is
    MintPolicy,
    PolicyFingerprints,
    OperatorRequests,
    ERC1155Holder,
    CirclesCoreAddresses,
    ISupergroup,
    ISupergroupErrors
{
    // Constants

    /// @notice Max ratio for minting fee or redemption burn ratio
    ///         is set to 2 out of 24, stored as a percentage.
    ///         With 18 decimals; 2/24 * 10**18 = 0,08333.. * 10**18
    uint256 public constant MAX_RATIO = 83333333333333333;
    /// @dev The sentinel value used as the first element in the linked list of operators
    address private constant SENTINEL = address(0x1);

    // Enum

    /// @notice Proxy status keeps an explicit byte about this state instance
    enum ProxyStatus {
        Uninitialised,
        Mastercopy,
        SetUp
    }

    // State variables

    /// @notice Owner address. This is a copied value of ERC1967 ADMIN_SLOT
    ///         if this supergroup mastercopy is consumed by an ERC1067 proxy.
    ///         For simplicity and readability we duplicate owner with ERC1967 admin,
    ///         even if for the intended deployment they are the same address.
    address public owner;
    /// @notice Require an authorized operator to register group mint requests ahead,
    ///         so that advanced checks can be performed by the operator.
    ///         If operators are not required, then direct mint access over the Circles
    ///         hub - either as a direct call or over a path transfer - will all
    ///         be allowed (if the collateral is trusted by the group).
    bool public requireOperator = false;
    /// @notice Return group Circles to sender, when true, will send group Circles
    ///         back to the original sender of a path, if collateral was sent to the group
    ///         as an end-receiver of that path.
    bool public returnGroupCirclesToSender = true;
    /// @notice fee levied upon group minting can be between zero and MAX_FEE (1/12th)
    ///         of the amount minted. Setting the fee to zero disables the fee charge.
    uint256 public mintFee = 0;
    /// @notice fee collection address collects group minting fees when enabled
    address public feeCollection;
    /// @notice redemption burn ratio will burn this ratio (expressed per 10**18). This amount
    ///         will be burnt and is not sent to a collection address.
    uint256 public redemptionBurnRatio = 0;
    /// @notice We take Hub address from core constants, so we need a minimal variable to
    ///         track whether this state (mastercopy or proxy) has been constructed or setup.
    ProxyStatus public proxyStatus = ProxyStatus.Uninitialised;
    /// @notice Mapping of operator addresses to the next operator in the linked list
    mapping(address => address) public operators;

    // Events

    /// @notice Emitted when fee, and collection address updated
    event MintFeeSet(address indexed feeCollection, uint256 fee);

    /// @notice Emitted when the operator requirement is updated
    event OperatorsRequired(bool required);

    /// @notice Emitted when the redemption burn rate is updated
    event RedemptionBurnRateUpdated(uint256 redemptionRate);

    /// @notice Emitted when the flag whether to return group Circles to sender
    ///         is updated
    event ReturnGroupCirclesToSender(bool returnGroupCircles);

    // Modifiers

    /// @notice Only the Circles Hub can call this function
    modifier onlyHub() {
        if (msg.sender != address(hub)) {
            revert SupergroupOnlyHub();
        }
        _;
    }

    /// @notice Only owner can call
    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert SupergroupOnlyOwner();
        }
        _;
    }

    // Constructor

    constructor() {
        // set proxy status to mastercopy to block its direct usage
        proxyStatus = ProxyStatus.Mastercopy;
    }

    // Setup

    function setup(
        address _owner,
        uint256 _mintFee,
        address _feeCollection,
        uint256 _redemptionBurnRatio,
        address[] calldata _operators,
        string calldata _name,
        string calldata _symbol,
        bytes32 _metadataDigest
    ) public virtual {
        if (proxyStatus != ProxyStatus.Uninitialised) {
            // contract state already initialised.
            revert SupergroupProxyAlreadyInitialised();
        }

        // mark this proxy as set up
        proxyStatus = ProxyStatus.SetUp;

        // set the owner to the same address (msg.sender) as ERC1967 ADMIN_SLOT
        // in Renounceable proxy
        owner = _owner;

        // register group in hub and set the mint policy to this address
        hub.registerGroup(address(this), _name, _symbol, _metadataDigest);

        // authorize operators
        uint256 length = _operators.length;
        for (uint256 i = 0; i < length; i++) {
            // authorize each operator
            _setAuthorizedOperator(_operators[i], true);
        }
        // sanity check
        if (length != countOperators()) {
            revert SupergroupLogicAssertion();
        }

        // set the fee and fee collection address
        _setMintFee(_mintFee, _feeCollection);

        // set redemption burn ratio
        _setRedemptionBurn(_redemptionBurnRatio);

        // set default behaviour to return gCRC to sender (also on proxy contract)
        returnGroupCirclesToSender = true;
    }

    function trust(address _trustReceiver, uint96 _expiry) external onlyOwner {
        _trust(_trustReceiver, _expiry);
    }

    /// @notice beforeMintPolicy returns true always, unless it is required to act over
    ///         an authorized operator of the supergroup, in which case the operator
    ///         must first have asserted potential requirements and registered an operator
    ///         request before initiating a further calls which trigger the mint policy.
    function beforeMintPolicy(
        address _minter,
        address _group,
        uint256[] calldata _collateral,
        uint256[] calldata _amounts,
        bytes calldata /*_data*/
    ) external override onlyHub returns (bool) {
        // sanity-check that group is this group
        if (_group != address(this)) {
            return false;
        }
        // if minting is required to go via operators, then the operator must have
        // registered its request to initiate a group mint.
        if (requireOperator) {
            // for explicit groupmint from the operator, we could short-cut
            // because the _minter is the operator address,
            // but for the path-triggered groupmint, we need to know whether
            // this request has been vetted by the operator before it reaches the policy.
            // So for clarity, we use the same pattern for both.
            bytes32 requestHash = PolicyTypes.hashRequest(_minter, _group, _collateral, _amounts);
            if (!_validateRequest(requestHash)) {
                return false;
            }
        }
        // next register the executed fingerprints to match them during potential acceptance calls
        uint256 length = _collateral.length;
        for (uint256 i = 0; i < length; i++) {
            _addToFingerprint(_group, _collateral[i], _amounts[i]);
        }
        return true;
    }

    function beforeRedeemPolicy(
        address, /*_operator*/
        address, /*_redeemer*/
        address _group,
        uint256, /*_value*/
        bytes calldata _data
    )
        external
        virtual
        override
        returns (
            uint256[] memory _ids,
            uint256[] memory _values,
            uint256[] memory _burnIds,
            uint256[] memory _burnValues
        )
    {
        // sanity-check that group is this group
        if (_group != address(this)) {
            revert SupergroupLogicAssertion();
        }
        // simplest policy is to return the collateral as the caller requests it in data
        BaseMintPolicyDefinitions.BaseRedemptionPolicy memory redemption =
            abi.decode(_data, (BaseMintPolicyDefinitions.BaseRedemptionPolicy));

        if (redemptionBurnRatio > 0) {
            uint256 length = redemption.redemptionIds.length;
            _burnIds = new uint256[](length);
            _burnValues = new uint256[](length);

            for (uint256 i = 0; i < length; i++) {
                _burnIds[i] = redemption.redemptionIds[i];
                (uint256 returnAmount, uint256 burnAmount) =
                    _splitAmountInReturnAndFee(redemption.redemptionValues[i], redemptionBurnRatio);
                redemption.redemptionValues[i] = returnAmount;
                _burnValues[i] = burnAmount;
            }
        } else {
            _burnIds = new uint256[](0);
            _burnValues = new uint256[](0);
        }

        // standard treasury checks whether the total sums add up to the amount of group Circles redeemed
        // so we can simply decode, update for potential return and burn, and
        // pass the request back to treasury.
        // The redemption will fail if it does not contain (sufficient of) these Circles
        return (redemption.redemptionIds, redemption.redemptionValues, _burnIds, _burnValues);
    }

    /// @notice Authorized operators can register a request to mint group currency
    ///         within the same transaction, by preregistering the parameters of the request
    ///         before initiating the hub either explicitly or over a path.
    ///         This can be called multiple times for multiple group mints along a path
    ///         (eg. different collateral arriving at the group).
    function registerOperatorRequest(
        address _minter,
        address _group,
        uint256[] calldata _collateral,
        uint256[] calldata _amounts
    ) external returns (bool) {
        // todo: this check can now use the locally stored operators - after tests written
        // the operator must be authorized by the supergroup to register request
        if (!hub.isApprovedForAll(address(this), msg.sender)) {
            revert SupergroupOnlyAuthorizedOperator();
        }
        _submitRequest(_minter, _group, _collateral, _amounts);
        return true;
    }

    /// @notice Set authorized operator for this group in Circles hub, and also
    ///         mirror this state in the supergroup, so one can query which operators
    ///         exist for this group (without indexing).
    /// @param _operator Address of the operator
    /// @param _authorized True to authorize, false to revoke
    function setAuthorizedOperator(address _operator, bool _authorized) external onlyOwner {
        _setAuthorizedOperator(_operator, _authorized);
    }

    function setMintFee(uint256 _mintFee, address _feeCollection) external onlyOwner {
        _setMintFee(_mintFee, _feeCollection);
    }

    function setRedemptionBurn(uint256 _burnRedemptionRate) external onlyOwner {
        _setRedemptionBurn(_burnRedemptionRate);
    }

    function setRequireOperators(bool _required) external onlyOwner {
        _requireOperator(_required);
    }

    function setReturnGroupCirclesToSender(bool _returnGroupCircles) external onlyOwner {
        returnGroupCirclesToSender = _returnGroupCircles;

        emit ReturnGroupCirclesToSender(_returnGroupCircles);
    }

    // ERC1155 Acceptance Call handlers

    /// @notice Handler for receiving single ERC1155 token transfers
    /// @dev Only callable by the Circles Hub. Verifies fingerprints and handles group token returns
    /// @param _from Address that initiated the transfer
    /// @param _id Token ID being transferred
    /// @param _value Amount of tokens being transferred
    /// @param _data Additional data passed with transfer
    /// @return bytes4 Function selector to confirm transfer acceptance
    function onERC1155Received(address, /*_operator*/ address _from, uint256 _id, uint256 _value, bytes memory _data)
        public
        virtual
        override
        onlyHub
        returns (bytes4)
    {
        // check the fingerprint whether value has been accounted for during beforeMintPolicy calls
        // If this value is not accounted for in during beforeMintPolicy calls,
        // then this will revert.
        // Note that this is still a "treacherous pattern", and the only recommended pattern is
        // to use operators exclusively.
        //
        // An example of an unintented manipulation that is unavoidable (when explictly
        // not wanting to use operators): imagine the group has 1 gCRC, and aCRC is valid collateral
        // one can call hub.groupMint(1 aCRC), which will register a fingerprint for 1 gCRC for aCRC,
        // but does not trigger an acceptance call; in the same transaction someone can now
        // send 1 aCRC to the group with hub.safeTransfer, and in that acceptance call,
        // if `returnGroupCirclesToSender` is true, this acceptance handler will send the groups'
        // 1 gCRC to the sender, accepting the 1 aCRC (which was necessarily valid collateral).
        //
        // However, this is exactly already possible with a path transfer, because the group trusts
        // aCRC, so an easier way to achieve the same is using a path and swapping the groups' gCRC
        // for aCRC directly.
        _subtractFromFingerprint(address(this), _id, _value);

        if (returnGroupCirclesToSender) {
            if (mintFee > 0) {
                (uint256 returnAmount, uint256 fee) = _splitAmountInReturnAndFee(_value, mintFee);
                // return the return amount to sender
                hub.safeTransferFrom(address(this), _from, _groupId(), returnAmount, _data);
                // send the fee to fee collection address
                hub.safeTransferFrom(address(this), feeCollection, _groupId(), fee, "");
            } else {
                // return the same amount as gCRC to the sender
                hub.safeTransferFrom(address(this), _from, _groupId(), _value, _data);
            }
        }
        return this.onERC1155Received.selector;
    }

    /// @notice Handler for receiving batch ERC1155 token transfers
    /// @dev Only callable by the Circles Hub. Verifies fingerprints and handles group token returns.
    ///      First parameter _operator is unused.
    /// @param _from Address that initiated the transfer
    /// @param _ids Array of token IDs being transferred
    /// @param _values Array of amounts being transferred for each token ID
    /// @param _data Additional data passed with transfer
    /// @return bytes4 Function selector to confirm transfer acceptance
    function onERC1155BatchReceived(
        address, /*_operator*/
        address _from,
        uint256[] memory _ids,
        uint256[] memory _values,
        bytes memory _data
    ) public virtual override onlyHub returns (bytes4) {
        uint256 length = _ids.length;
        uint256 value = 0;
        for (uint256 i = 0; i < length; i++) {
            // account for all the accepting ids and values
            _subtractFromFingerprint(address(this), _ids[i], _values[i]);
            value += _values[i];
        }
        if (returnGroupCirclesToSender) {
            if (mintFee > 0) {
                (uint256 returnAmount, uint256 fee) = _splitAmountInReturnAndFee(value, mintFee);
                // return the return amount to sender
                hub.safeTransferFrom(address(this), _from, _groupId(), returnAmount, _data);
                // send the fee to fee collection address
                hub.safeTransferFrom(address(this), feeCollection, _groupId(), fee, "");
            } else {
                // return the same amount as gCRC to the sender
                hub.safeTransferFrom(address(this), _from, _groupId(), value, _data);
            }
        }
        return this.onERC1155BatchReceived.selector;
    }

    // External pass-through helpers for owner to act on Circles hub and NameRegistry

    /// @notice Safely transfers a single ERC1155 token from one address to another.
    /// @dev Only callable by the owner of this contract.
    /// @param _from The address currently holding the token to be transferred.
    /// @param _to The address to which the token will be transferred.
    /// @param _id The ID of the token being transferred.
    /// @param _value The amount of the token being transferred.
    /// @param _data Additional data with no specified format, sent in call to `_to`.
    function safeTransferFrom(address _from, address _to, uint256 _id, uint256 _value, bytes calldata _data)
        external
        onlyOwner
    {
        hub.safeTransferFrom(_from, _to, _id, _value, _data);
    }

    /// @notice Safely transfers a batch of ERC1155 tokens from one address to another.
    /// @dev Only callable by the owner of this contract.
    /// @param _from The address currently holding the tokens to be transferred.
    /// @param _to The address to which the tokens will be transferred.
    /// @param _ids An array of token IDs being transferred.
    /// @param _values An array of amounts being transferred for each token ID.
    /// @param _data Additional data with no specified format, sent in call to `_to`.
    function safeBatchTransferFrom(
        address _from,
        address _to,
        uint256[] calldata _ids,
        uint256[] calldata _values,
        bytes calldata _data
    ) external onlyOwner {
        hub.safeBatchTransferFrom(_from, _to, _ids, _values, _data);
    }

    function setAdvancedUsageFlag(bytes32 _flag) external onlyOwner {
        hub.setAdvancedUsageFlag(_flag);
    }

    function updateMetadataDigest(bytes32 _metadataDigest) external onlyOwner {
        nameRegistry.updateMetadataDigest(_metadataDigest);
    }

    function registerShortName() external onlyOwner {
        nameRegistry.registerShortName();
    }

    function registerShortNameWithNonce(uint256 _nonce) external onlyOwner {
        nameRegistry.registerShortNameWithNonce(_nonce);
    }

    // External view functions

    /// @notice Gets all authorized operators
    /// @return Array of operator addresses
    function getOperators() external view returns (address[] memory) {
        // Count operators first
        uint256 count = countOperators();

        // Create and populate array
        address[] memory result = new address[](count);
        address current = operators[SENTINEL];
        for (uint256 i = 0; i < count; i++) {
            result[i] = current;
            current = operators[current];
        }

        return result;
    }

    /// @notice Checks if an address is an authorized operator
    /// @param _operator Address to check
    /// @return True if authorized, false otherwise
    function isAuthorizedOperator(address _operator) public view returns (bool) {
        return operators[_operator] != address(0);
    }

    // Public functions

    function countOperators() public view returns (uint256) {
        uint256 count = 0;
        address current = operators[SENTINEL];
        while (current != SENTINEL && current != address(0)) {
            count++;
            current = operators[current];
        }
        return count;
    }

    // Internal functions

    function _trust(address _trustReceiver, uint96 _expiry) internal {
        hub.trust(_trustReceiver, _expiry);
    }

    /// @notice Internal function to add or remove an operator from both the linked list and hub authorization
    /// @dev Uses a linked list structure to maintain operator list, with SENTINEL as guard node
    /// @param _operator The address of the operator to authorize or revoke
    /// @param _authorized True to authorize the operator, false to revoke authorization
    /// @custom:throws SupergroupInvalidOperator if operator is zero address or SENTINEL
    function _setAuthorizedOperator(address _operator, bool _authorized) internal {
        if (_operator == address(0) || _operator == SENTINEL) {
            revert SupergroupInvalidOperator(_operator);
        }

        // Initialize the linked list if it hasn't been already
        if (operators[SENTINEL] == address(0)) {
            operators[SENTINEL] = SENTINEL;
        }

        // Current states
        bool isInLinkedList = operators[_operator] != address(0);
        bool isAuthorizedInHub = hub.isApprovedForAll(address(this), _operator);

        // If desired state matches both current states, no action needed
        if (_authorized == isInLinkedList && _authorized == isAuthorizedInHub) {
            return;
        }

        // Update linked list to match desired state
        if (_authorized && !isInLinkedList) {
            // Add to linked list
            operators[_operator] = operators[SENTINEL];
            operators[SENTINEL] = _operator;
        } else if (!_authorized && isInLinkedList) {
            // Remove from linked list
            _removeOperator(_operator);
        }

        // Update hub authorization if it doesn't match desired state
        if (_authorized != isAuthorizedInHub) {
            hub.setApprovalForAll(_operator, _authorized);
        }
    }

    function _setMintFee(uint256 _mintFee, address _feeCollection) internal {
        if (_mintFee > 0 && _feeCollection == address(0)) {
            // if a fee is levied, collection address cannot be zero
            revert SupergroupInvalidCallingParameters();
        }

        if (_mintFee > MAX_RATIO) {
            revert SupergroupInvalidCallingParameters();
        }

        if (_mintFee > 0) {
            // if a minting fee is set, then operators are required,
            // because explicit hub.groupMint could by-pass the fee
            // when not done over operators.
            _requireOperator(true);
        }

        mintFee = _mintFee;
        feeCollection = _feeCollection;

        emit MintFeeSet(feeCollection, mintFee);
    }

    function _setRedemptionBurn(uint256 _burnRedemptionRate) internal {
        if (_burnRedemptionRate > MAX_RATIO) {
            revert SupergroupInvalidCallingParameters();
        }

        emit RedemptionBurnRateUpdated(redemptionBurnRatio);
    }

    function _requireOperator(bool _required) internal {
        if (_required) {
            if (countOperators() > 0) {
                revert SupergroupMustHaveOperatorsActivated();
            }
        }

        requireOperator = _required;

        emit OperatorsRequired(_required);
    }

    /// @dev Splits a given amount into return and fee based on the provided fee ratio.
    function _splitAmountInReturnAndFee(uint256 _amount, uint256 _feeRatio)
        internal
        pure
        returns (uint256 _returnAmount, uint256 _fee)
    {
        _returnAmount = (_amount * _feeRatio) / 1 ether;
        _fee = _amount - _returnAmount;
    }

    /// @dev Removes an operator from the linked list
    /// @param _operator Address of the operator to remove
    function _removeOperator(address _operator) internal {
        address current = SENTINEL;
        while (operators[current] != SENTINEL) {
            if (operators[current] == _operator) {
                operators[current] = operators[_operator];
                operators[_operator] = address(0);
                return;
            }
            current = operators[current];
        }
        // only check after removal because _operator might not be included
        if (requireOperator && countOperators() == 0) {
            revert SupergroupMustHaveOperatorsActivated();
        }
    }

    function _groupId() internal view returns (uint256) {
        return uint256(uint160(address(this)));
    }
}
