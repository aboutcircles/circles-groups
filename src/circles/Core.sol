// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "src/circles/IHub.sol";
import "src/circles/INameRegistry.sol";
import "src/circles/IStandardTreasury.sol";
import "circles-contracts-v2/lift/IERC20Lift.sol";

contract CirclesCoreAddresses {
    // Structs

    /// @notice CirclesCore defines core addresses of Circles
    ///         protocol to interact with it.
    struct CirclesCore {
        IHub hub;
        IStandardTreasury standardTreasury;
        INameRegistryExtended nameRegistry;
        IERC20Lift erc20Lift;
    }
}

/// @notice Circles Core Addresses list the constant addresses
///         of the deployed core contracts of Circles on Gnosis Chain.
contract CirclesV2BetaAddresses {
    // State

    // these constants can be verified on
    // https://gnosis.blockscout.com/address/0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8?tab=contract
    // note: keeping unused contract addresses for easy reference
    /// @dev Hub contract address
    IHub internal hub = IHub(address(0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8));
    /// @dev Standard Treasury
    IStandardTreasury internal standardTreasury = IStandardTreasury(address(0x08F90aB73A515308f03A718257ff9887ED330C6e));
    /// @dev Name Registry
    INameRegistryExtended internal nameRegistry =
        INameRegistryExtended(address(0xA27566fD89162cC3D40Cb59c87AAaA49B85F3474));
    /// @dev ERC20 Lift contract
    IERC20Lift internal erc20Lift = IERC20Lift(address(0x5F99a795dD2743C36D63511f0D4bc667e6d3cDB5));
    // /// @dev Migration contract to migrate Circles from Hub v1 to Hub v2
    // address internal migration = address(0xD44B8dcFBaDfC78EA64c55B705BFc68199B56376);
    // /// @dev the original Circles Hub v1 contract
    // address internal hubV1 = address(0x29b9a7fBb8995b2423a71cC17cf9810798F6C543);

    // Public functions

    function getCirclesCore() public view returns (CirclesCoreAddresses.CirclesCore memory) {
        return CirclesCoreAddresses.CirclesCore(hub, standardTreasury, nameRegistry, erc20Lift);
    }
}
