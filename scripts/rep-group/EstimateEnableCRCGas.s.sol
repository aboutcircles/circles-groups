// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {ScoreGroupMintRouter} from "src/rep-group/ScoreGroupMintRouter.sol";

/**
 * @title EstimateEnableCRCGas
 * @notice Measures gas for a single `ScoreGroupMintRouter.enableCRCForRouting`
 *         call with a batch of BATCH_SIZE members from the gnosis-group set.
 *
 * Usage:
 *   forge script scripts/rep-group/EstimateEnableCRCGas.s.sol \
 *       --rpc-url https://rpc.gnosischain.com -vv
 */
contract EstimateEnableCRCGas is Script {
    address constant ADMIN = 0x3e8E5E7243B78292742f20228F348b510D7148E5;
    string constant CSV_PATH = "./scripts/rep-group/gnosis_group_member.csv";
    uint256 constant BATCH_SIZE = 250;
    // batch: 250, gas used: 14717242
    // batch: 200, gas used: 11776319
    // batch: 150, gas used: 8838188
    // batch: 100, gas used: 5895869

    function run() public {
        address[] memory members = _readMembers();
        console.log(string.concat("members loaded: ", vm.toString(members.length)));

        uint256 n = BATCH_SIZE > members.length ? members.length : BATCH_SIZE;
        address[] memory batch = _slice(members, 0, n);

        ScoreGroupMintRouter router = new ScoreGroupMintRouter(ADMIN);
        vm.prank(ADMIN);
        uint256 g0 = gasleft();
        router.enableCRCForRouting(batch);
        uint256 gasUsed = g0 - gasleft();

        console.log(string.concat("batch size: ", vm.toString(n)));
        console.log(string.concat("gas used:   ", vm.toString(gasUsed)));
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
