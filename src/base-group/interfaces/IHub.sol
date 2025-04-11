// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "circles-contracts-v2/hub/IHub.sol";
import "circles-contracts-v2/hub/TypeDefinitions.sol";

interface IHub is IHubV2 {
    /// @notice registers group with Circles hub
    function registerGroup(address policy, string calldata name, string calldata symbol, bytes32 metadataDigest)
        external;
    function registerCustomGroup(
        address _mint,
        address _treasury,
        string calldata _name,
        string calldata _symbol,
        bytes32 _metadataDigest
    ) external;
    /// @notice register organization with Circles hub
    function registerOrganization(string calldata name, bytes32 metadataDigest) external;
    /// @notice trust sets the trust of the caller for the receiver with an expiry time.
    function trust(address _trustReceiver, uint96 _expiry) external;
    /// @notice isTrusted returns true if the expiry time of the trust relation is in the future
    function isTrusted(address truster, address trustee) external returns (bool);
    /// @notice Trustmarkers returns (iterator, expiry uint96)
    function trustMarkers(address, address) external returns (TypeDefinitions.TrustMarker memory);
    /// @notice treasuries returns the collateral treasury of the group
    function treasuries(address) external returns (address);
    /// @notice sets advanced usage flags
    function setAdvancedUsageFlag(bytes32 flag) external;
    /// @notice groupMint allows the holder of collateral to directly group mint
    function groupMint(
        address group,
        address[] calldata collateralAvatars,
        uint256[] calldata amounts,
        bytes calldata data
    ) external;
    function wrap(address _avatar, uint256 _amount, uint8 _type) external returns (address);
}
