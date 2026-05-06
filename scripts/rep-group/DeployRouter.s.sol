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
    address constant ADMIN = address();
    address constant DEPLOYER = address();

    function run() public {
        vm.startBroadcast(DEPLOYER);
        ScoreGroupMintRouter router = new ScoreGroupMintRouter(ADMIN);
        vm.stopBroadcast();

        console.log("ScoreGroupMintRouter:", address(router));
        console.log("admin:               ", ADMIN);
    }
}
