// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

interface IMultiAffiliateGroupRegistry {
    function initialize(address[] memory avatars, address[] memory affiliateGroup) external;
    function lockInitialization() external;
    function isInitialized() external view returns (bool);
    function deployer() external view returns (address);
}

/**
 * @title Initialize
 * @notice Seeds a deployed {MultiAffiliateGroupRegistry} with the avatar/affiliate-group pairs
 *         in `data-affiliate_group.csv`, by calling `initialize(address[],address[])` in batches,
 *         then permanently locks seeding via `lockInitialization()`.
 *
 * @dev The full set (~13,510 pairs) cannot fit in a single call: it exceeds both the EIP-3860
 *      init-code limit and the Gnosis block gas limit, so it must be sent in batches.
 *      The configured account must be the registry's `deployer` (the address that deployed it).
 *
 * Usage:
 *   REGISTRY=0x... PRIVATE_KEY=0x... forge script scripts/affiliate-group/Initialize.s.sol \
 *       --rpc-url $GNOSIS_RPC \
 *       --broadcast -vv
 *
 *   # Seed a custom [START_INDEX, END_INDEX) slice of pairs (END_INDEX is exclusive, defaults to the
 *   # total pair count). The final lock only runs when the slice reaches the very last pair:
 *   START_INDEX=4000 END_INDEX=8000 REGISTRY=0x... PRIVATE_KEY=0x... forge script ... --broadcast
 *
 *   # Seed only, skip the final lock (e.g. when resuming a partial run):
 *   LOCK=false REGISTRY=0x... PRIVATE_KEY=0x... forge script ... --broadcast
 */
contract Initialize is Script {
    string constant CSV_PATH = "./scripts/affiliate-group/data-affiliate_group.csv";
    uint256 constant BATCH_SIZE = 200;

    function run() public {
        IMultiAffiliateGroupRegistry registry =
            IMultiAffiliateGroupRegistry(vm.envAddress("REGISTRY"));
        uint256 pk = vm.envUint("PRIVATE_KEY");
        uint256 startIndex = vm.envOr("START_INDEX", uint256(0));
        bool doLock = vm.envOr("LOCK", true);

        require(!registry.isInitialized(), "registry already locked");
        require(vm.addr(pk) == registry.deployer(), "signer is not registry deployer");

        // Read+split the CSV once, then count rows cheaply (no per-row address parsing).
        string[] memory lines = _readLines();
        uint256 total = _countPairs(lines);
        // END_INDEX is exclusive and defaults to the full pair count.
        uint256 endIndex = vm.envOr("END_INDEX", total);
        require(startIndex < total, "START_INDEX past end");
        require(endIndex <= total, "END_INDEX past end");
        require(startIndex < endIndex, "START_INDEX >= END_INDEX");

        // Parse only the requested window; rows outside [startIndex, endIndex) are never decoded.
        (address[] memory avatars, address[] memory groups) = _parseWindow(lines, startIndex, endIndex);
        uint256 windowLen = avatars.length; // == endIndex - startIndex

        uint256 batches = (windowLen + BATCH_SIZE - 1) / BATCH_SIZE;
        console.log(string.concat("registry: ", vm.toString(address(registry))));
        console.log(string.concat("pairs:    ", vm.toString(total)));
        console.log(string.concat("start:    ", vm.toString(startIndex)));
        console.log(string.concat("end:      ", vm.toString(endIndex)));
        console.log(string.concat("batches:  ", vm.toString(batches)));

        vm.startBroadcast(pk);
        _seed(registry, avatars, groups, startIndex);

        // Only lock once the very last pair has been seeded.
        if (doLock && endIndex == total) {
            registry.lockInitialization();
            console.log("locked initialization");
        } else {
            console.log(doLock ? "skipped lock (END_INDEX < total)" : "skipped lock (LOCK=false)");
        }
        vm.stopBroadcast();

        console.log("done");
    }

    /// @dev Sends the windowed pairs to `initialize` in {BATCH_SIZE} chunks. `startIndex` is only used
    ///      to label log lines with absolute pair indices; `avatars`/`groups` are already the slice.
    function _seed(
        IMultiAffiliateGroupRegistry registry,
        address[] memory avatars,
        address[] memory groups,
        uint256 startIndex
    ) internal {
        uint256 windowLen = avatars.length;
        for (uint256 off = 0; off < windowLen; off += BATCH_SIZE) {
            uint256 end = off + BATCH_SIZE;
            if (end > windowLen) end = windowLen;
            (address[] memory aBatch, address[] memory gBatch) = _slice(avatars, groups, off, end);
            registry.initialize(aBatch, gBatch);
            console.log(string.concat(
                "seeded batch [", vm.toString(startIndex + off), "..", vm.toString(startIndex + end),
                ") size=", vm.toString(end - off)
            ));
        }
    }

    /// @dev Reads the CSV and splits it into lines once. The expensive per-row address parsing is
    ///      deferred to {_parseWindow}, so callers that only need a slice don't decode the whole file.
    function _readLines() internal view returns (string[] memory lines) {
        lines = vm.split(vm.readFile(CSV_PATH), "\n");
    }

    /// @dev Counts the data rows (a valid data line is `"0x..40..","0x..40.."` (~89 chars); header/blank
    ///      lines are shorter). Cheap: only inspects line lengths, never decodes addresses.
    function _countPairs(string[] memory lines) internal pure returns (uint256 count) {
        for (uint256 i = 1; i < lines.length; i++) {
            if (bytes(lines[i]).length >= 80) count++;
        }
    }

    /// @dev Decodes only the data rows in `[startIndex, endIndex)` into addresses, stopping as soon as
    ///      the window is filled. Rows before `startIndex` are skipped (length check only, no parsing).
    function _parseWindow(string[] memory lines, uint256 startIndex, uint256 endIndex)
        internal
        pure
        returns (address[] memory avatars, address[] memory groups)
    {
        uint256 windowLen = endIndex - startIndex;
        avatars = new address[](windowLen);
        groups = new address[](windowLen);

        uint256 dataIdx = 0; // index among valid data rows
        uint256 out = 0;
        for (uint256 i = 1; i < lines.length && out < windowLen; i++) {
            if (bytes(lines[i]).length < 80) continue;
            if (dataIdx >= startIndex) {
                string[] memory cols = vm.split(lines[i], ",");
                require(cols.length == 2, "unexpected column count");
                avatars[out] = vm.parseAddress(_unquote(cols[0]));
                groups[out] = vm.parseAddress(_unquote(cols[1]));
                out++;
            }
            dataIdx++;
        }
    }

    /// @dev Strips surrounding double-quotes and trailing CR/whitespace from a CSV field.
    function _unquote(string memory s) internal pure returns (string memory) {
        bytes memory b = bytes(s);
        uint256 start = 0;
        uint256 end = b.length;
        while (end > start && (b[end - 1] == '"' || b[end - 1] == "\r" || b[end - 1] == " ")) end--;
        while (start < end && (b[start] == '"' || b[start] == " ")) start++;
        bytes memory out = new bytes(end - start);
        for (uint256 i = 0; i < end - start; i++) out[i] = b[start + i];
        return string(out);
    }

    function _slice(address[] memory a, address[] memory g, uint256 start, uint256 end)
        internal
        pure
        returns (address[] memory aOut, address[] memory gOut)
    {
        aOut = new address[](end - start);
        gOut = new address[](end - start);
        for (uint256 i = 0; i < end - start; i++) {
            aOut[i] = a[start + i];
            gOut[i] = g[start + i];
        }
    }
}
