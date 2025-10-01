// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {BaseGroupMintRouter} from "src/base-group/BaseGroupMintRouter.sol";

contract DeployRouter is Script {
    address deployer = address(0x915aec9009a847a8EB1f65bA87dC02742E37B9D1);
    address admin = address(0x7ADd2C8D1f7CE98cA9a6A7c0122916787988071F);
    BaseGroupMintRouter public router; // 0xDC287474114cC0551a81DdC2EB51783fBF34802F

    function setUp() public {}

    function run() public {
        vm.startBroadcast(deployer);

        router = new BaseGroupMintRouter(admin);

        vm.stopBroadcast();
        console.log(address(router), "BaseGroupMintRouter");
    }
}