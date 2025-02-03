// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "src/core-members-group/helpers/UpgradeableRenounceableProxy.sol";
import "src/membership-conditions/projects/ces/CESgroup.sol";
import "src/core-members-group/CMGMintHandler.sol";
import "src/core-members-group/CMGRedemptionHandler.sol";

contract CESDeployer {
    // State variables

    /// @notice address of the deployed mastercopy for the CES group
    CESgroup public masterCopyCESGroup;

    // Events

    /// @notice Emitted when a new CES group proxy is deployed
    /// @param proxy Address of the deployed proxy contract
    /// @param owner Owner of the new group
    /// @param mintHandler Address of the mintHandler contract
    /// @param redemptionHandler Address of the redemptionHandler contract
    event CESGroupCreated(
        address indexed proxy, address indexed owner, address indexed mintHandler, address redemptionHandler
    );

    /// @notice Emitted when mastercopy is deployed in constructor
    /// @param mastercopy Address of the deployed mastercopy contract
    event MasterCopyDeployed(address indexed mastercopy);

    // Constructor

    constructor() {
        // deploy a master copy for CES group
        masterCopyCESGroup = new CESgroup();
        emit MasterCopyDeployed(address(masterCopyCESGroup));
    }

    // External functions

    /// @notice Create CES group for caller
    function createCESGroup(address _service, string calldata _name, string calldata _symbol, bytes32 _metadataDigest)
        external
        returns (address)
    {
        // group and handlers owned by caller
        address owner = msg.sender;
        // first deploy proxy to obtain address, but don't yet initialise by calling setup
        UpgradeableRenounceableProxy proxy = new UpgradeableRenounceableProxy(owner, address(masterCopyCESGroup), "");
        // deploy the handlers
        CMGMintHandler mintHandler = new CMGMintHandler(address(proxy), owner, _name);
        CMGRedemptionHandler redemptionHandler = new CMGRedemptionHandler(address(proxy), owner, _name);
        // lastly, call setup on the proxy to initialise the group
        CESgroup(address(proxy)).setup(
            owner, _service, address(mintHandler), address(redemptionHandler), _name, _symbol, _metadataDigest
        );

        emit CESGroupCreated(address(proxy), owner, address(mintHandler), address(redemptionHandler));
        return address(proxy);
    }
}
