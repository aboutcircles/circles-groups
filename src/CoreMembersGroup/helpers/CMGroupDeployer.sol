// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "src/CoreMembersGroup/helpers/UpgradeableRenounceableProxy.sol";
import "src/CoreMembersGroup/CoreMembersGroup.sol";
import "src/CoreMembersGroup/CMAncillary.sol";

contract CMGroupDeployer {
    // State variables

    /// @notice address of the deployed mastercopy for the CMGroup
    CoreMembersGroup public masterCopyCMGroup;

    // Events

    /// @notice Emitted when a new CMGroup proxy is deployed
    /// @param proxy Address of the deployed proxy contract
    /// @param owner Owner of the new group
    /// @param ancillary Address of the ancillary contract
    event CMGroupCreated(address indexed proxy, address indexed owner, address indexed ancillary);

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
    function createCMGroup(address _service, string calldata _name, string calldata _symbol, bytes32 _metadataDigest)
        external
        returns (address)
    {
        // first deploy proxy to obtain address, but don't yet initialise by calling setup
        UpgradeableRenounceableProxy proxy =
            new UpgradeableRenounceableProxy(msg.sender, address(masterCopyCMGroup), "");
        // instead first set up the ancillary
        CMAncillary ancillary = new CMAncillary(address(proxy), _name);
        // lastly, call setup on the proxy to initialise the group
        CoreMembersGroup(address(proxy)).setup(
            msg.sender, address(ancillary), _service, _name, _symbol, _metadataDigest
        );

        emit CMGroupCreated(address(proxy), msg.sender, address(ancillary));
        return address(proxy);
    }
}
