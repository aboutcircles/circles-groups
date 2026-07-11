// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {ScoreGroup} from "src/score-group/ScoreGroup.sol";

contract DeployGroup is Script {
    address deployer = address(0x09F00445e068eb812c541F6538a2f60eAaf51a69);
 
    address metadataManager = address(0x536b4EF99252a8019dCA1e068A37c28BEa2F2BB2);
    address mintRouterAdmin = address(0x3C87d21Bb9d60eB99b490095BA2e18969aCA488e);
    address merkleTreeManager = address(0xd739ADdD4FBEe12A9157683247f28B864D8275B6);

    ScoreGroup public group; // 0x93eD5A96347927ff6fF6b790F8Cf5258240c321f  // router 0xE171a76De6B645A28b3767f84B177a4f6659a3D7 // treasury 0xE445f8b377f7689D2987920D51B8bBa21B6241Ce // low 0xd9fa2f4A35899f7d1e5ADb79592fbf51DC0806a4 // high 0x516ADcF32be9576AefE2176C059d8abaB4f3C2D4

    function setUp() public {}

    function run() public {
        vm.startBroadcast(deployer);

        group = new ScoreGroup(metadataManager, mintRouterAdmin, merkleTreeManager, "Gnosis", "gCRC", bytes32(0x1b4e6979861b7e2832c37abd9703d287b807d8479f0f7d0c2a88330c427f9638));

        vm.stopBroadcast();
    }
}