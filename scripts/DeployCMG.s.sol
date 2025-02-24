// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import "src/core-members-group/helpers/CMGroupDeployer.sol";
import "src/core-members-group/CoreMembersGroup.sol";

contract DeployCMG is Script {
    address deployer = address(0x6F939041650e72855018678002c9b8F8AfAD95Da);
    CMGroupDeployer public cmgDeployer = CMGroupDeployer(address(0xb345f161B20E558BAaa013A635f95d2e21DF196F)); 
    address groupProxy; // 0x013D8f8227dCe534876bba8b3441cd93A7a241F9
    // mintHandler 0xaf041b224AA1363c50976C2970Ad52Cab4Ed62Cc
    // redeemHandler 0xC57Eb099f2a2198e29e0bF2B3447aEaAF93476d7 

    function setUp() public {}

    function run() public {
        vm.startBroadcast(deployer);
        // Deploy a CoreMembersGroup instance using the deployer.
        // In our deployer, the createCMGroup() function requires:
        // _service, _name, _symbol, _metadataDigest.
        address service = deployer;
        address[] memory initialConditions = new address[](1);
        initialConditions[0] = address(0x21e88dC236097b1E40B98fd0C996713FB60ecc24);
        string memory groupName = "TestTVS";
        string memory groupSymbol = "TTVS";
        bytes32 metadataDigest = bytes32(0);

        groupProxy = cmgDeployer.createCMGroup(service, initialConditions, groupName, groupSymbol, metadataDigest);

        vm.stopBroadcast();
        console.log(groupProxy, "CMGroup");
    }
}