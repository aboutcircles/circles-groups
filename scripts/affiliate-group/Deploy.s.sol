// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {MultiAffiliateGroupRegistry} from "src/affiliate-group/MultiAffiliateGroupRegistry.sol";

/**
 * @title Deploy
 * @notice Deploys {MultiAffiliateGroupRegistry}.
 *
 * @dev The broadcasting account becomes the registry's `deployer` — the only account permitted
 *      to seed it via {Initialize}. Use the same `PRIVATE_KEY` for the subsequent Initialize run.
 *
 * Usage:
 *   PRIVATE_KEY=0x... forge script scripts/affiliate-group/Deploy.s.sol \
 *       --rpc-url $GNOSIS_RPC \
 *       --broadcast -vv
 */
contract Deploy is Script {
    MultiAffiliateGroupRegistry public registry;

    function run() public {
        uint256 pk = vm.envUint("PRIVATE_KEY"); // 0xcCC2F6aE2b268Ea5700C74276574ecb45a8Ce47f

        vm.startBroadcast(pk);
        registry = new MultiAffiliateGroupRegistry(); // 0x4a25a7cf216351963f1637ad965d77b3ae277ef3
        vm.stopBroadcast();

        console.log(string.concat("MultiAffiliateGroupRegistry: ", vm.toString(address(registry))));
        console.log(string.concat("deployer:                    ", vm.toString(registry.deployer())));
    }
}