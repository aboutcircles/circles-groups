// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "src/circles/Core.sol";
import "src/liquidity-provider/GroupLiquidityProvider.sol";
import "src/redemption-operator/CMGRedemptionOperator.sol";

contract GroupLiquidityProviderDeployer is CirclesCoreAddresses {
    // State variables

    /// @notice redemption operator used by all liquidity providers
    CMGRedemptionOperator public immutable redemptionOperator;

    /// @notice core Circles protocol addresses
    CirclesCore public circlesCore;

    // Events

    /// @notice Emitted when a new Liquidity Provider is deployed
    /// @param liquidityProvider Address of the deployed liquidity provider
    /// @param group Group the liquidity provider serves
    /// @param owner Owner of the liquidity provider
    /// @param redemptionOperator Address of the redemption operator used
    event LiquidityProviderCreated(
        address indexed liquidityProvider, address indexed group, address indexed owner, address redemptionOperator
    );

    // Constructor

    constructor(CMGRedemptionOperator _redemptionOperator, CirclesCore memory _circlesCore) {
        redemptionOperator = _redemptionOperator;
        circlesCore = _circlesCore;
    }

    // External functions

    /// @notice Create liquidity provider organization for a group
    /// @param _group The group to create a liquidity provider for
    /// @param _name Name of the liquidity provider organization
    /// @param _metadataDigest Metadata digest for the organization
    function createLiquidityProvider(address _group, string memory _name, bytes32 _metadataDigest)
        external
        returns (address)
    {
        // deploy liquidity provider passing owner and group address
        GroupLiquidityProvider liquidityProvider =
            new GroupLiquidityProvider(_group, msg.sender, _name, _metadataDigest, circlesCore, redemptionOperator);

        emit LiquidityProviderCreated(address(liquidityProvider), _group, msg.sender, address(redemptionOperator));
        return address(liquidityProvider);
    }

    /// @notice Create liquidity provider organization for a group with custom redemption operator
    /// @param _group The group to create a liquidity provider for
    /// @param _name Name of the liquidity provider organization
    /// @param _metadataDigest Metadata digest for the organization
    /// @param _redemptionOperator Custom redemption operator address
    function createLiquidityProviderWithCustomRedemptionOperator(
        address _group,
        string memory _name,
        bytes32 _metadataDigest,
        CMGRedemptionOperator _redemptionOperator
    ) external returns (address) {
        // deploy liquidity provider passing owner and group address
        GroupLiquidityProvider liquidityProvider =
            new GroupLiquidityProvider(_group, msg.sender, _name, _metadataDigest, circlesCore, _redemptionOperator);

        emit LiquidityProviderCreated(address(liquidityProvider), _group, msg.sender, address(_redemptionOperator));
        return address(liquidityProvider);
    }
}
