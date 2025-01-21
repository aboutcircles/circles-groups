// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "openzeppelin-contracts/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "circles-contracts-v2/groups/BaseMintPolicy.sol";
import "src/circles/Core.sol";
import "src/errors/Errors.sol";
import "src/operator/IOperator.sol";
import "src/policies/PolicyTypes.sol";
import "src/supergroup/OperatorRequest.sol";

/// @notice Supergroups are opinionated liquidity clusters of valued Circles
///         Supergroups follow a pattern where the group avatar is a contract address
///         that registers itself as the group and acts as a policy at the same time.
///         This pattern allows the group to have transparant behaviour.
///         Furthermore, this supergroup contract is intended to be used as an implementation
///         for a (renounceable) proxy contract, so the constructor blocks
///         the mastercopy deployment, and the proxy should call setup to configure the state.
contract Supergroup is MintPolicy, OperatorRequest, ERC1155Holder, CirclesCoreAddresses, ISupergroupErrors {
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

    function setAuthorizedOperator(address _operator, bool _authorized) external {
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
        // if a fee is enabled, only authorized operators
        // can initiate a group mint request and must have registered a request
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
        return true;
    }

    /// @notice Authorized operators can register a request to mint group currency
    ///         within the same transaction, by preregistering the parameters of the request
    ///         before initiating the hub either explicitly or over a path).
    ///         This can be called multiple times for multiple group mints along a path
    ///         (eg. different collateral arriving at the group) but the parameters
    ///         need to be unique within the transaction.
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
    //
    // note: it is not a recommended pattern for the group itself to handle this in the acceptance call
    //       instead it is much cleaner, easier and more transparant to handle this in operators only.
    //       However,

    /// @dev There two scenarios under which a group registered in the hub
    ///      can receive the `onERC1155(Batch)Received` acceptance call from Circles hub:
    ///         1. when some does a standard ERC1155 `safe(Batch)TransferFrom` of any Circles id, including the groups own id.
    ///            The group should not accept tokens in general to prevent tokens accidentally getting locked.
    ///            The ERC1155 standard requires us to revert acceptance handler (not simply return the tokens to sender).
    ///         2. when a path transfer has a stream which terminates at the group, then hub will perform an acceptance call
    ///            `onERC1155(Batch)Received` with the terminal edges that sum to the total amount received.
    ///            However, during a path transfer, when an edge transfers tokens to a group it is interpreted as a request
    ///            to group mint the collateral. So by the time the acceptance call is performed, the group does not hold
    ///            the separate collateral ids from the acceptance call, but the sum as newly minted group Circles
    ///            - the collateral was transfered to the treasury for the group rather than to the group.
    ///     In the first case, the group should revert the acceptance call to avoid tokens being locked;
    ///     in the second situation we should automatically return the newly minted group Circles to the original sender
    ///     of the stream, if `returnGroupCirclesToSender` is true.
    ///
    ///     Note that when an explicit group mint is performed over `hub.groupMint()` the group Circles minted are given
    ///     directly to the caller, and there is no acceptance call for the group.
    ///
    ///     To protect that the acceptance handler never sends out tokens other than those that were minted
    ///     during a given transaction (which can be composed of normal ERC1155 transfers to the group and path transfers)
    ///     transient storage can account for the newly minted group tokens and subtract any returns in acceptance call.
    ///     This way this handler can also work in situations where the group holds Circles balances itself.
    ///
    ///     To simplify the implementation here, we require that:
    ///         - the group must not hold any Circles balance (outside the scope of a transaction) and
    ///         - the received id is trusted (probably redundant)
    ///         - the group's balance of the Circles id in the acceptance call is actually zero
    ///           (ie. it is in the groups treasury and in exchange the group holds at least this many gCRC)
    ///     This evaluation function will under these conditions not revert.
    function onERC1155Received(address _operator, address _from, uint256 _id, uint256 _value, bytes memory _data)
        public
        override virtual
        onlyHub
        returns (bytes4)
    {
        // Likely redundant sanity-check to always block ids that are not trusted or our own id.
        if (_id == _groupId || !hub.isTrusted(address(this), address(uint160(_id)))) {
            revert SupergroupAlwaysBlockUntrustedIds();
        }
        // check that the tokens from the acceptance call are in fact in the treasury, not held by the group.
        uint256 balanceMustBeZero = hub.balanceOf(address(this), _id);
        if (balanceMustBeZero != uint256(0)) {
            revert SupergroupBlockNormalERC1155Transfers();
        }
        // the supergroup MUST never hold balances beyond temporarily during transactions,
        // as this construction is not a recommended pattern.
        // The only recommended pattern is the use of operators, to handle things like "return gCRC to Alice"
        hub.safeTransferFrom(address(this), _from, _groupId(), _value, "");
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address _operator,
        address _from,
        uint256[] memory _ids,
        uint256[] memory _values,
        bytes memory _data
    ) public override virtual onlyHub returns (bytes4) {
        uint256 groupCrcValue = 0;
        uint256 length = _ids.length;
        address[] memory copiesOfMe = new address[](_ids.length);
        for (uint256 i = 0; i < length; i++) {
            copiesOfMe[i] = address(this);
            if (_ids[i] == _groupId || !hub.isTrusted(address(this), address(uint160(_ids[i])))) {
                revert SupergroupAlwaysBlockUntrustedIds();
            }
        }
        uint256[] memory balancesMustBeZero = hub.balanceOfBatch(copiesOfMe, _ids);
        for (uint256 i = 0; i < balancesMustBeZero.length; i++) {
            // check that the tokens received are all in the treasury and not held by the group.
            if (balancesMustBeZero[i] != uint256(0)) {
                revert SupergroupBlockNormalERC1155Transfers();
            }
            // and track the total of collateral received, for the total amount of gCRC
            groupCrcValue += _values[i];
        }
        // the group MUST never hold balances so that this can only send gCRC it minted.
        hub.safeTransferFrom(address(this), _from, _groupId(), groupCrcValue, "");
        return this.onERC1155BatchReceived.selector;
    }

    // Internal functions

    function _groupId() internal pure returns uint256 {
        return uint256(uint160(address(this)));
    }
}
