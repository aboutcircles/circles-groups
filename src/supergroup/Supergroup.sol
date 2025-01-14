// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "circles-contracts-v2/hub/IHub.sol";
import "src/errors/Errors.sol";
import "./BaseGroupPolicy.sol";

/// @notice Supergroups are opinionated liquidity clusters of valued Circles
/// Supergroups follow a pattern where the group avatar is a contract address
/// that registers itself as the group and acts as a policy at the same time.
/// This pattern allows the group to have transparant behaviour.
/// Furthermore, this supergroup contract is intended to be used as an implementation
/// for a (renounceable) proxy contract, so the constructor blocks
/// the mastercopy deployment, and the proxy should call setup to configure the state
contract Supergroup is BaseGroupPolicy, ISupergroupProxyErrors {
    // State variables

    /// @notice Hub contract
    IHubV2 public hub;
    /// @notice Treasury contract collects group minting fees when enabled
    address public treasury;

    /// @notice

    // Constructor

    constructor() {
        // set hub to 0x01 to block the mastercopy deployment from functioning
        hub = IHubV2(address(1));
    }

    // Setup

    function setup(IHubV2 _hub, address _treasury) external {
        if (address(hub) != address(0)) {
            // Supergroup already initialised
            revert SupergroupProxyAlreadyInitialised();
        }

        // set the treasury once during setup
        treasury = _treasury;
    }

    function beforeMintPolicy(
        address _minter,
        address _group,
        uint256[] calldata _collateral,
        uint256[] calldata _amounts,
        bytes calldata _data
    ) external virtual override returns (bool) {
        // only allow minting if the minter is a trusted human by this group
        if (!hub.isTrusted(_group, _minter)) {
            super.beforeMintPolicy(
                _minter,
                _group,
                _collateral,
                _amounts,
                _data
            );
        }
        return true;
    }
}
