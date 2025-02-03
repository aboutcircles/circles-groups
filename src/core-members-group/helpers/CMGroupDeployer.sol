// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "src/core-members-group/helpers/UpgradeableRenounceableProxy.sol";
import "src/core-members-group/CoreMembersGroup.sol";
import "src/core-members-group/CMGMintHandler.sol";
import "src/core-members-group/CMGRedemptionHandler.sol";

contract CMGroupDeployer {
    // State variables

    /// @notice address of the deployed mastercopy for the CMGroup
    CoreMembersGroup public masterCopyCMGroup;

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
        // deploy a master copy for Core Members group
        masterCopyCMGroup = new CoreMembersGroup();
        emit MasterCopyDeployed(address(masterCopyCMGroup));
    }

    // External functions

    /// @notice Create Core Members group for caller
    function createCMGroup(
        address _service,
        address[] memory _initialConditions,
        string memory _name,
        string memory _symbol,
        bytes32 _metadataDigest
    ) external returns (address) {
        // group and handlers owned by caller
        address owner = msg.sender;
        // first deploy proxy to obtain address, but don't yet initialise by calling setup
        UpgradeableRenounceableProxy proxy = new UpgradeableRenounceableProxy(owner, address(masterCopyCMGroup), "");
        // deploy the handlers
        CMGMintHandler mintHandler = new CMGMintHandler(address(proxy), owner, _name);
        CMGRedemptionHandler redemptionHandler = new CMGRedemptionHandler(address(proxy), owner, _name);
        // lastly, call setup on the proxy to initialise the group
        CoreMembersGroup(address(proxy)).setup(
            owner,
            _service,
            address(mintHandler),
            address(redemptionHandler),
            _initialConditions,
            _name,
            _symbol,
            _metadataDigest
        );

        emit CMGroupCreated(address(proxy), owner, address(mintHandler), address(redemptionHandler));
        return address(proxy);
    }
}
