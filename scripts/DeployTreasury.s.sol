// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {StandardVaultShield, StandardTreasury} from "src/treasury/StandardVaultShieldS.sol";

contract DeployTreasuryOverriden is Script {
    address deployer = address(0x6F939041650e72855018678002c9b8F8AfAD95Da);
    address hub = address(0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8);
    address nameRegistry = address(0xA27566fD89162cC3D40Cb59c87AAaA49B85F3474);
    StandardVaultShield public standardVaultShield; // 
    StandardTreasury public standardTreasury; // 

    function setUp() public {}

    function run() public {
        vm.startBroadcast(deployer);
        standardVaultShield = new StandardVaultShield(nameRegistry);
        standardTreasury = new StandardTreasury(hub, address(standardVaultShield));

        vm.stopBroadcast();
        console.log(address(standardTreasury), "StandardTreasury");
    }
}