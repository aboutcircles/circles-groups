# Rep based mint policy

## Overview

A new group where personal CRC is converted into group CRC at one of two ratios:

- **Score path** (gated by `MintHandler`): `X · Z` group CRC, where `X ∈ [0, 1]` is the avatar's score and `Z` is the personal CRC just issued by `Hub.personalMint`. The remaining `(1 − X) · Z` stays in the user's wallet as personal CRC.
- **Historical 1:1 path**: any holder of a trusted personal CRC can mint group CRC 1:1 against an inflationary budget snapshotted at deployment for each founding trustee.

The Hub is treated as immutable. All gating logic lives in `MintPolicy`, with `MintHandler` providing atomicity for the score path.

## Glossary

| Term                     | Meaning                                                                                                                                        |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `historical[collateral]` | per-avatar 1:1 mint budget, denominated in inflationary units anchored at `inflationDayZero`. Set at deployment, monotonically non-increasing. |
| Inflationary value       | a value in `Hub`'s anchor frame; converts to today's demurrage value via `convertInflationaryToDemurrageValue(v, today)`.                      |
| `MintHandler`            | sole authorized minter for the score path. `_minter == MINT_HANDLER` short-circuits to score / explicit-historical mode.                       |
| Score `X`                | scalar in `[0, SCALE]` issued by an off-chain authority and committed via merkle root in `Score`.                                              |
| Founding trustee         | an avatar whose `Hub.totalSupplies` was snapshotted in `MintPolicy.initBatch` before sealing.                                                  |

## Contracts

### IMintPolicy (extends existing `IMintPolicy` from `src/groups/IMintPolicy.sol`)

```solidity
interface INewGroupMintPolicy {
    enum Mode { SCORE, HISTORICAL_VIA_HANDLER }

    struct InflationaryBudget {
        uint192 remaining;     // inflationary units
        bool    initialized;   // true once initBatch has touched this avatar
    }

    // ---------- one-shot configuration ----------

    /// @notice Sets MintHandler. Reverts after the first successful call.
    /// Logic: require(MINT_HANDLER == address(0)); MINT_HANDLER = h; emit ...
    function setMintHandler(address h) external;

    /// @notice Snapshots a batch of avatars into historical[]. Reverts after sealInit().
    /// Logic per entry c:
    ///   require(!sealed && !historical[c].initialized);
    ///   uint256 supply = HUB.totalSupplies(toTokenId(c));
    ///   historical[c].remaining = uint192(convertDemurrageToInflationaryValue(supply, today()));
    ///   historical[c].initialized = true;
    function initBatch(address[] calldata avatars) external;

    /// @notice Locks initBatch. One-shot.
    /// Logic: require(!sealed && MINT_HANDLER != address(0)); sealed = true.
    function sealInit() external;

    // ---------- Hub callback ----------

    /// @notice Called by Hub on every group mint into this group.
    /// Logic:
    ///   if (_minter == MINT_HANDLER) {
    ///     Mode m = abi.decode(_data, (Mode));
    ///     if (m == SCORE) {
    ///         // MintHandler has already verified score and bounded amount.
    ///         // Policy MAY re-verify or trust-and-route. Recommended: trust.
    ///         // Do NOT touch historical[].
    ///     } else if (m == HISTORICAL_VIA_HANDLER) {
    ///         _consumeHistorical(_collateral, _amounts);
    ///     } else revert();
    ///   } else {
    ///     // Path mint via operateFlowMatrix (Router as _minter) OR direct Hub.groupMint.
    ///     // _data is ignored here.
    ///     _consumeHistorical(_collateral, _amounts);
    ///   }
    ///   return true;
    function beforeMintPolicy(
        address _minter,
        address _group,
        uint256[] calldata _collateral,
        uint256[] calldata _amounts,
        bytes calldata _data
    ) external returns (bool);

    /// @notice Standard burn / redeem hooks; defer to BaseMintPolicy semantics.
    function beforeBurnPolicy(address, address, uint256, bytes calldata) external returns (bool);
    function beforeRedeemPolicy(address, address, address, uint256, bytes calldata)
        external
        returns (uint256[] memory ids, uint256[] memory values, uint256[] memory burnIds, uint256[] memory burnValues);

    // ---------- views ----------

    function MINT_HANDLER() external view returns (address);
    function SCORE() external view returns (address);
    function HUB() external view returns (address);
    function GROUP() external view returns (address);
    function historical(address c) external view returns (uint192 remaining, bool initialized);
}
```

