// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import "src/core-members-group/helpers/CMGroupDeployer.sol";

contract DeployCMGDeployer is Script {
    address deployer = address(0x6F939041650e72855018678002c9b8F8AfAD95Da);
    address standardTreasury = address(0xd89538F85220893289526d36a80eBdD123A5b7A8);
    CMGroupDeployer public cmgDeployer; // 0xb345f161B20E558BAaa013A635f95d2e21DF196F
    // CMG mastercopy 0xC0CED093F1dD09c1061Fc03F13dcb8b810A903F3

    function setUp() public {}

    function run() public {
        vm.startBroadcast(deployer);
        cmgDeployer = new CMGroupDeployer(standardTreasury);

        vm.stopBroadcast();
        console.log(address(cmgDeployer), "CMGroupDeployer");
    }
}