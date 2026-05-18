// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {IHub} from "src/score-group/interfaces/IHub.sol";
import {IScoreTreasury} from "src/score-group/interfaces/IScoreTreasury.sol";
import {SMT} from "src/score-group/libraries/SparseMerkleTree.sol";
import {Demurrage} from "src/score-group/Demurrage.sol";

/**
 * @title OffchainScoreBasedMintPolicy
 * @notice Mint policy for Circles groups using off-chain scores committed by a Sparse Merkle Tree.
 * @dev Supports personal issuance mints limited by verified scores and router mints limited by
 *      historical collateral supply plus score-based personal mint activity.
 */
contract OffchainScoreBasedMintPolicy is Demurrage {
    using SMT for bytes32;

    struct MerkleRoot {
        bytes32 currentRoot;
        bytes32 previousRoot;
        uint256 updateBlockNumber;
    }

    // =================================================
    //                       ERRORS
    // =================================================

    /// @notice Reverts when a Hub-only function is called by any address other than the Hub.
    error OnlyHub();

    /// @notice Reverts when the caller's group does not use this contract as its mint policy.
    error NotGroupMintPolicy();

    /// @notice Reverts when a group has already been initialized.
    error GroupAlreadyInitialized();

    /// @notice Reverts when a required address argument is the zero address.
    error ZeroAddress();

    /// @notice Reverts when caller is not the configured Merkle tree manager for the group.
    error NotMerkleTreeManager();

    /// @notice Reverts when personal mint collateral is not exactly the minter's personal token.
    error InvalidCollateralForPersonalIssuanceMint();

    /// @notice Reverts when the caller has no currently claimable personal issuance.
    error NoIssuance();

    /// @notice Reverts when personal mint validation is attempted without a prior issuance snapshot.
    error NoSnapshot();

    /// @notice Reverts when personal issuance was not consumed atomically after snapshotting.
    error NotAtomicMint();

    /// @notice Reverts when the provided score is not proven in the group's Merkle tree.
    error InvalidScore();

    /// @notice Reverts when a personal mint amount exceeds the score-adjusted issuance limit.
    error AmountExceedsScoreLimit();

    /// @notice Reverts when the treasury already holds more collateral than the permitted limit.
    error CollateralLimitReached();

    /// @notice Reverts when a router mint amount exceeds currently available collateral capacity.
    error AmountExceedsCollateralLimit();

    // =================================================
    //                    EVENTS
    // =================================================

    /**
     * @notice Emitted when a group initializes its mint policy configuration.
     * @param group Group address being initialized.
     * @param merkleTreeManager Address allowed to update the group's Merkle root.
     * @param pathMintRouter Router address allowed to perform router/migration mints.
     */
    event GroupInitialized(address indexed group, address indexed merkleTreeManager, address pathMintRouter);

    /**
     * @notice Emitted when a group's score Merkle root is updated.
     * @param group Group whose Merkle root was updated.
     * @param newMerkleRoot New Sparse Merkle Tree root.
     */
    event MerkleRootUpdated(
        address indexed group, bytes32 newMerkleRoot, bytes32 previousRoot, uint256 updateBlockNumber
    );

    /**
     * @notice Emitted when historical supply is snapshotted for collateral.
     * @param collateral Collateral token ID.
     * @param supply Total collateral supply at snapshot time.
     * @param day Demurrage day of the snapshot.
     */
    event HistoricalSupply(address indexed group, uint256 indexed collateral, uint256 supply, uint256 day);

    /**
     * @notice Emitted when a personal issuance mint is approved.
     * @param group Group receiving the mint.
     * @param collateral Personal collateral token ID.
     * @param amount Amount approved for minting.
     * @param score Verified score used to determine the mint limit.
     * @param mintedAmountOnToday Total demurrage-adjusted personal amount minted today.
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
     * @notice Emitted when a router/migration mint is approved.
     * @param group Group receiving the mint.
     * @param collateral Collateral token ID.
     * @param amount Amount approved for minting.
     * @param currentAvailableLimit Remaining available limit after this mint.
     */
    event RouterMinted(
        address indexed group, uint256 indexed collateral, uint256 amount, uint256 currentAvailableLimit
    );

    // =================================================
    //                     CONSTANTS
    // =================================================

    /// @notice Circles Hub v2.
    IHub public constant HUB = IHub(address(0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8));

    /// @notice Maximum score used for score-based issuance limits.
    uint256 public constant MAX_SCORE = 100;

    // =================================================
    //                    STATE
    // =================================================

    /// @notice Merkle root per group.
    mapping(address group => MerkleRoot merkleRoot) public merkleRoots;

    /// @notice Address allowed to update each group's Merkle root.
    mapping(address group => address merkleRootManager) public merkleTreeManagers;

    /// @notice Router address allowed to perform router/migration mints for each group.
    mapping(address group => address pathMintRouter) public pathMintRouters;

    /// @dev Lazily snapshotted historical supply per collateral token.
    mapping(address group => mapping(uint256 collateral => DiscountedBalance historicalSupply)) internal
        historicalSupplies;

    /// @dev Demurrage-adjusted personal mint totals per group and collateral token.
    mapping(address group => mapping(uint256 collateral => DiscountedBalance personalMint)) internal personalMints;

    mapping(address => uint256) internal snapshottedIssuances;

    // =================================================
    //                    MODIFIERS
    // =================================================

    /// @notice Restricts execution to the Hub.
    modifier onlyHub() {
        _onlyHub();
        _;
    }

    /// @notice Deploys the mint policy.
    constructor() {}

    // =================================================
    //                 EXTERNAL FUNCTIONS
    // =================================================

    /**
     * @notice Initializes mint policy configuration for the calling group.
     * @dev The caller must be a group whose Hub mint policy is this contract.
     * @param merkleTreeManager Address allowed to update the group's Merkle root.
     * @param pathMintRouter Address allowed to perform router/migration mints.
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
     * @notice Updates the score Merkle root for a group.
     * @dev Only the configured Merkle tree manager for `group` may update the root.
     * @param group Group whose Merkle root is updated.
     * @param newMerkleRoot New Sparse Merkle Tree root committing user scores.
     */
    function updateMerkleRoot(address group, bytes32 newMerkleRoot) external {
        if (merkleTreeManagers[group] != msg.sender) revert NotMerkleTreeManager();
        bytes32 previousRoot = merkleRoots[group].currentRoot;
        merkleRoots[group] = MerkleRoot(newMerkleRoot, previousRoot, block.number);
        emit MerkleRootUpdated(group, newMerkleRoot, previousRoot, block.number);
    }

    /**
     * @notice Snapshots the caller's currently available personal issuance.
     * @dev Stores issuance in transient storage. The following personal mint validation must consume
     *      the issuance atomically in the same transaction, otherwise validation reverts.
     */
    function snapshotIssuance() external {
        uint256 issuance = _getHumanIssuance(msg.sender);
        if (issuance == 0) revert NoIssuance();
        snapshottedIssuances[msg.sender] = issuance;
    }

    function consumeScore(bytes32 slot) external returns (uint256 score) {
        assembly {
            score := tload(slot)
            tstore(slot, 0)
        }
    }

    /**
     * @notice Checks whether a mint operation is allowed before execution.
     * @dev Called by the Hub. If `minter` is not the configured router, validates a personal issuance
     *      mint using an off-chain score proof. If `minter` is the configured router, enforces
     *      collateral limits against the group's treasury balance.
     * @param minter Address initiating the mint.
     * @param group Group token being minted.
     * @param collateral Collateral token IDs used for the mint.
     * @param amounts Amounts to mint per collateral token.
     * @param data ABI-encoded `(uint256 score, bytes proof)` for personal issuance mints.
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
            // store score for treasury consumation
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
                try IScoreTreasury(treasury).balanceOfCollateral{gas: 100_000}(collateral[i]) returns (uint256 returnedBalance) {
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
     * @dev This policy does not restrict burns.
     * @return A boolean indicating whether the burn is approved.
     */
    function beforeBurnPolicy(address, address, uint256, bytes calldata)
        external
        view
        onlyHub
        returns (bool)
    {
        return true;
    }

    // =================================================
    //                 VIEW FUNCTIONS
    // =================================================

    /**
     * @notice Returns a collateral token's historical supply discounted to today.
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
     * @notice Returns personal mint total for a group and collateral token discounted to today.
     * @param group Group address.
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

    /// @dev Reverts unless the caller is the Hub.
    function _onlyHub() internal view {
        if (msg.sender != address(HUB)) revert OnlyHub();
    }

    /**
     * @notice Returns currently available human issuance for a user.
     * @param user Address whose issuance is queried.
     * @return issuance Currently claimable issuance amount.
     */
    function _getHumanIssuance(address user) internal view returns (uint256) {
        (uint256 issuance,,) = HUB.calculateIssuance(user);
        return issuance;
    }

    /**
     * @notice Discounts an amount from its last update day to the current day.
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
     * @notice Initializes historical supply for a collateral token if not already initialized.
     * @dev Snapshots current Hub total supply and stores it with the current demurrage day.
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
     * @dev Loads and clears the caller's transient issuance snapshot, verifies atomic consumption of
     *      issuance, checks the score proof, caps score at `MAX_SCORE`, and enforces the score-based limit.
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

        if (!merkleRoots[group].currentRoot.verify(uint160(minter), bytes32(score), proof)) {
            if (
                block.number > merkleRoots[group].updateBlockNumber + 2
                    || !merkleRoots[group].previousRoot.verify(uint160(minter), bytes32(score), proof)
            ) revert InvalidScore();
        }

        if (score > MAX_SCORE) score = MAX_SCORE;

        if (amount > (score * snapshottedIssuance) / MAX_SCORE) revert AmountExceedsScoreLimit();

        snapshottedIssuances[minter] = 0;
    }
}
