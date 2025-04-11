// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "circles-contracts-v2/names/INameRegistry.sol";

interface INameRegistryExtended is INameRegistry {
    /// @notice updates metadata digest
    function updateMetadataDigest(bytes32 metadataDigest) external;
    /// @notice registers short name
    function registerShortName() external;
    /// @notice registers short name with nonce
    function registerShortNameWithNonce(uint256 nonce) external;
}
