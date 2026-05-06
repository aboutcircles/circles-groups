#!/usr/bin/env node
// Fetch all members of a Circles v2 group via circles_getGroupMembers and
// write them into gnosis_group_member.csv (one column: member).
//
// Usage:
//   node scripts/rep-group/fetchGroupMembers.mjs [groupAddress] [rpcUrl]
//
// Defaults:
//   groupAddress = 0xC19BC204eb1c1D5B3FE500E5E5dfaBaB625F286c (gnosis group)
//   rpcUrl       = https://rpc.aboutcircles.com/

import { writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const DEFAULT_GROUP = "0xC19BC204eb1c1D5B3FE500E5E5dfaBaB625F286c";
const DEFAULT_RPC = "https://rpc.aboutcircles.com/";
const PAGE_SIZE = 1000;

const group = process.argv[2] ?? DEFAULT_GROUP;
const rpcUrl = process.argv[3] ?? DEFAULT_RPC;

const __dirname = dirname(fileURLToPath(import.meta.url));
const outFile = resolve(__dirname, "gnosis_group_member.csv");

async function rpc(params) {
    const res = await fetch(rpcUrl, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
            jsonrpc: "2.0",
            id: 1,
            method: "circles_getGroupMembers",
            params,
        }),
    });
    if (!res.ok) throw new Error(`RPC HTTP ${res.status}`);
    const json = await res.json();
    if (json.error) throw new Error(`RPC error: ${JSON.stringify(json.error)}`);
    return json.result;
}

const members = [];
const seen = new Set();
let cursor = null;
let page = 0;

while (true) {
    const params = cursor === null ? [group, PAGE_SIZE] : [group, PAGE_SIZE, cursor];
    const result = await rpc(params);
    page += 1;
    const batch = result?.results ?? [];
    for (const row of batch) {
        const m = (row.member || "").toLowerCase();
        if (m && !seen.has(m)) {
            seen.add(m);
            members.push(m);
        }
    }
    process.stdout.write(
        `page ${page}: +${batch.length} (total ${members.length}) hasMore=${result.hasMore}\n`,
    );
    if (!result.hasMore || !result.nextCursor) break;
    cursor = result.nextCursor;
}

const csv = "member\n" + members.join("\n") + "\n";
writeFileSync(outFile, csv);
console.log(`wrote ${members.length} members -> ${outFile}`);
