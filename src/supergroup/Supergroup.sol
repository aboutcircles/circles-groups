// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "src/operator/IOperator.sol";
import "src/circles/Core.sol";
import "src/errors/Errors.sol";
import "src/policies/PolicyTypes.sol";
import "src/supergroup/BaseGroupPolicy.sol";

/// @notice Supergroups are opinionated liquidity clusters of valued Circles
/// Supergroups follow a pattern where the group avatar is a contract address
/// that registers itself as the group and acts as a policy at the same time.
/// This pattern allows the group to have transparant behaviour.
/// Furthermore, this supergroup contract is intended to be used as an implementation
/// for a (renounceable) proxy contract, so the constructor blocks
/// the mastercopy deployment, and the proxy should call setup to configure the state.
contract Supergroup is BaseGroupPolicy, CirclesCoreAddresses, ISupergroupErrors {
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
    /// @notice Service address. The service is limited to trusting (or untrusting) avatars
    address public service;
    /// @notice Launchpad enables people to back their personal CRC in an LBP pool.
    ///         This first supergroup will explicitly check the launchpad whether
    ///         a person has backed their Circles. This is a specific opinion on what
    ///         a supergroup can be, so (todo) in later work, factor this out better.
    address public launchpad;
    /// @notice Exclusive operator is the only authorized operator that can request a group mint
    ///         when a fee is enabled.
    /// @dev Because the path transfer does not pass `data` to the mint policy call,
    ///      we only have the parameters of the mint policy hook to identify a request
    ///      and this does not include an operator address, so for now resign to a single
    ///      operator, so the policy knows which operator to validate a request against.
    IOperator public exclusiveOperator;
    /// @notice fee levied upon group minting can be between zero and MAX_FEE (1/12th)
    ///         of the amount minted. Setting the fee to zero disables the fee charge.
    ///         When the fee is charged, group mint MUST happen over (an) authorized
    ///         operator - and the owner must ensure that all authorized operators
    ///         enforce the fee (as the hub won't charge a fee).
    uint256 public fee = 0;
    /// @notice fee collection contract collects group minting fees when enabled
    address public feeCollection;
    /// @dev We take Hub address from core constants, so we need a minimal variable to
    ///      track whether this state (mastercopy or proxy) has been constructed or setup.
    ProxyStatus public proxyStatus = ProxyStatus.Uninitialised;

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

    function setExclusiveOperator(address _operator, bool _authorized) external {
        if (_operator == address(0)) revert SupergroupInvalidCallingParameters();

        if (address(exclusiveOperator) != _operator && address(exclusiveOperator) != address(0)) {
            // disable existing exclusive operator
            hub.setApprovalForAll(address(exclusiveOperator), false);
        }

        // store exclusive operator (unfortunately)
        exclusiveOperator = _authorized ? IOperator(_operator) : IOperator(address(0));
        hub.setApprovalForAll(_operator, _authorized);
        // event is already emitted and indexed for ERC1155 hub
    }

    function beforeMintPolicy(
        address _minter,
        address _group,
        uint256[] calldata _collateral,
        uint256[] calldata _amounts,
        bytes calldata _data
    ) external virtual override returns (bool) {
        // redundant sanity-check that group is this group
        if (_group != address(this)) {
            return false;
        }
        // if a fee is enabled, only authorized operators
        // can initiate a group mint request
        if (fee > 0) {
            // for explicit groupmint from the operator, we could short-cut
            // because the _minter is the operator address,
            // but for the path-triggered groupmint, we need to request the
            // operator whether this was "signed off by them".
            // So for clarity, we use the same pattern for both.
        }
        return true;
    }

    // Internal functions

    /// @dev validate operator request checks that the data decodes to an operator request
    function _validateOperatorRequest(bytes memory _data) internal view returns (bool) {
        PolicyTypes.OperatorRequest memory request = abi.decode(_data, (PolicyTypes.OperatorRequest));

        // verify the operator is authorized
        if (!hub.isApprovedForAll(address(this), request.operator)) {
            return false;
        }
    }
}
