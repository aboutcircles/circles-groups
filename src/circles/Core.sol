// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "src/circles/IHub.sol";
import "src/circles/INameRegistry.sol";

/// @notice Circles Core Addresses list the constant addresses
///         of the deployed core contracts of Circles on Gnosis Chain.
contract CirclesCoreAddresses {
    // Constants

    // these constants can be verified on
    // https://gnosis.blockscout.com/address/0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8?tab=contract
    /// @dev Hub contract address
    IHub internal constant hub = IHub(address(0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8));
    /// @dev Name Registry
    INameRegistryExtended internal constant nameRegistry =
        INameRegistryExtended(address(0xA27566fD89162cC3D40Cb59c87AAaA49B85F3474));
    /// @dev Migration contract to migrate Circles from Hub v1 to Hub v2
    address internal constant migration = address(0xD44B8dcFBaDfC78EA64c55B705BFc68199B56376);
    /// @dev Lift ERC20 helps lift ERC1155 Circles out into an ERC20 wrapper contract
    address internal constant liftERC20 = address(0x5F99a795dD2743C36D63511f0D4bc667e6d3cDB5);
    /// @dev the original Circles Hub v1 contract
    address internal constant hubV1 = address(0x29b9a7fBb8995b2423a71cC17cf9810798F6C543);
}
