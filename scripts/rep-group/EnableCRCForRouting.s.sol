// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {ScoreGroupMintRouter} from "src/rep-group/ScoreGroupMintRouter.sol";

/**
 * @title EnableCRCForRouting
 * @notice Calls `ScoreGroupMintRouter.enableCRCForRouting` in batches over the
 *         full gnosis-group member set.
 *
 * Usage:
 *   forge script scripts/rep-group/EnableCRCForRouting.s.sol \
 *       --rpc-url $GNOSIS_RPC \
 *       --private-key <PRIVATE_KEY> \
 *       --broadcast -vv
 *
 *   # Resume from a specific index after a failed tx:
 *   START_INDEX=600 forge script ... --broadcast
 */
contract EnableCRCForRouting is Script {
    address constant ADMIN = address(0x0000000000000000000000000000000000000000); // TODO: set admin
    address constant ROUTER = address(0x0000000000000000000000000000000000000000); // TODO: set deployed router
    string constant CSV_PATH = "./scripts/rep-group/gnosis_group_member.csv";
    uint256 constant BATCH_SIZE = 150;

    function run() public {
        require(ROUTER != address(0), "ROUTER not set");

        address[] memory members = _readMembers();
        uint256 startIndex = vm.envOr("START_INDEX", uint256(0));
        require(startIndex < members.length, "START_INDEX past end");

        ScoreGroupMintRouter router = ScoreGroupMintRouter(ROUTER);

        uint256 total = members.length;
        uint256 batches = (total - startIndex + BATCH_SIZE - 1) / BATCH_SIZE;
        console.log(string.concat("members: ", vm.toString(total)));
        console.log(string.concat("start:   ", vm.toString(startIndex)));
        console.log(string.concat("batches: ", vm.toString(batches)));

        vm.startBroadcast(ADMIN);
        for (uint256 i = startIndex; i < total; i += BATCH_SIZE) {
            uint256 end = i + BATCH_SIZE;
            if (end > total) end = total;
            address[] memory batch = _slice(members, i, end);
            router.enableCRCForRouting(batch);
            console.log(string.concat(
                "sent batch [", vm.toString(i), "..", vm.toString(end), ") size=", vm.toString(end - i)
            ));
        }
        vm.stopBroadcast();

        console.log("done");
    }

    function _readMembers() internal view returns (address[] memory members) {
        string memory data = vm.readFile(CSV_PATH);
        string[] memory lines = vm.split(data, "\n");

        uint256 count = 0;
        for (uint256 i = 1; i < lines.length; i++) {
            if (bytes(lines[i]).length >= 42) count++;
        }

        members = new address[](count);
        uint256 idx = 0;
        for (uint256 i = 1; i < lines.length; i++) {
            bytes memory raw = bytes(lines[i]);
            if (raw.length < 42) continue;
            members[idx++] = vm.parseAddress(string(raw));
        }
    }

    function _slice(address[] memory src, uint256 start, uint256 end)
        internal
        pure
        returns (address[] memory out)
    {
        out = new address[](end - start);
        for (uint256 i = 0; i < end - start; i++) out[i] = src[start + i];
    }
}
