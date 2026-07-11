// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {MerkleTreeRegistry} from "src/score-group/MerkleTreeRegistry.sol";

contract DeployTreeRegistry is Script {
    address deployer = address(0x09F00445e068eb812c541F6538a2f60eAaf51a69);
    MerkleTreeRegistry public registry; // 0xB4bfedaD42a14c30Bd9C1FdBf3e11916Fc719E6C

    function setUp() public {}

    function run() public {
        vm.startBroadcast(deployer);

        registry = new MerkleTreeRegistry();

        vm.stopBroadcast();
    }
}