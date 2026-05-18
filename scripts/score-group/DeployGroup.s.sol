// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {ScoreGroup} from "src/score-group/ScoreGroup.sol";

contract DeployGroup is Script {
    address deployer = address(0x09F00445e068eb812c541F6538a2f60eAaf51a69);
 
    address metadataManager = address(0x536b4EF99252a8019dCA1e068A37c28BEa2F2BB2);
    address mintRouterAdmin = address(0xcC05dab6e530b5E846DDfdEd09874BF4ADDEE8eC);
    address merkleTreeManager = address(0xd739ADdD4FBEe12A9157683247f28B864D8275B6);

    ScoreGroup public group; // 0x7CadB2E92295F3E4fA65D3d4E7265E2e05d7a783  // router 0xA60Cd6ddbB4eBa93246D6f80ff4504476c8117D1 // treasury 0xbeE55b27EbC0855CffcB2DBE829f8e921Eb793b3 // low 0xe7Dc5Fae0b2d6f3392d45fCA03F58DC224c63e6F // high 0x4b767D106F4e552Ffdb7Ce6547eB0398E208fc96

    function setUp() public {}

    function run() public {
        vm.startBroadcast(deployer);

        group = new ScoreGroup(metadataManager, mintRouterAdmin, merkleTreeManager, "Gnosis", "gCRC", bytes32(0x1b4e6979861b7e2832c37abd9703d287b807d8479f0f7d0c2a88330c427f9638));

        vm.stopBroadcast();
    }
}