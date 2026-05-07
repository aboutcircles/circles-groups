// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {ScoreGroupMintRouter} from "src/rep-group/ScoreGroupMintRouter.sol";

/**
 * @title DeployRouter
 * @notice Deploys `ScoreGroupMintRouter` and registers it in the Hub as an
 *         organization (handled in the constructor).
 *
 * Usage:
 *   forge script scripts/rep-group/DeployRouter.s.sol \
 *       --rpc-url $GNOSIS_RPC \
 *       --private-key <PRIVATE_KEY> \
 *       --broadcast -vv
 */
contract DeployRouter is Script {
    address constant ADMIN = 0x2951100fdfCB0c9677Eea28332CE2306fc67b9eB;
    address constant DEPLOYER = 0xcCC2F6aE2b268Ea5700C74276574ecb45a8Ce47f;

    function run() public {
        vm.startBroadcast(DEPLOYER);
        ScoreGroupMintRouter router = new ScoreGroupMintRouter(ADMIN); // 0x57f419d38fB95400A0a8479B16891d36F09b06E7
        vm.stopBroadcast();

        console.log("ScoreGroupMintRouter:", address(router));
        console.log("admin:               ", ADMIN);
    }
}
