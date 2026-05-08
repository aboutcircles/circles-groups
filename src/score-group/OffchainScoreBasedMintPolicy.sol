// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {IHub} from "src/score-group/interfaces/IHub.sol";
import {SMT} from "src/score-group/libraries/SparseMerkleTree.sol";
import {Demurrage} from "src/score-group/Demurrage.sol";

/**
 * @title OffchainScoreBasedMintPolicy
 */
contract OffchainScoreBasedMintPolicy is Demurrage {
    using SMT for bytes32;

    // =================================================
    //                       ERRORS
    // =================================================
    error OnlyHub();
    error NotGroupMintPolicy();
    error GroupAlreadyInitialized();
    error ZeroAddress();
    error NotMerkleTreeManager();
    error InvalidCollateralForPersonalIssuanceMint();
    error NoIssuance();
    error NoSnapshot();
    error NotAtomicMint();
    error InvalidScore();
    error AmountExceedsScoreLimit();
    error CollateralLimitReached();
    error AmountExceedsCollateralLimit();

    // =================================================
    //                    EVENTS
    // =================================================
    event GroupInitialized(address indexed group, address indexed merkleTreeManager, address pathMintRouter);
    event MerkleRootUpdated(address indexed group, bytes32 newMerkleRoot);
    event HistoricalSupply(uint256 indexed collateral, uint256 supply, uint256 day);
    event PersonalMinted(
        address indexed group,
        uint256 indexed collateral,
        uint256 amount,
        uint256 score,
        uint256 mintedAmountOnToday,
        uint256 day
    );
    event RouterMinted(
        address indexed group, uint256 indexed collateral, uint256 amount, uint256 currentAvailableLimit
    );

    // =================================================
    //                     CONSTANTS
    // =================================================

    /// @notice Circles Hub v2.
    IHub public constant HUB = IHub(address(0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8));
    uint256 public constant MAX_SCORE = 100;

    // =================================================
    //                    STATE
    // =================================================

    mapping(address group => bytes32 merkleRoot) public merkleRoots;
    mapping(address group => address merkleRootManager) public merkleTreeManagers;
    mapping(address group => address pathMintRouter) public pathMintRouters;

    mapping(uint256 collateral => DiscountedBalance historicalSupply) internal historicalSupplies;
    mapping(address group => mapping(uint256 collateral => DiscountedBalance personalMint)) internal personalMints;

    // =================================================
    //                    MODIFIERS
    // =================================================

    modifier onlyHub() {
        _onlyHub();
        _;
    }

    constructor() {}

    function initializeGroup(address merkleTreeManager, address pathMintRouter) external {
        address group = msg.sender;
        if (HUB.mintPolicies(group) != address(this)) revert NotGroupMintPolicy();
        if (merkleTreeManagers[group] != address(0)) revert GroupAlreadyInitialized();
        if (merkleTreeManager == address(0) || pathMintRouter == address(0)) revert ZeroAddress();
        merkleTreeManagers[group] = merkleTreeManager;
        pathMintRouters[group] = pathMintRouter;
        emit GroupInitialized(group, merkleTreeManager, pathMintRouter);
    }

    function updateMerkleRoot(address group, bytes32 newMerkleRoot) external {
        if (merkleTreeManagers[group] != msg.sender) revert NotMerkleTreeManager();
        merkleRoots[group] = newMerkleRoot;
        emit MerkleRootUpdated(group, newMerkleRoot);
    }

    function snapshotIssuance() external {
        uint256 issuance = _getHumanIssuance(msg.sender);
        if (issuance == 0) revert NoIssuance();
        bytes32 slot = keccak256(abi.encode(msg.sender));
        assembly {
            tstore(slot, issuance)
        }
    }

    /**
     * @notice Checks whether a mint operation is allowed before execution.
     * @return bool A boolean value indicating whether the mint is approved.
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
            _ensureHistoricalSupplyInitialized(collateral[0]);

            (uint256 score, bytes memory proof) = abi.decode(data, (uint256, bytes));
            _validatePersonalIssuanceMint(group, minter, score, proof, amounts[0]);
            uint64 today = day(block.timestamp);
            uint256 mintedAmountOnToday = getMintedAmountOnToday(group, collateral[0]) + amounts[0];
            personalMints[group][collateral[0]] = DiscountedBalance(uint192(mintedAmountOnToday), today);
            emit PersonalMinted(group, collateral[0], amounts[0], score, mintedAmountOnToday, today);
        } else {
            // migration mint branch
            address treasury = HUB.treasuries(group);
            for (uint256 i; i < collateral.length;) {
                _ensureHistoricalSupplyInitialized(collateral[i]);

                // check limits
                uint256 historicalSupplyOnToday = getHistoricalSupplyOnToday(collateral[i]);
                // personal minted
                uint256 mintedAmountOnToday = getMintedAmountOnToday(group, collateral[i]);
                uint256 maxLimit = historicalSupplyOnToday + mintedAmountOnToday;

                uint256 treasuryBalance = HUB.balanceOf(treasury, collateral[i]);

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
     * @return bool A boolean value indicating whether the burn is approved.
     */
    function beforeBurnPolicy(address burner, address group, uint256 amount, bytes calldata data)
        external
        onlyHub
        returns (bool)
    {
        return true;
    }

    // =================================================
    //                 VIEW FUNCTIONS
    // =================================================

    function getHistoricalSupplyOnToday(uint256 collateral) public view returns (uint256 historicalSupplyOnToday) {
        DiscountedBalance memory discountedBalance = historicalSupplies[collateral];
        historicalSupplyOnToday = _calculateAmountOnToday(discountedBalance.balance, discountedBalance.lastUpdatedDay);
    }

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

    function _onlyHub() internal view {
        if (msg.sender != address(HUB)) revert OnlyHub();
    }

    function _getHumanIssuance(address user) internal view returns (uint256) {
        (uint256 issuance,,) = HUB.calculateIssuance(user);
        return issuance;
    }

    function _calculateAmountOnToday(uint192 amount, uint64 lastUpdatedDay)
        internal
        view
        returns (uint256 amountOnToday)
    {
        uint64 today = day(block.timestamp);
        amountOnToday = _calculateDiscountedBalance(amount, today - lastUpdatedDay);
    }

    function _ensureHistoricalSupplyInitialized(uint256 collateral) internal {
        if (historicalSupplies[collateral].balance == 0) {
            uint64 today = day(block.timestamp);
            uint192 supply = uint192(HUB.totalSupply(collateral));
            historicalSupplies[collateral] = DiscountedBalance(supply, today);
            emit HistoricalSupply(collateral, supply, today);
        }
    }

    function _validatePersonalIssuanceMint(
        address group,
        address minter,
        uint256 score,
        bytes memory proof,
        uint256 amount
    ) internal {
        bytes32 slot = keccak256(abi.encode(minter));
        uint256 snapshottedIssuance;
        assembly {
            snapshottedIssuance := tload(slot)
            tstore(slot, 0)
        }
        if (snapshottedIssuance == 0) revert NoSnapshot();

        uint256 currentIssuance = _getHumanIssuance(minter);
        if (currentIssuance != 0) revert NotAtomicMint();

        if (!merkleRoots[group].verify(uint160(minter), bytes32(score), proof)) revert InvalidScore();

        if (score > MAX_SCORE) score = MAX_SCORE;

        if (amount > (score * snapshottedIssuance) / MAX_SCORE) revert AmountExceedsScoreLimit();
    }
}
