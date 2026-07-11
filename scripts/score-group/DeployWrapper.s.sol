// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {SinkGroupWrapperInflationary} from "src/score-group/SinkGroupWrapperInflationary.sol";

contract DeployWrapper is Script {
    address deployer = address(0x09F00445e068eb812c541F6538a2f60eAaf51a69);
    SinkGroupWrapperInflationary public wrapper; // 0xD4cF9afd3aE777C24454b70dd28E32d1bd516F05

    function setUp() public {}

    function run() public {
        vm.startBroadcast(deployer);

        wrapper = new SinkGroupWrapperInflationary();

        vm.stopBroadcast();
    }
}