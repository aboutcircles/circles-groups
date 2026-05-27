// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {IHub} from "src/score-group/interfaces/IHub.sol";
import {IMerkleTreeRegistry} from "src/score-group/interfaces/IMerkleTreeRegistry.sol";
import {IScoreTreasury} from "src/score-group/interfaces/IScoreTreasury.sol";
import {Demurrage} from "src/score-group/Demurrage.sol";

/**
 * @title OffchainScoreBasedMintPolicy
 * @notice Mint policy for Circles groups whose personal issuance limits are derived from off-chain scores.
 * @dev This policy is intended to be installed as a Circles Hub v2 group mint policy. Each initialized
 *      group has an independently configured Merkle tree manager, router, historical collateral supply
 *      accounting, and personal mint accounting.
 *
 *      Personal issuance mints are approved when the minter proves a score through the configured
 *      `MERKLE_TREE_REGISTRY` namespace for the group. The registry may accept proofs against the current
 *      root, or against the previous root during its configured grace period. The requested mint amount may
 *      not exceed `score / MAX_SCORE` of the minter's previously snapshotted personal issuance.
 *
 *      Router or migration mints are approved against collateral capacity. Capacity is computed as the
 *      demurrage-adjusted historical collateral supply plus demurrage-adjusted personal mints for the same
 *      group and collateral, minus the group's current treasury balance for that collateral.
 *
 *      This contract inherits demurrage calculation helpers from `Demurrage` and delegates score proof
 *      verification to `MERKLE_TREE_REGISTRY`.
 */
