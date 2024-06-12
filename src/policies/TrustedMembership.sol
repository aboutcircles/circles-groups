// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.24;

import "circles-contracts-v2/hub/IHub.sol";
import "../guards/PathGuard.sol";

contract TrustedMembershipPolicy is PathGuard {
    // State variables

    IHubV2 hub;

    // Constructor

    constructor(IHubV2 _hub) {
        hub = _hub;
    }

    // External functions

    /**
     * @notice Simple mint policy that always returns true
     */
    function beforeMintPolicy(
        address _minter,
        address _group,
        uint256[] calldata _collateral,
        uint256[] calldata _amounts,
        bytes calldata _data
    ) external virtual override returns (bool) {
        // only allow minting if the minter is a trusted human by this group
        if (!hub.isTrusted(_group, _minter))

        super.beforeMintPolicy(_minter, _group, _collateral, _amounts, _data);
        return true;
    }
}