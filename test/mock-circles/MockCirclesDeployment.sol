// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "src/core-members-group/helpers/UpgradeableRenounceableProxy.sol";
import "src/core-members-group/helpers/CoreMembersGroupUpgradeable.sol";
import "src/core-members-group/CMGMintHandler.sol";
import "src/core-members-group/CMGRedemptionHandler.sol";
import "src/redemption-operator/CMGRedemptionOperator.sol";
import "src/liquidity-provider/helpers/GroupLiquidityProviderDeployer.sol";
import "src/circles/Core.sol";
import "test/mock-circles/MockHub.sol";
import "test/mock-circles/MockStandardTreasury.sol";
import "test/mock-circles/MockVault.sol";

contract MockCirclesDeployment is CirclesCoreAddresses {
    // State

    MockHub public mockHub;
    MockStandardTreasury public mockStandardTreasury;
    /// @notice address of the deployed mastercopy for the CMGroup
    CoreMembersGroupUpgradeable public masterCopyCMGroup;
    /// @notice address of the deployed redemption operator
    CMGRedemptionOperator public redemptionOperator;
    /// @notice deployer for liquidity providers
    GroupLiquidityProviderDeployer public lpDeployer;

    // Events

    /// @notice Emitted when a new CMGroup proxy is deployed
    /// @param proxy Address of the deployed proxy contract
    /// @param owner Owner of the new group
    /// @param mintHandler Address of the mintHandler contract
    /// @param redemptionHandler Address of the redemptionHandler contract
    /// @param liquidityProvider Address of the liquidity provider
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
        mockHub = new MockHub();
        mockStandardTreasury = mockHub.standardTreasury();

        // deploy a master copy for Core Members group
        masterCopyCMGroup = new CoreMembersGroupUpgradeable();
        emit MasterCopyDeployed(address(masterCopyCMGroup));

        // deploy redemption operator
        redemptionOperator = new CMGRedemptionOperator(getCirclesCore());

        // create deployer for liquidity providers
        lpDeployer = new GroupLiquidityProviderDeployer(redemptionOperator, getCirclesCore());
    }

    function getCirclesCore() public view returns (CirclesCore memory) {
        return CirclesCore(
            IHub(address(mockHub)),
            IStandardTreasury(address(mockStandardTreasury)),
            INameRegistryExtended(address(0)),
            IERC20Lift(address(0))
        );
    }

    function createCMGroup(
        address _service,
        address[] memory _initialConditions,
        string memory _name,
        string memory _symbol,
        bytes32 _metadataDigest
    ) external returns (address proxy, address mintHandler, address redemptionHandler, address liquidityProvider) {
        // load Circles mock core addresses
        CirclesCore memory circlesMockCore = getCirclesCore();
        // group and handlers owned by caller
        address owner = msg.sender;
        // first deploy proxy to obtain address, but don't yet initialise by calling setup
        proxy = address(new UpgradeableRenounceableProxy(owner, address(masterCopyCMGroup), ""));
        // deploy the handlers
        mintHandler = address(new CMGMintHandler(proxy, owner, _name, circlesMockCore));
        redemptionHandler = address(new CMGRedemptionHandler(proxy, owner, circlesMockCore));
        // lastly, call setup on the proxy to initialise the group
        CoreMembersGroupUpgradeable(proxy).setup(
            owner,
            _service,
            mintHandler,
            redemptionHandler,
            _initialConditions,
            _name,
            _symbol,
            _metadataDigest,
            circlesMockCore
        );

        // deploy liquidity provider for owner
        string memory lpName = string.concat(_name, "-lp");
        liquidityProvider = lpDeployer.createLiquidityProvider(proxy, lpName, bytes32(0));

        // in mock don't deploy erc20 static wrapper -- not mocked

        emit CMGroupCreated(proxy, owner, mintHandler, redemptionHandler, liquidityProvider);
    }
}
