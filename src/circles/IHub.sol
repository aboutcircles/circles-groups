// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "circles-contracts-v2/hub/IHub.sol";

interface IHub is IHubV2 {
    /// @notice treasuries returns the collateral treasury of the group
    function treasuries(address) external returns (address);
}
