// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "circles-contracts-v2/hub/IHub.sol";

interface IHub is IHubV2 {
    /// @notice isTrusted returns true if the expiry time of the trust relation is in the future
    function isTrusted(address _truster, address _trustee) external returns (bool);
    /// @notice treasuries returns the collateral treasury of the group
    function treasuries(address) external returns (address);
}
