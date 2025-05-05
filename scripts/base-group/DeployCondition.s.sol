// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {CirclesBackingCondition} from "src/membership-conditions/CirclesBackingCondition.sol";

contract DeployCondition is Script {
    address deployer = address(0xaAb15A045e74c6539B696B115e763A22BE5C9594);
    CirclesBackingCondition public circlesBackingCondition; // 0xA88553421CED59Ff886A79855A7B9AA16417335B

    function setUp() public {}

    function run() public {
        vm.startBroadcast(deployer);

        circlesBackingCondition = new CirclesBackingCondition();

        vm.stopBroadcast();
        console.log(address(circlesBackingCondition), "CirclesBackingCondition");
    }
}