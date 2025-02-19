// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "src/core-members-group/helpers/UpgradeableRenounceableProxy.sol";
import "src/core-members-group/CoreMembersGroup.sol";
import "src/core-members-group/CMGMintHandler.sol";
import "src/core-members-group/CMGRedemptionHandler.sol";
import "src/redemption-operator/CMGRedemptionOperator.sol";
import "src/circles/Core.sol";
import "src/circles/IHub.sol";
import "src/circles/INameRegistry.sol";
import "src/circles/IStandardTreasury.sol";
import "test/mock-circles/MockHub.sol";
import "test/mock-circles/MockStandardTreasury.sol";
import "test/mock-circles/MockVault.sol";

contract MockCirclesDeployment is CirclesCoreAddresses {
    // State

    MockHub public mockHub;
    MockStandardTreasury public mockStandardTreasury;
    /// @notice address of the deployed mastercopy for the CMGroup
    CoreMembersGroup public masterCopyCMGroup;
    /// @notice address of the deployed redemption operator
    CMGRedemptionOperator public redemptionOperator;

    // Events

    /// @notice Emitted when a new CMGroup proxy is deployed
    /// @param proxy Address of the deployed proxy contract
    /// @param owner Owner of the new group
    /// @param mintHandler Address of the mintHandler contract
    /// @param redemptionHandler Address of the redemptionHandler contract
    event CMGroupCreated(
        address indexed proxy, address indexed owner, address indexed mintHandler, address redemptionHandler
    );

    /// @notice Emitted when mastercopy is deployed in constructor
    /// @param mastercopy Address of the deployed mastercopy contract
    event MasterCopyDeployed(address indexed mastercopy);

    // Constructor

    constructor() {
        mockHub = new MockHub();
        mockStandardTreasury = mockHub.standardTreasury();

        // deploy a master copy for Core Members group
        masterCopyCMGroup = new CoreMembersGroup();
        emit MasterCopyDeployed(address(masterCopyCMGroup));

        // deploy redemption operator
        redemptionOperator = new CMGRedemptionOperator(getCirclesCore());
    }

    function getCirclesCore() public view returns (CirclesCore memory) {
        return CirclesCore(
            IHub(address(mockHub)), IStandardTreasury(address(mockStandardTreasury)), INameRegistryExtended(address(0))
        );
    }

    function createCMGroup(
        address _service,
        address[] memory _initialConditions,
        string memory _name,
        string memory _symbol,
        bytes32 _metadataDigest
    ) external returns (address) {
        // load Circles mock core addresses
        CirclesCore memory circlesMockCore = getCirclesCore();
        // group and handlers owned by caller
        address owner = msg.sender;
        // first deploy proxy to obtain address, but don't yet initialise by calling setup
        UpgradeableRenounceableProxy proxy = new UpgradeableRenounceableProxy(owner, address(masterCopyCMGroup), "");
        // deploy the handlers
        CMGMintHandler mintHandler = new CMGMintHandler(address(proxy), owner, _name, circlesMockCore);
        CMGRedemptionHandler redemptionHandler = new CMGRedemptionHandler(address(proxy), owner, circlesMockCore);
        // lastly, call setup on the proxy to initialise the group
        CoreMembersGroup(address(proxy)).setup(
            owner,
            _service,
            address(mintHandler),
            address(redemptionHandler),
            _initialConditions,
            _name,
            _symbol,
            _metadataDigest,
            circlesMockCore
        );

        emit CMGroupCreated(address(proxy), owner, address(mintHandler), address(redemptionHandler));
        return address(proxy);
    }
}
