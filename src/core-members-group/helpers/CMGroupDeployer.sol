// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "src/circles/Core.sol";
import "src/core-members-group/helpers/UpgradeableRenounceableProxy.sol";
import "src/core-members-group/CoreMembersGroup.sol";
import "src/core-members-group/CMGMintHandler.sol";
import "src/core-members-group/CMGRedemptionHandler.sol";
import "src/redemption-operator/CMGRedemptionOperator.sol";
import "src/liquidity-provider/helpers/GroupLiquidityProviderDeployer.sol";

contract CMGroupDeployer is CirclesCoreAddresses, CirclesV2BetaAddresses {
    // State variables

    /// @notice address of the deployed mastercopy for the CMGroup
    CoreMembersGroup public masterCopyCMGroup;

    /// @notice deployer for liquidity providers
    GroupLiquidityProviderDeployer public immutable lpDeployer;

    /// @notice redemption operator used by liquidity providers
    CMGRedemptionOperator public immutable redemptionOperator;

    // Events

    /// @notice Emitted when a new CMGroup proxy is deployed
    /// @param proxy Address of the deployed proxy contract
    /// @param owner Owner of the new group
    /// @param mintHandler Address of the mintHandler contract
    /// @param redemptionHandler Address of the redemptionHandler contract
    /// @param liquidityProvider Address of the (first) liquidity provider
    event CMGroupCreated(
        address indexed proxy,
        address indexed owner,
        address indexed mintHandler,
        address redemptionHandler,
        address liquidityProvider
    );

    /// @notice Emitted when mastercopy is deployed in constructor
    /// @param mastercopy Address of the deployed mastercopy contract
    event MasterCopyDeployed(address indexed mastercopy);

    // Constructor

    constructor() {
        // deploy a master copy for Core Members group
        masterCopyCMGroup = new CoreMembersGroup();
        emit MasterCopyDeployed(address(masterCopyCMGroup));

        // create deployer for liquidity providers
        redemptionOperator = new CMGRedemptionOperator(getCirclesCore());
        lpDeployer = new GroupLiquidityProviderDeployer(redemptionOperator, getCirclesCore());
    }

    // External functions
    /// @notice Create Core Members group for caller
    /// @return proxy Address of the deployed proxy contract
    /// @return mintHandler Address of the deployed mint handler
    /// @return redemptionHandler Address of the deployed redemption handler
    /// @return liquidityProvider Address of the deployed liquidity provider
    function createCMGroup(
        address _service,
        address[] memory _initialConditions,
        string memory _name,
        string memory _symbol,
        bytes32 _metadataDigest
    ) external returns (address proxy, address mintHandler, address redemptionHandler, address liquidityProvider) {
        // load Circles v2 core protocol addresses
        CirclesCore memory circlesCore = getCirclesCore();
        // group and handlers owned by caller
        address owner = msg.sender;
        // first deploy proxy to obtain address, but don't yet initialise by calling setup
        proxy = address(new UpgradeableRenounceableProxy(owner, address(masterCopyCMGroup), ""));
        // deploy the handlers
        mintHandler = address(new CMGMintHandler(proxy, owner, _name, circlesCore));
        redemptionHandler = address(new CMGRedemptionHandler(proxy, owner, circlesCore));
        // lastly, call setup on the proxy to initialise the group
        CoreMembersGroup(proxy).setup(
            owner,
            _service,
            mintHandler,
            redemptionHandler,
            _initialConditions,
            _name,
            _symbol,
            _metadataDigest,
            circlesCore
        );

        // ensure static ERC20 wrapper is deployed for group
        circlesCore.erc20Lift.ensureERC20(proxy, CirclesType.Inflation);

        emit CMGroupCreated(proxy, owner, mintHandler, redemptionHandler, liquidityProvider);
    }
}
