// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "src/CoreMembersGroup/helpers/UpgradeableRenounceableProxy.sol";
import "src/projects/ces/CESgroup.sol";
import "src/CoreMembersGroup/CMGMintHandler.sol";

contract CESDeployer {
    // State variables

    /// @notice address of the deployed mastercopy for the CES group
    CESgroup public masterCopyCESGroup;

    // Events

    /// @notice Emitted when a new CES group proxy is deployed
    /// @param proxy Address of the deployed proxy contract
    /// @param owner Owner of the new group
    /// @param mintHandler Address of the mintHandler contract
    event CESGroupCreated(address indexed proxy, address indexed owner, address indexed mintHandler);

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
        // group and mintHandler owner by caller
        address owner = msg.sender;
        // first deploy proxy to obtain address, but don't yet initialise by calling setup
        UpgradeableRenounceableProxy proxy = new UpgradeableRenounceableProxy(owner, address(masterCopyCESGroup), "");
        // instead first set up the mintHandler
        CMGMintHandler mintHandler = new CMGMintHandler(address(proxy), owner, _name);
        // lastly, call setup on the proxy to initialise the group
        CESgroup(address(proxy)).setup(owner, address(mintHandler), _service, _name, _symbol, _metadataDigest);

        emit CESGroupCreated(address(proxy), owner, address(mintHandler));
        return address(proxy);
    }
}
