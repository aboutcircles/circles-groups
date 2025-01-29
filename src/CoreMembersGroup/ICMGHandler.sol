// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

interface ICMGHandler {
    /// @notice Safely transfers a single ERC1155 token through the Circles Hub.
    /// @dev Only callable by the owner of this contract. Reverts if _from is not this contract.
    /// @param from Source address
    /// @param to Destination address
    /// @param id Token id to transfer
    /// @param value Amount of tokens to transfer
    /// @param data Additional data with no specified format
    function safeTransferFrom(address from, address to, uint256 id, uint256 value, bytes calldata data) external;

    /// @notice Safely transfers a batch of ERC1155 tokens through the Circles Hub.
    /// @dev Only callable by the owner of this contract. Reverts if _from is not this contract.
    /// @param from Source address
    /// @param to Destination address
    /// @param ids Array of token ids to transfer
    /// @param values Array of token amounts to transfer
    /// @param data Additional data with no specified format
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external;

    /// @notice Sets advanced usage flags for this group in the Hub
    /// @param _flag Advanced usage flag value to set
    function setAdvancedUsageFlag(bytes32 _flag) external;

    /// @notice Updates the metadata digest for this group in the name registry
    /// @param _metadataDigest New metadata digest value
    function updateMetadataDigest(bytes32 _metadataDigest) external;

    /// @notice Registers a short name for this group in the name registry
    function registerShortName() external;

    /// @notice Registers a short name for this group with a specified nonce
    /// @param _nonce Nonce value to use for short name registration
    function registerShortNameWithNonce(uint256 _nonce) external;
}