**Internal helper logic notes:**

- `_consumeHistorical(_collateral, _amounts)`:
  - For each `i`:
    - Resolve `c = address(uint160(_collateral[i]))`.
    - `require(historical[c].initialized)`. (Implicitly false for non-founders → revert.)
    - `amountInfl = convertDemurrageToInflationaryValue(_amounts[i], today())`.
    - `require(amountInfl <= historical[c].remaining)`.
    - `historical[c].remaining -= uint192(amountInfl)`.
- The bucket key is the **collateral avatar** (issuer of the personal CRC), not the minter. Bob holding Alice's CRC drains Alice's bucket — the right semantic for path transfers.
- `MintPolicy` inherits demurrage helpers from `Demurrage.sol` (or copies the math) so it can convert at `today()`.

### IMintHandler

```solidity
interface IMintHandler {
    /// @notice Step 1 of the score-path 3-call wallet bundle. Snapshots the user's
    ///         currently claimable issuance into transient storage.
    /// Logic:
    ///   (uint256 z,,) = HUB.calculateIssuance(msg.sender);
    ///   require(z > 0, "no issuance");
    ///   bytes32 slot = keccak256(abi.encode("scorePathSnapshot", msg.sender));
    ///   assembly { tstore(slot, z) }
    function snapshotIssuance() external;

    /// @notice Step 3. Verifies the score proof, enforces the X·Z cap,
    ///         pulls collateral from the user, and triggers Hub.groupMint.
    /// Logic:
    ///   bytes32 slot = keccak256(abi.encode("scorePathSnapshot", msg.sender));
    ///   uint256 z; assembly { z := tload(slot) }
    ///   require(z > 0, "no snapshot");
    ///   SCORE.verify(proof, msg.sender, score);   // score is in [0, SCALE]
    ///   require(amount <= (score * z) / SCALE, "exceeds score budget");
    ///   HUB.safeTransferFrom(msg.sender, address(this), toTokenId(msg.sender), amount, "");
    ///   HUB.groupMint(GROUP, [msg.sender], [amount], abi.encode(Mode.SCORE));
    ///   // forward minted group CRC back to user
    ///   HUB.safeTransferFrom(address(this), msg.sender, toTokenId(GROUP), amount, "");
    ///   assembly { tstore(slot, 0) }
    function finalizeScoreMint(bytes calldata proof, uint256 score, uint256 amount) external;

    /// @notice Optional convenience entry for HISTORICAL_VIA_HANDLER.
    ///         Pulls collateral and triggers Hub.groupMint with Mode.HISTORICAL_VIA_HANDLER.
    ///         Equivalent to user calling Hub.groupMint directly; provided for UX uniformity.
    function historicalMint(address collateralAvatar, uint256 amount) external;

    function POLICY() external view returns (address);
    function SCORE() external view returns (address);
    function HUB() external view returns (address);
    function GROUP() external view returns (address);
}
```

**Implementation notes:**

- Must implement `ERC1155TokenReceiver` so `Hub.groupMint`'s mint-to-MintHandler step succeeds, and so `safeTransferFrom` to/from MintHandler works.
- TSTORE slot keyed by `keccak256("scorePathSnapshot", user)` to avoid collision with future per-user transient state.
- `snapshotIssuance` and `finalizeScoreMint` rely on EIP-1153 transient storage; the wallet bundle MUST execute both within the same transaction. Across-tx state is impossible by construction.
- No `onlyOwner` admin paths. Any non-finalize behavior should be considered a bug.

