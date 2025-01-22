// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "circles-contracts-v2/hub/IHub.sol";

interface IHub is IHubV2 {
    /// @notice registers group with Circles hub
    function registerGroup(address policy, string calldata name, string calldata symbol, bytes32 metadataDigest)
        external;
    /// @notice trust sets the trust of the caller for the receiver with an expiry time.
    function trust(address _trustReceiver, uint96 _expiry) external;
    /// @notice isTrusted returns true if the expiry time of the trust relation is in the future
    function isTrusted(address truster, address trustee) external returns (bool);
    /// @notice treasuries returns the collateral treasury of the group
    function treasuries(address) external returns (address);
}
