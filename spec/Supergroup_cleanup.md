# Proposal for the Supergroup Trust Management Algorithm

## Objective

To periodically update the trust list of a supergroup by evaluating whether CRC are backed in a Liquidity Bootstrapping Pool (LBP) (aka. "backers") or trusted by people who backed their CRC (aka "friends"). Because this algorithm recalculates the whole trust list, ensure that trust connections are stable over iterations. Additionally with an `append-only` flag defaulted to true, once a person is trusted, they remain trusted unless they get blacklisted.

## Prelimenaries

#### Execution Frequency
- The algorithm runs every 30 minutes to rebuild a full picture of trusted list; ideally randomise a small time-offset to make less predicatable.

#### Iterative Counter
- **`current_iteration`** is incremented by 1 at the start of each execution. Just so we can cache in database easily the "last iteration" some account was trusted by the group, and build insight.

#### Working (pseudocode) lists

- **List A**: The list of all plausible candidates to be trusted in this round (i.e., all humans minus blacklisted ones).
- **List B**: A copy of the list of previously trusted humans from the last iteration. (On start of service, first query Nethermind for current list of trusted accounts by group.)
- **List C**: The newly built proposal for the trusted list in the current round.
- **List D**: The list of currently backing humans, for determining new friends.

## Algorithm Steps

### Step 0, once on startup:
- Query **Nethermind RPC** to retrieve the complete list of trusted accounts by supergroup.
  - Store this data as **List B**.

---
#### [repeat step 1 - 5, every 30min +/- random time-offset]

### Step 1: Fetch All Humans
- Query **Nethermind RPC** to retrieve the complete list of v2 human accounts registered in the Hub.
  - Store this data as **List A**.

---

### Step 2: Filter Blacklisted
- Check each account in **List A** against the cache/database:
  - **Blacklist Check**:
    - If the account is blacklisted, remove it from **List A** and from **List B**.

---

### Step 3: Evaluate Backing for Trusted and Not-Blacklisted Humans

#### Sub-Step 3a: First Check for Backed Already Trusted Humans
- For all accounts in **List B**, check the `LBP indexer RPC` to determine if their CRC is sufficiently backed:
  - If **backed**:
    - Add the account to **List D** and **List C**.
    - Remove it from **Lists A and B**.
  - else if `APPEND_ONLY`:
    - Add the account to **List C**.
    - Remove it from **List A**.
  - Stop if **|C| >= 10,000**, and skip to Step 5.

#### Sub-Step 3b: Find Newly Backed Humans
- For all accounts in **List A**, check the `LBP indexer RPC` to determine if their CRC is sufficiently backed:
  - If **backed**:
    - Add the account to **List D** and **List C**.
    - Remove it from **Lists A**.
  - Stop if **|C| >= 10,000**, and skip to Step 5.

---

### Step 4: Trust "Unbacked Friends"

#### Sub-Step 4a: Filter for at least 3 Trust Connections
- For each account in **List A**:
  - Use **Nethermind RPC** to retrieve their `trusted_by` list.
  - Check if the intersection of their `trusted_by` list with **List D** contains **≥ 3 trusted connections**:
    - If not, remove the account from **List A**.

#### Sub-Step 4b: Reconsider First Previously Trusted Accounts
- If not `APPEND_ONLY`:
  - For each account in **List B** that is also in **List A**:
    - Add the account to **List C**.
    - Remove it from **Lists B and A**.
    - Sort the account’s backers by ascending `n_friends_backed` and increment the top 3 backers by +1 on their `n_friends_backed` counter (ie. the least backing so far).

#### Sub-Step 4c: Add New Friends trusted by Backers
- For each remaining account in **List A**:
  - Sort the account’s backers by ascending `n_friends_backed`.
  - If the **top 3 backers** each have backed **< 2 friends**:
    - Add the account to **List C**.
    - Remove it from **List A**.
    - Increment the `n_friends_backed` counter for the top 3 backers by +1.

#### During Sub-Steps 4b and 4c
- Continue processing accounts while **|C| < 10,000**.

---

### Step 5: Finalize Trust List
1. **Determine Changes**:
   - Compare **List C** (new trust list) with the current trust list to calculate:
     - **Δ_JOINERS**: Accounts to be added to the trust list of group.
     - **Δ_LEAVERS**: Accounts to be removed from the trust list of group.
2. **Apply Threshold**:
   - If **|Δ_JOINERS| - |Δ_LEAVERS| > Threshold** (or alternatively, **|Δ_JOINERS| > Threshold**):
     - Truncate **Δ_JOINERS** to fit criteria:
       - First prioritize backed accounts (select randomly if needed).
       - Then if threshold not met, randomly select unbacked friends until threshold
3. **Update Supergroup and Cache/Database**:
   - Apply the new trust list on-chain
   - Update **List B** (or cache/database) with the results.