### IScore

```solidity
interface IScore {
    /// @notice Active merkle root. Leaves: keccak256(abi.encode(avatar, score, ...)).
    function root() external view returns (bytes32);

    /// @notice Optional: keep N previous roots valid for a TTL window.
    ///         See "Open consideration: root rotation" below.
    function rootAt(uint256 version) external view returns (bytes32);
    function currentVersion() external view returns (uint256);

    /// @notice Verify a score proof. Reverts on failure.
    /// Logic:
    ///   bytes32 leaf = keccak256(abi.encode(avatar, score));
    ///   require(MerkleProof.verify(proof, root(), leaf), "bad proof");
    function verify(bytes calldata proof, address avatar, uint256 score) external view;

    /// @notice Update root. Authority-gated (multisig / DAO).
    function setRoot(bytes32 newRoot) external;
}
```

**Implementation notes:**

- Root lives in regular storage. SLOAD is fine; no transient-storage caching needed.
- Authority for `setRoot` is out-of-scope here but should be a multisig or DAO. Document the rotation cadence.
- See "Open consideration: root rotation" for the proof-vs-root race.

## Setup / Deployment Order

| Step | Action                                                                   | Notes                                                                                                                                                        |
| ---- | ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1    | Deploy `Score` with initial root and authority.                          | Authority can later `setRoot`.                                                                                                                               |
| 2    | Deploy `MintPolicy(SCORE, HUB, GROUP_PLACEHOLDER)`.                      | `MINT_HANDLER` and `GROUP` may be unset; use setter or pass placeholder. If `GROUP` is needed at construction, deploy at a CREATE2 address known in advance. |
| 3    | Deploy `MintHandler(POLICY, SCORE, HUB, GROUP)`.                         | Must implement ERC1155 receiver.                                                                                                                             |
| 4    | `MintPolicy.setMintHandler(MintHandler)`.                                | One-shot; the slot is now sealed.                                                                                                                            |
| 5    | `Hub.registerGroup(MintPolicy, name, symbol, metadata)`.                 | Group avatar is now live.                                                                                                                                    |
| 6    | `MintPolicy.initBatch([avatars...])` × N.                                | ~500 entries per tx; deployer-gated. Reads `Hub.totalSupplies` for each, converts to inflationary at `today()`.                                              |
| 7    | `MintPolicy.sealInit()`.                                                 | One-shot; `historical[]` is now immutable in shape (only `remaining` decreases via mints).                                                                   |
| 8    | (Production) `BaseGroupMintRouter.enableCRCForRouting(GROUP, crcArray)`. | Sets up trust + operator approval so `operateFlowMatrix` paths can route through `Router → GROUP`.                                                           |

**Order rationale:** `setMintHandler` and `sealInit` should both complete before step 5 (registerGroup) ideally, but if the registration must happen earlier, the policy still reverts any mint against uninitialized buckets — `historical[c].initialized == false` → all path mints fail until init completes.

## Workflow: Three Mint Flows

### 1.1 Score Path — wallet-batched 3-call tx

**Prereq (one-time, separate tx):** `Hub.setApprovalForAll(MintHandler, true)` by the user.

**The batch:**

```
tx1: MintHandler.snapshotIssuance()          // msg.sender = user
        └─ TSTORE(slot(user), HUB.calculateIssuance(user).issuance)

tx2: Hub.personalMint()                      // msg.sender = user
        └─ mints Z personal CRC to user

tx3: MintHandler.finalizeScoreMint(proof, score, amount)
        ├─ Z = TLOAD(slot(user))                       // require Z > 0
        ├─ Score.verify(proof, user, score)            // reverts on bad proof
        ├─ require amount ≤ score * Z / SCALE
        ├─ Hub.safeTransferFrom(user, MintHandler, toTokenId(user), amount, "")
        ├─ Hub.groupMint(GROUP, [user], [amount], abi.encode(Mode.SCORE))
        │    └─ Hub._groupMint:
        │         ├─ MintPolicy.beforeMintPolicy(_minter=MintHandler, ..., data=Mode.SCORE)
        │         │     └─ accept; do NOT touch historical[]
        │         ├─ collateral → treasury
        │         └─ mint amount of GROUP CRC to MintHandler (acceptance call OK; MintHandler is ERC1155Receiver)
        ├─ Hub.safeTransferFrom(MintHandler, user, toTokenId(GROUP), amount, "")
        └─ TSTORE(slot(user), 0)
```

