// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {BaseGroupFactory} from "src/base-group/BaseGroupFactory.sol";

contract DeployGroupFactory is Script {
    address deployer = address(0x915aec9009a847a8EB1f65bA87dC02742E37B9D1);
    BaseGroupFactory public baseGroupFactory; // 0x9d3232483A40A5149a2600A5b6Fb85CFddc487b6

    function setUp() public {}

    function run() public {
        vm.startBroadcast(deployer);

        baseGroupFactory = new BaseGroupFactory();

        vm.stopBroadcast();
        console.log(address(baseGroupFactory), "BaseGroupFactory");
    }
}