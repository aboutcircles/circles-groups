// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

/// @notice Mapping of group address to vault address,
///         where the vault holds the group's collateral
interface IStandardTreasury {
    function vaults(address group) external view returns (address);
}
