# ScoreGroupMintRouter Migration Runbook

End-to-end steps for migrating gnosis-group members onto a freshly deployed `ScoreGroupMintRouter`. All scripts live in `scripts/rep-group/`.

## Prerequisites

- `foundry` installed (`forge` ≥ 1.0)
- `node` ≥ 18 (for the member-fetcher)
- An RPC endpoint for Gnosis Chain (e.g. `https://rpc.gnosischain.com`)
- A funded admin/deployer key. Export once per shell:
  ```bash
  export GNOSIS_RPC=https://rpc.gnosischain.com
  export PRIVATE_KEY=0x...        # deployer key (also the ADMIN unless changed)
  ```

---

## 1. Fetch gnosis-group members → `gnosis_group_member.csv`

`fetchGroupMembers.mjs` calls `circles_getGroupMembers` with pagination, dedupes, and writes one address per line (CSV header `member`).

```bash
# from repo root
node scripts/rep-group/fetchGroupMembers.mjs
```

Optional positional args:

```bash
# node scripts/rep-group/fetchGroupMembers.mjs <groupAddress> <rpcUrl>
node scripts/rep-group/fetchGroupMembers.mjs \
  0xC19BC204eb1c1D5B3FE500E5E5dfaBaB625F286c \
  https://rpc.aboutcircles.com/
```

Output: `scripts/rep-group/gnosis_group_member.csv`. Verify line count matches the RPC totals before continuing.

---

## 2. Estimate gas → `EstimateEnableCRCGas.s.sol`

Pick the largest batch size that fits comfortably under Gnosis Chain's block gas limit (~17M). The script deploys a fresh router in-memory and measures `enableCRCForRouting(batch)`.

Edit `BATCH_SIZE` in the script, then run (no broadcast needed):

```bash
forge script scripts/rep-group/EstimateEnableCRCGas.s.sol \
  --rpc-url $GNOSIS_RPC \
  -vv
```

Reference numbers already recorded in the script:

| BATCH_SIZE | gas used   |
| ---------- | ---------- |
| 250        | 14,717,242 |
| 200        | 11,776,319 |
| 150        |  8,838,188 |
| 100        |  5,895,869 |

Recommendation: `BATCH_SIZE = 150` (default in `EnableCRCForRouting.s.sol`).

---

## 3. Deploy the router → `DeployRouter.s.sol`

Set the admin and deployer addresses in `DeployRouter.s.sol`:

```solidity
address constant ADMIN    = 0x...;   // privileged rollback/admin address
address constant DEPLOYER = 0x...;   // matches the broadcast key
```

Then deploy:

```bash
forge script scripts/rep-group/DeployRouter.s.sol \
  --rpc-url $GNOSIS_RPC \
  --private-key $PRIVATE_KEY \
  --broadcast -vv
```

Record the printed `ScoreGroupMintRouter:` address — it is needed in step 4.

---

## 4. Enable CRC for routing in batches → `EnableCRCForRouting.s.sol`

Set the deployed router and admin addresses in `EnableCRCForRouting.s.sol`:

```solidity
address constant ADMIN  = 0x...;     // must match the router's admin
address constant ROUTER = 0x...;     // address from step 3
uint256 constant BATCH_SIZE = 150;   // adjust if step 2 said otherwise
```

`CSV_PATH` defaults to `./scripts/rep-group/gnosis_group_member.csv` (the file from step 1).

Run the full migration:

```bash
forge script scripts/rep-group/EnableCRCForRouting.s.sol \
  --rpc-url $GNOSIS_RPC \
  --private-key $PRIVATE_KEY \
  --broadcast -vv
```

The script logs `members:`, `batches:`, and a `sent batch [i..j)` line per tx.

### Resuming after a failure

If a batch reverts mid-run, set `START_INDEX` to the first member that did **not** land on-chain and re-run:

```bash
START_INDEX=600 forge script scripts/rep-group/EnableCRCForRouting.s.sol \
  --rpc-url $GNOSIS_RPC \
  --private-key $PRIVATE_KEY \
  --broadcast -vv
```

`START_INDEX` is read via `vm.envOr` and defaults to `0`.

---

## File reference

| File                          | Purpose                                                              | How to run                                                                                |
| ----------------------------- | -------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| `fetchGroupMembers.mjs`       | Pull all gnosis-group members into `gnosis_group_member.csv`         | `node scripts/rep-group/fetchGroupMembers.mjs`                                            |
| `gnosis_group_member.csv`     | One member address per line; header `member`                         | (output of fetch step)                                                                    |
| `EstimateEnableCRCGas.s.sol`  | Measure gas for one `enableCRCForRouting` batch                      | `forge script ... --rpc-url $GNOSIS_RPC -vv` (no `--broadcast`)                           |
| `DeployRouter.s.sol`          | Deploy `ScoreGroupMintRouter` (registers as Hub organization)        | `forge script ... --rpc-url $GNOSIS_RPC --private-key $PRIVATE_KEY --broadcast -vv`       |
| `EnableCRCForRouting.s.sol`   | Loop CSV → `router.enableCRCForRouting(batch)` in `BATCH_SIZE` slices | `forge script ... --rpc-url $GNOSIS_RPC --private-key $PRIVATE_KEY --broadcast -vv`       |

---

## `circles_getGroupMembers` reference

Underlying RPC the fetcher wraps:

```bash
curl -s https://rpc.aboutcircles.com/ \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc":"2.0","id":1,
    "method":"circles_getGroupMembers",
    "params":["0xC19BC204eb1c1D5B3FE500E5E5dfaBaB625F286c", 1000]
  }'
```

Response shape (truncated):

```json
{
  "jsonrpc": "2.0",
  "result": {
    "results": [
      { "group": "0xc19b...", "member": "0x50e9...", "expiryTime": 9223372036854776000 }
    ],
    "hasMore": true,
    "nextCursor": "NDU3Njk5MTg6MTc6MQ=="
  },
  "id": 1
}
```

The fetcher pages with `[group, PAGE_SIZE, nextCursor]` until `hasMore === false`.