**Outcome:** user has `(1 − X) · Z` personal CRC and `X · Z` group CRC. The score budget is enforced atomically by the snapshot → personalMint → finalize triplet inside one transaction.

### 1.2 Path Mint via `Hub.operateFlowMatrix`

**Prereq:** Router has been configured (`BaseGroupMintRouter.enableCRCForRouting`) for the relevant CRCs and the BaseGroup.

```
user → Hub.operateFlowMatrix(...)            // any caller; flow may originate from anyone
   └─ for the edge crossing GROUP (Router → GROUP):
        Hub._groupMint(_sender = Router, ..., _collateral = [A_id], _amounts = [v], data="", _explicitCall=false)
          ├─ MintPolicy.beforeMintPolicy(_minter=Router, ..., data="")
          │     └─ else branch → _consumeHistorical([A_id], [v])
          │           - require historical[A].initialized
          │           - vInfl = convertDemurrageToInflationaryValue(v, today())
          │           - require vInfl <= historical[A].remaining
          │           - historical[A].remaining -= vInfl
          ├─ collateral → treasury
          └─ mint v of GROUP CRC along the path
```

### 1.3 Direct `Hub.groupMint`

```
user → Hub.groupMint(GROUP, [collateralAvatar], [amount], "")
   └─ Hub._groupMint(_sender = user, ..., data="")
        ├─ MintPolicy.beforeMintPolicy(_minter=user, ..., data="")
        │     └─ else branch → _consumeHistorical([collateralAvatar_id], [amount])
        ├─ collateral → treasury
        └─ mint amount of GROUP CRC to user
```

User must hold the collateral and the collateral avatar must have an initialized historical bucket.

## Invariants

1. `MINT_HANDLER` is set exactly once via `setMintHandler`. Subsequent calls revert.
2. `sealed` transitions false → true exactly once via `sealInit`. After that, `initBatch` reverts.
3. `historical[c].remaining` is monotonically non-increasing across the contract's lifetime.
4. For all `c`, day `d`: `convertInflationaryToDemurrageValue(historical[c].remaining, d) ≤ Hub.totalSupplies(toTokenId(c)) at day d` in spirit — the bucket can never authorize more group CRC than exists in personal CRC backing it. (Worth a fuzz test against `Hub` totalSupplies.)
5. The score-path 3-call batch executes in a single transaction. No `finalizeScoreMint` should ever succeed if `snapshotIssuance` was not called in the same tx (TSTORE clears at tx boundary).
6. `_consumeHistorical` is the **only** writer of `historical[c].remaining` after `sealInit`.

## Open Considerations

### Root rotation race

**Problem:** at block A, `Score.setRoot(newRoot)` lands. A user submits a tx with a proof generated against the previous root. The user's tx mines at block A or later → `Score.verify` reverts.

**Options, in order of preference:**

1. **Bundle root update + mint in the user's tx.** Authority signs `(newRoot, deadline)` off-chain; the user includes a `Score.applyRootUpdate(newRoot, sig)` call as the first call in the wallet bundle.

### Group-CRC-as-collateral

If the new group ever trusts another group's CRC as collateral, `_consumeHistorical` keys the bucket by the group avatar — but groups never had a personal CRC supply to snapshot. The simplest rule: only personal CRC is acceptable collateral for the historical path; reject group-CRC collateral in `beforeMintPolicy` (`require(Hub.isHuman(collateralAvatar))`).
