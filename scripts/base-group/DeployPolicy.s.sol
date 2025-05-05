// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {BaseMintPolicy} from "src/base-group/BaseMintPolicy.sol";

contract DeployPolicy is Script {
    address deployer = address(0x915aec9009a847a8EB1f65bA87dC02742E37B9D1);
    BaseMintPolicy public baseMintPolicy; // 0xCDFc5135AEC0aFbf102C108e7f5C8A88C6112842

    function setUp() public {}

    function run() public {
        vm.startBroadcast(deployer);

        baseMintPolicy = new BaseMintPolicy();

        vm.stopBroadcast();
        console.log(address(baseMintPolicy), "BaseMintPolicy");
    }
}