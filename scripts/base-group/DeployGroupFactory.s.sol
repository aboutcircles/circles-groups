// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {BaseGroupFactory} from "src/base-group/BaseGroupFactory.sol";

contract DeployGroupFactory is Script {
    address deployer = address(0x2D75A44e14C660fc5d4d30B22aE133b244D6D30B);
    BaseGroupFactory public baseGroupFactory; // 0x452C116060cBB484eeDD70F32F08aD4F0685B5D2 rings

    function setUp() public {}

    function run() public {
        vm.startBroadcast(deployer);

        baseGroupFactory = new BaseGroupFactory();

        vm.stopBroadcast();
        console.log(address(baseGroupFactory), "BaseGroupFactory");
    }
}