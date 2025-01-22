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
    ISupergroupErrors
{
    // Constants

    /// @notice Max fee is set to 2 out of 24, stored as a percentage.
    ///         With 18 decimals; 2/24 * 10**18 = 0,08333.. * 10**18
    uint256 public constant MAX_FEE = 83333333333333333;

    // Enum

    /// @notice Proxy status keeps an explicit byte about this state instance
    enum ProxyStatus {
        Uninitialised,
        Mastercopy,
        Setup
    }

    // State variables

    /// @notice Owner address. This is a copied value of ERC1967 ADMIN_SLOT
    ///         if this supergroup mastercopy is consumed by an ERC1067 proxy.
    ///         For simplicity and readability we duplicate owner with ERC1967 admin,
    ///         even if for the intended deployment they are the same address.
    address public owner;
    /// @notice Service address. The service is limited to trusting (or untrusting) avatars.
    address public service;
    /// @notice Launchpad enables people to back their personal CRC in an LBP pool.
    ///         This first supergroup will explicitly check the launchpad whether
    ///         a person has backed their Circles. This is a specific opinion on what
    ///         a supergroup can be, so (todo) in later work, factor this out better.
    address public launchpad;
    /// @notice Require an authorized operator to register group mint requests ahead,
    ///         so that advanced checks can be performed by the operator.
    ///         Also when a fee is charged, this must be enforced by the operator, so
    ///         setting a fee will enable this requirement for operators to gatekeep the groupmint.
    bool public requireOperator = false;
    /// @notice Return group Circles to sender, when true, will send group Circles
    ///         back to the original sender of a path, if collateral was sent to the group
    ///         as an end-receiver
    bool public returnGroupCirclesToSender = true;
    /// @notice fee levied upon group minting can be between zero and MAX_FEE (1/12th)
    ///         of the amount minted. Setting the fee to zero disables the fee charge.
    ///         When the fee is charged, group mint MUST happen over (an) authorized
    ///         operator - and the owner must ensure that all authorized operators
    ///         enforce the fee (as the hub won't charge a fee).
    uint256 public fee = 0;
    /// @notice fee collection address collects group minting fees when enabled
    address public feeCollection;
    /// @dev We take Hub address from core constants, so we need a minimal variable to
    ///      track whether this state (mastercopy or proxy) has been constructed or setup.
    ProxyStatus public proxyStatus = ProxyStatus.Uninitialised;

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

    /// @notice Only owner or service can call
    modifier onlyOwnerOrService() {
        if (msg.sender != owner && msg.sender != service) {
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

    function setup(address _service, address _launchpad, uint256 _fee, address _feeCollection) external {
        if (proxyStatus != ProxyStatus.Uninitialised) {
            // contract state already initialised.
            revert SupergroupProxyAlreadyInitialised();
        }
        if (_service == address(0) || _launchpad == address(0)) {
            revert SupergroupInvalidCallingParameters();
        }
        if (_fee > 0 && _feeCollection == address(0)) {
            // if a fee is levied, collection address cannot be zero
            revert SupergroupInvalidCallingParameters();
        }

        // set the owner to the same address (msg.sender) as ERC1967 ADMIN_SLOT
        // in Renounceable proxy
        owner = msg.sender;

        // set the service key
        service = _service;
        // set the launchpad address (immutable in this impl)
        launchpad = _launchpad;

        // set the fee and fee collection address
        fee = _fee;
        feeCollection = _feeCollection;
    }

    function setAuthorizedOperator(address _operator, bool _authorized) external onlyOwner {
        hub.setApprovalForAll(_operator, _authorized);
        // event is already emitted and indexed for ERC1155 hub
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
        // redundant sanity-check that group is this group
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
        // the operator must be authorized by the supergroup to register request
        if (!hub.isApprovedForAll(address(this), msg.sender)) {
            revert SupergroupOnlyAuthorizedOperator();
        }
        _submitRequest(_minter, _group, _collateral, _amounts);
        return true;
    }

    // ERC1155 Acceptance Call handlers

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
            // return the same amount as gCRC to the sender
            hub.safeTransferFrom(address(this), _from, _groupId(), _value, _data);
        }
        return this.onERC1155Received.selector;
    }

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
            // return the same amount as gCRC to the sender
            hub.safeTransferFrom(address(this), _from, _groupId(), value, _data);
        }
        return this.onERC1155BatchReceived.selector;
    }

    // Internal functions

    function _groupId() internal view returns (uint256) {
        return uint256(uint160(address(this)));
    }
}
