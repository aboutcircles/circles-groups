// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {CirclesBackingCondition} from "src/membership-conditions/CirclesBackingCondition.sol";
import {IsHumanCondition} from "src/membership-conditions/IsHumanCondition.sol";

contract DeployCondition is Script {
    address deployer = address(0xaAb15A045e74c6539B696B115e763A22BE5C9594);
    address hub = address(0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8);
    CirclesBackingCondition public circlesBackingCondition; // 0xA88553421CED59Ff886A79855A7B9AA16417335B
    IsHumanCondition public isHumanCondition; // 0xFd8fEd5ACfb4e4eA045Eee1C8cA2705a942655C6

    function setUp() public {}

    function run() public {
        vm.startBroadcast(deployer);

        circlesBackingCondition = new CirclesBackingCondition();

        isHumanCondition = new IsHumanCondition(hub);

        vm.stopBroadcast();
        console.log(address(circlesBackingCondition), "CirclesBackingCondition");
        console.log(address(isHumanCondition), "IsHumanCondition");
    }
}