contract OffchainScoreBasedMintPolicy is Demurrage {
    // =================================================
    //                       ERRORS
    // =================================================

    /// @notice Reverts when a Hub-only function is called by an address other than `HUB`.
    error OnlyHub();

    /// @notice Reverts when the caller is not a Hub group whose configured mint policy is this contract.
    error NotGroupMintPolicy();

    /// @notice Reverts when a group attempts to initialize its mint policy configuration more than once.
    error GroupAlreadyInitialized();

    /// @notice Reverts when a required address argument is the zero address.
    error ZeroAddress();

    /// @notice Reverts when personal mint collateral is not exactly the minter's personal token ID.
    error InvalidCollateralForPersonalIssuanceMint();

    /// @notice Reverts when the caller has no currently claimable personal issuance to snapshot.
    error NoIssuance();

    /// @notice Reverts when personal mint validation is attempted without a prior issuance snapshot.
    error NoSnapshot();

    /// @notice Reverts when the minter still has currently claimable issuance after snapshotting.
    error NotAtomicMint();

    /// @notice Reverts when the provided score is not proven through the configured Merkle tree registry namespace.
    error InvalidScore();

    /// @notice Reverts when a personal mint amount exceeds the score-adjusted issuance limit.
    error AmountExceedsScoreLimit();

    /// @notice Reverts when the treasury already holds more collateral than the permitted collateral limit.
    error CollateralLimitReached();

    /// @notice Reverts when a router mint amount exceeds currently available collateral capacity.
    error AmountExceedsCollateralLimit();

    // =================================================
    //                    EVENTS
    // =================================================

    /**
     * @notice Emitted when a group initializes its mint policy configuration.
     * @param group Group address being initialized.
     * @param merkleTreeManager Address whose registry root namespace is used for score proof verification.
     * @param pathMintRouter Router address allowed to perform router or migration mints for the group.
     */
    event GroupInitialized(address indexed group, address indexed merkleTreeManager, address pathMintRouter);

    /**
     * @notice Emitted when historical supply is snapshotted for a group and collateral token.
     * @dev The snapshot is created lazily the first time the group/collateral pair is used by this policy.
     * @param group Group for which the historical collateral supply is snapshotted.
     * @param collateral Collateral token ID.
     * @param supply Total collateral supply at snapshot time, before future demurrage adjustment.
     * @param day Demurrage day of the snapshot.
     */
    event HistoricalSupply(address indexed group, uint256 indexed collateral, uint256 supply, uint256 day);

    /**
     * @notice Emitted when a personal issuance mint is approved.
     * @param group Group receiving the mint.
     * @param collateral Personal collateral token ID, expected to equal `uint160(minter)`.
     * @param amount Amount approved for minting.
     * @param score Verified score used to determine the mint limit.
     * @param mintedAmountOnToday Total demurrage-adjusted personal amount minted today after this mint.
     * @param day Demurrage day of the mint.
     */
    event PersonalMinted(
        address indexed group,
        uint256 indexed collateral,
        uint256 amount,
        uint256 score,
        uint256 mintedAmountOnToday,
        uint256 day
    );

    /**
     * @notice Emitted when a router or migration mint is approved.
     * @param group Group receiving the mint.
     * @param collateral Collateral token ID used for the router mint.
     * @param amount Amount approved for minting.
     * @param currentAvailableLimit Remaining available collateral capacity after this mint.
     */
    event RouterMinted(
        address indexed group, uint256 indexed collateral, uint256 amount, uint256 currentAvailableLimit
    );

    // =================================================
    //                     CONSTANTS
    // =================================================

    /**
     * @notice Circles Hub v2 contract used for issuance, balances, treasuries, mint policies, and supply reads.
     * @dev This address is hard-coded for the deployment environment targeted by this policy.
     */
    IHub public constant HUB = IHub(address(0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8));

    /**
     * @notice Merkle tree registry used to verify score proofs for configured group managers.
     * @dev Root storage, previous-root grace-period handling, and Sparse Merkle Tree proof verification
     *      are delegated to this registry.
     */
    IMerkleTreeRegistry public constant MERKLE_TREE_REGISTRY =
        IMerkleTreeRegistry(address(0xB4bfedaD42a14c30Bd9C1FdBf3e11916Fc719E6C));

    /**
     * @notice Maximum score used for score-based issuance limits.
     * @dev Scores above this value are capped to this value before calculating the personal mint limit.
     */
    uint256 public constant MAX_SCORE = 100;

    // =================================================
    //                    STATE
    // =================================================

    /**
     * @notice Merkle tree registry namespace used for each group's score proof verification.
     * @dev A group can set this value only once through `initializeGroup`. The configured address is passed
     *      to `MERKLE_TREE_REGISTRY` when verifying score proofs.
     */
    mapping(address group => address merkleRootManager) public merkleTreeManagers;

    /**
     * @notice Router address allowed to perform router or migration mints for each group.
     * @dev Calls to `beforeMintPolicy` from any other minter are treated as personal issuance mints.
     */
    mapping(address group => address pathMintRouter) public pathMintRouters;

    /**
     * @notice Lazily snapshotted historical supply per group and collateral token.
     * @dev Stores a `DiscountedBalance` whose `balance` is the Hub total supply at first use and whose
     *      `lastUpdatedDay` is the demurrage day of that snapshot.
     */
    mapping(address group => mapping(uint256 collateral => DiscountedBalance historicalSupply)) internal
        historicalSupplies;

    /**
     * @notice Demurrage-adjusted personal mint totals per group and collateral token.
     * @dev Stores the aggregate personal mint amount for a group/collateral pair, represented as a
     *      `DiscountedBalance` and periodically normalized to the current demurrage day on write.
     */
    mapping(address group => mapping(uint256 collateral => DiscountedBalance personalMint)) internal personalMints;

    /**
     * @notice Snapshotted personal issuance per minter.
     * @dev This is persistent contract storage. `snapshotIssuance` writes the caller's current Hub issuance,
     *      and `_validatePersonalIssuanceMint` clears it after a successful personal mint validation.
     */
    mapping(address => uint256) internal snapshottedIssuances;

    // =================================================
    //                    MODIFIERS
    // =================================================

    /**
     * @notice Restricts execution to the Circles Hub.
     * @dev Reverts with `OnlyHub` when `msg.sender` is not `HUB`.
     */
    modifier onlyHub() {
        _onlyHub();
        _;
    }

    /**
     * @notice Deploys the mint policy.
     * @dev The constructor performs no initialization; group-specific configuration is set by each group
     *      through `initializeGroup` after the Hub points the group mint policy to this contract.
     */
    constructor() {}

    // =================================================
    //                 EXTERNAL FUNCTIONS
    // =================================================

    /**
     * @notice Initializes mint policy configuration for the calling group.
     * @dev The caller must be a group whose Hub mint policy is this contract. Initialization is one-time:
     *      after `merkleTreeManagers[group]` is set, this function reverts for that group.
     * @param merkleTreeManager Address whose registry root namespace is used for score proof verification.
     * @param pathMintRouter Address allowed to perform router or migration mints for the group.
     */
    function initializeGroup(address merkleTreeManager, address pathMintRouter) external {
        address group = msg.sender;
        if (HUB.mintPolicies(group) != address(this)) revert NotGroupMintPolicy();
        if (merkleTreeManagers[group] != address(0)) revert GroupAlreadyInitialized();
        if (merkleTreeManager == address(0) || pathMintRouter == address(0)) revert ZeroAddress();
        merkleTreeManagers[group] = merkleTreeManager;
        pathMintRouters[group] = pathMintRouter;
        emit GroupInitialized(group, merkleTreeManager, pathMintRouter);
    }

    /**
     * @notice Snapshots the caller's currently available personal issuance.
     * @dev Reads the caller's current Hub issuance and stores it in persistent storage under the caller's
     *      address. A later successful personal mint validation clears this snapshot. Validation also checks
     *      that the caller's current Hub issuance is zero at mint time.
     */
    function snapshotIssuance() external {
        uint256 issuance = _getHumanIssuance(msg.sender);
        if (issuance == 0) revert NoIssuance();
        snapshottedIssuances[msg.sender] = issuance;
    }

    /**
     * @notice Consumes and returns a score stored in transient storage at `slot`.
     * @dev Loads the transient value at `slot`, clears that transient slot, and returns the loaded score.
     *      This function does not derive or validate the slot; callers are expected to know the slot used by
     *      the mint flow.
     * @param slot Transient storage slot from which to load and clear a score.
     * @return score Score loaded from transient storage before the slot was cleared.
     */
    function consumeScore(bytes32 slot) external returns (uint256 score) {
        assembly {
            score := tload(slot)
            tstore(slot, 0)
        }
    }

    /**
     * @notice Checks whether a Hub mint operation is allowed before execution.
     * @dev Called by the Hub. If `minter` is not the configured router for `group`, the call is treated as a
     *      personal issuance mint and must use the minter's personal token as the only collateral. Personal
     *      mints require ABI-encoded `(uint256 score, bytes proof)` data and are capped by the minter's
     *      snapshotted issuance multiplied by `score / MAX_SCORE`.
     *
     *      If `minter` is the configured router for `group`, the call is treated as a router or migration
     *      mint. Each collateral amount is checked against the remaining collateral capacity derived from
     *      historical supply, personal mint activity, and the current treasury balance.
     * @param minter Address initiating the mint through the Hub.
     * @param group Group token being minted.
     * @param collateral Collateral token IDs used for the mint.
     * @param amounts Amounts to mint per collateral token.
     * @param data ABI-encoded `(uint256 score, bytes proof)` for personal issuance mints; unused by the
     *        router branch.
     * @return A boolean indicating whether the mint is approved.
     */
    function beforeMintPolicy(
        address minter,
        address group,
        uint256[] calldata collateral,
        uint256[] calldata amounts,
        bytes calldata data
    ) external onlyHub returns (bool) {
        if (minter != pathMintRouters[group]) {
            // personal mint branch
            if (collateral.length > 1 || collateral[0] != uint256(uint160(minter))) {
                revert InvalidCollateralForPersonalIssuanceMint();
            }
            _ensureHistoricalSupplyInitialized(group, collateral[0]);

            (uint256 score, bytes memory proof) = abi.decode(data, (uint256, bytes));
            _validatePersonalIssuanceMint(group, minter, score, proof, amounts[0]);
            uint64 today = day(block.timestamp);
            uint256 mintedAmountOnToday = getMintedAmountOnToday(group, collateral[0]) + amounts[0];
            personalMints[group][collateral[0]] = DiscountedBalance(uint192(mintedAmountOnToday), today);
            // store score for treasury consumption
            bytes32 slot = keccak256(abi.encode(minter, block.timestamp));
            assembly {
                tstore(slot, score)
            }
            emit PersonalMinted(group, collateral[0], amounts[0], score, mintedAmountOnToday, today);
        } else {
            // migration mint branch
            address treasury = HUB.treasuries(group);
            for (uint256 i; i < collateral.length;) {
                _ensureHistoricalSupplyInitialized(group, collateral[i]);

                // check limits
                uint256 historicalSupplyOnToday = getHistoricalSupplyOnToday(group, collateral[i]);
                // personal minted
                uint256 mintedAmountOnToday = getMintedAmountOnToday(group, collateral[i]);
                uint256 maxLimit = historicalSupplyOnToday + mintedAmountOnToday;

                uint256 treasuryBalance;
                try IScoreTreasury(treasury).balanceOfCollateral{gas: 100_000}(collateral[i]) returns (
                    uint256 returnedBalance
                ) {
                    treasuryBalance = returnedBalance;
                } catch {
                    treasuryBalance = HUB.balanceOf(treasury, collateral[i]);
                }

                if (treasuryBalance > maxLimit) revert CollateralLimitReached();

                uint256 currentLimit = maxLimit - treasuryBalance;

                if (amounts[i] > currentLimit) revert AmountExceedsCollateralLimit();

                emit RouterMinted(group, collateral[i], amounts[i], currentLimit - amounts[i]);

                unchecked {
                    ++i;
                }
            }
        }

        return true;
    }

    /**
     * @notice Checks whether a burn operation is allowed before execution.
     * @dev Called by the Hub. This policy does not restrict burns and always approves them when the caller
     *      is the Hub.
     * @return A boolean indicating whether the burn is approved.
     */
    function beforeBurnPolicy(address, address, uint256, bytes calldata) external view onlyHub returns (bool) {
        return true;
    }

    // =================================================
    //                 VIEW FUNCTIONS
    // =================================================

    /**
     * @notice Returns a collateral token's historical supply discounted to the current demurrage day.
     * @dev If the group/collateral pair has never been initialized, the returned value is calculated from
     *      the zero-value `DiscountedBalance` entry.
     * @param group Group whose historical collateral supply is queried.
     * @param collateral Collateral token ID.
     * @return historicalSupplyOnToday Demurrage-adjusted historical supply for the current day.
     */
    function getHistoricalSupplyOnToday(address group, uint256 collateral)
        public
        view
        returns (uint256 historicalSupplyOnToday)
    {
        DiscountedBalance memory discountedBalance = historicalSupplies[group][collateral];
        historicalSupplyOnToday = _calculateAmountOnToday(discountedBalance.balance, discountedBalance.lastUpdatedDay);
    }

    /**
     * @notice Returns personal mint total for a group and collateral token discounted to the current day.
     * @dev The returned value is the stored personal mint aggregate after applying elapsed demurrage since
     *      its `lastUpdatedDay`.
     * @param group Group whose personal mint aggregate is queried.
     * @param collateral Collateral token ID.
     * @return mintedAmountOnToday Demurrage-adjusted personal mint total for the current day.
     */
    function getMintedAmountOnToday(address group, uint256 collateral)
        public
        view
        returns (uint256 mintedAmountOnToday)
    {
        DiscountedBalance memory discountedBalance = personalMints[group][collateral];
        mintedAmountOnToday = _calculateAmountOnToday(discountedBalance.balance, discountedBalance.lastUpdatedDay);
    }

    // =================================================
    //               INTERNAL FUNCTIONS
    // =================================================

    /**
     * @notice Ensures that the caller is the Circles Hub.
     * @dev Reverts with `OnlyHub` unless `msg.sender` equals `HUB`.
     */
    function _onlyHub() internal view {
        if (msg.sender != address(HUB)) revert OnlyHub();
    }

    /**
     * @notice Returns currently available human issuance for a user.
     * @dev Delegates to `HUB.calculateIssuance` and returns only the issuance amount from the tuple.
     * @param user Address whose issuance is queried.
     * @return issuance Currently claimable issuance amount.
     */
    function _getHumanIssuance(address user) internal view returns (uint256) {
        (uint256 issuance,,) = HUB.calculateIssuance(user);
        return issuance;
    }

    /**
     * @notice Discounts an amount from its last update day to the current demurrage day.
     * @dev Uses `day(block.timestamp)` as the current demurrage day and delegates the actual discount
     *      calculation to `_calculateDiscountedBalance` from `Demurrage`.
     * @param amount Stored amount before applying elapsed demurrage.
     * @param lastUpdatedDay Day on which `amount` was last updated.
     * @return amountOnToday Demurrage-adjusted amount for the current day.
     */
    function _calculateAmountOnToday(uint192 amount, uint64 lastUpdatedDay)
        internal
        view
        returns (uint256 amountOnToday)
    {
        uint64 today = day(block.timestamp);
        amountOnToday = _calculateDiscountedBalance(amount, today - lastUpdatedDay);
    }

    /**
     * @notice Initializes historical supply for a group and collateral token if not already initialized.
     * @dev A group/collateral pair is considered uninitialized when its stored `lastUpdatedDay` is zero.
     *      On first use, the function snapshots `HUB.totalSupply(collateral)` and stores it together with
     *      the current demurrage day.
     * @param group Group whose historical collateral supply entry is initialized.
     * @param collateral Collateral token ID.
     */
    function _ensureHistoricalSupplyInitialized(address group, uint256 collateral) internal {
        if (historicalSupplies[group][collateral].lastUpdatedDay == 0) {
            uint64 today = day(block.timestamp);
            uint192 supply = uint192(HUB.totalSupply(collateral));
            historicalSupplies[group][collateral] = DiscountedBalance(supply, today);
            emit HistoricalSupply(group, collateral, supply, today);
        }
    }

    /**
     * @notice Validates a personal issuance mint against a score proof and snapshotted issuance.
     * @dev Reads the minter's persistent issuance snapshot, requires the minter's current Hub issuance to
     *      be zero, verifies the score through `MERKLE_TREE_REGISTRY.verifyWithGracePeriod` using the group's
     *      configured Merkle tree manager namespace, caps the score at `MAX_SCORE`, and enforces the
     *      score-adjusted issuance limit. On success, clears the minter's stored issuance snapshot.
     * @param group Group for which the score proof is verified.
     * @param minter Address performing the personal issuance mint.
     * @param score Score claimed by the minter.
     * @param proof Sparse Merkle Tree proof for `(minter, score)`.
     * @param amount Amount requested for minting.
     */
    function _validatePersonalIssuanceMint(
        address group,
        address minter,
        uint256 score,
        bytes memory proof,
        uint256 amount
    ) internal {
        uint256 snapshottedIssuance = snapshottedIssuances[minter];
        if (snapshottedIssuance == 0) revert NoSnapshot();

        uint256 currentIssuance = _getHumanIssuance(minter);
        if (currentIssuance != 0) revert NotAtomicMint();

        if (!MERKLE_TREE_REGISTRY.verifyWithGracePeriod(
                merkleTreeManagers[group], uint160(minter), bytes32(score), proof
            )) revert InvalidScore();

        if (score > MAX_SCORE) score = MAX_SCORE;

        if (amount > (score * snapshottedIssuance) / MAX_SCORE) revert AmountExceedsScoreLimit();

        snapshottedIssuances[minter] = 0;
    }
}
