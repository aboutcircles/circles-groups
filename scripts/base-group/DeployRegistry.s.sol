// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {AffiliateGroupRegistry} from "src/affiliate-group/AffiliateGroupRegistry.sol";

contract DeployRegistry is Script {
    address deployer = address(0xfDA1086AeFcC86234b45461326524991397a8FD1);
    address hub = address(0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8);
    AffiliateGroupRegistry public affiliateGroupRegistry; // 0xca8222e780d046707083f51377B5Fd85E2866014

    function setUp() public {}

    function run() public {
        vm.startBroadcast(deployer);

        affiliateGroupRegistry = new AffiliateGroupRegistry(hub);

        vm.stopBroadcast();
        console.log(address(affiliateGroupRegistry), "AffiliateGroupRegistry");
    }
}