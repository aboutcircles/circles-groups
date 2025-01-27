// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "src/CoreMembersGroup/helpers/UpgradeableRenounceableProxy.sol";
import "src/CoreMembersGroup/CoreMembersGroup.sol";
import "src/CoreMembersGroup/CMAncillary.sol";

contract CMGroupDeployer {
    // State variables

    /// @notice address of the deployed mastercopy for the CMGroup
    CoreMembersGroup public masterCopyCMGroup;

    // Constructor

    constructor() {
        // deploy a master copy for Core Members group
        masterCopyCMGroup = new CoreMembersGroup();
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
        return address(proxy);
    }
}
