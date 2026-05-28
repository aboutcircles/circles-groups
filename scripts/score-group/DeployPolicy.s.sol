// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {OffchainScoreBasedMintPolicy} from "src/score-group/OffchainScoreBasedMintPolicy.sol";

contract DeployPolicy is Script {
    address deployer = address(0x09F00445e068eb812c541F6538a2f60eAaf51a69);
    OffchainScoreBasedMintPolicy public policy; // 0x450D68272e43c4Cab7cbC7faA37893A50FAE9569

    function setUp() public {}

    function run() public {
        vm.startBroadcast(deployer);

        policy = new OffchainScoreBasedMintPolicy();

        vm.stopBroadcast();
    }
}