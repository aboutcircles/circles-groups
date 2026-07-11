// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {IHub} from "src/score-group/interfaces/IHub.sol";
import {INameRegistry} from "src/score-group/interfaces/INameRegistry.sol";
import {IOffchainScoreBasedMintPolicy} from "src/score-group/interfaces/IOffchainScoreBasedMintPolicy.sol";

/**
 * @title ScoreTreasury
 * @notice Custody contract for ScoreGroup collateral that routes received collateral into score-based sub-treasuries.
 * @dev
 * The treasury receives Circles Hub ERC1155 collateral and immediately forwards it to one of two
 * sub-treasuries:
 * - collateral received from the configured mint router is routed to the high-score sub-treasury;
 * - collateral received from a personal mint flow is routed according to the score consumed from the
 *   configured mint policy in the same transaction.
 *
 * The treasury itself is an ERC1155 receiver and only accepts transfers initiated by the Hub. Before
 * forwarding collateral, it verifies that the group trusts the collateral avatar represented by the
 * ERC1155 token id.
 *
 * The contract also exposes an aggregate collateral balance helper used by the mint policy to account
 * for collateral held across both sub-treasuries.
 */
contract ScoreTreasury {
    // =================================================
    //                       ERRORS
    // =================================================

    /**
     * @notice Thrown when a function is called by an account other than the Hub.
     */
    error OnlyHub();

    /**
     * @notice Thrown when a function is called by an account other than the Group.
     */
    error OnlyGroup();

    /**
     * @notice Thrown when a personal mint transfer cannot consume a non-zero score from the mint policy.
     * @dev A zero consumed score is treated as evidence that the collateral transfer was not part of the
     *      expected atomic personal mint flow.
     */
    error AtomicMintRequired();

    /**
     * @notice Thrown when an ERC1155 collateral token received is not trusted by the group.
     */
    error CollateralIsNotTrustedByGroup();

    // =================================================
    //                     CONSTANTS
    // =================================================

    /**
     * @notice Minimum score routed to the high-score sub-treasury for personal mint collateral.
     * @dev Personal mint collateral with a consumed score below this threshold is routed to the low-score
     *      sub-treasury. Scores greater than or equal to this threshold are routed to the high-score sub-treasury.
     */
    uint256 public constant HIGH_SCORE_THRESHOLD = 50;

    /**
     * @notice The Hub contract that manages trust relationships and other Circles operations.
     */
    IHub public immutable HUB;

    /**
     * @notice The address of the group for which this treasury is created.
     */
    address public immutable GROUP;

    /**
     * @notice Mint policy used to consume the transient score associated with a personal mint flow.
     */
    IOffchainScoreBasedMintPolicy public immutable MINT_POLICY;

    /**
     * @notice Router address whose incoming collateral is always routed to the high-score sub-treasury.
     */
    address public immutable MINT_ROUTER;

    /**
     * @notice Sub-treasury that receives collateral from personal mint flows with scores below {HIGH_SCORE_THRESHOLD}.
     */
    address public immutable LOW_SCORE_SUB_TREASURY;

    /**
     * @notice Sub-treasury that receives router collateral and personal mint collateral with scores at or above {HIGH_SCORE_THRESHOLD}.
     */
    address public immutable HIGH_SCORE_SUB_TREASURY;

    // =================================================
    //                    MODIFIERS
    // =================================================

    /**
     * @notice Ensures the function is only called by the Hub.
     * @dev Reverts if `msg.sender` is not the Hub contract.
     */
    modifier onlyHub() {
        if (msg.sender != address(HUB)) {
            revert OnlyHub();
        }
        _;
    }

    // =================================================
    //                    CONSTRUCTOR
    // =================================================

    /**
     * @notice Deploys the treasury and its two score-tier sub-treasuries.
     * @dev
     * The deploying treasury becomes the `TREASURY` authorized to send collateral into both
     * sub-treasuries. Each sub-treasury registers itself as a Hub organization during construction.
     *
     * @param _hub Address of the Circles Hub used for ERC1155 balances, transfers, burns, trust, and registration.
     * @param _group Group avatar address associated with this treasury.
     * @param _mintPolicy Mint policy used to consume personal-mint scores.
     * @param _mintRouter Router address whose incoming collateral is treated as router/migration collateral.
     * @param _groupName Human-readable group name used to derive sub-treasury organization names.
     * @param _metadataDigest Initial metadata digest passed to each sub-treasury organization registration.
     */
    constructor(
        address _hub,
        address _group,
        address _mintPolicy,
        address _mintRouter,
        string memory _groupName,
        bytes32 _metadataDigest
    ) {
        HUB = IHub(_hub);
        GROUP = _group;
        MINT_POLICY = IOffchainScoreBasedMintPolicy(_mintPolicy);
        MINT_ROUTER = _mintRouter;
        LOW_SCORE_SUB_TREASURY = address(new ScoreSubTreasury(_hub, _group, _groupName, _metadataDigest));
        HIGH_SCORE_SUB_TREASURY = address(new ScoreSubTreasury(_hub, _group, _groupName, _metadataDigest));
    }

    // =================================================
    //                EXTERNAL FUNCTIONS
    // =================================================

    /**
     * @notice Updates the metadata digest for both sub-treasury organizations.
     * @dev
     * Only the configured group may call this function. The treasury forwards the metadata update to
     * both sub-treasuries, which then call the supplied name registry from their own organization context.
     *
     * @param nameRegistry Address of the name registry contract to update.
     * @param _metadataDigest New off-chain metadata digest for both sub-treasury organizations.
     */
    function updateMetadataDigest(address nameRegistry, bytes32 _metadataDigest) external {
        if (msg.sender != GROUP) revert OnlyGroup();
        ScoreSubTreasury(LOW_SCORE_SUB_TREASURY).updateMetadataDigest(nameRegistry, _metadataDigest);
        ScoreSubTreasury(HIGH_SCORE_SUB_TREASURY).updateMetadataDigest(nameRegistry, _metadataDigest);
    }

    /**
     * @notice Returns the total collateral balance held across both score-tier sub-treasuries.
     * @dev
     * The returned value is the sum of the Hub ERC1155 balances for `collateralId` held by
     * {LOW_SCORE_SUB_TREASURY} and {HIGH_SCORE_SUB_TREASURY}.
     *
     * @param collateralId ERC1155 collateral token id to query.
     * @return balance Aggregate collateral balance across both sub-treasuries.
     */
    function balanceOfCollateral(uint256 collateralId) external view returns (uint256 balance) {
        balance = HUB.balanceOf(LOW_SCORE_SUB_TREASURY, collateralId);
        balance += HUB.balanceOf(HIGH_SCORE_SUB_TREASURY, collateralId);
    }

    // =================================================
    //         ERC1155 RECEIVER FUNCTION
    // =================================================

    /**
     * @notice Handles receipt of a single ERC1155 collateral token from the Hub.
     * @dev
     * Only callable by the Hub. The received token id must represent collateral trusted by the group.
     *
     * Routing behavior:
     * - if `from` is the configured mint router, the collateral is forwarded to the high-score sub-treasury;
     * - otherwise, the treasury consumes the score stored by the mint policy for `(from, block.timestamp)`;
     * - personal mint collateral with score below {HIGH_SCORE_THRESHOLD} is forwarded to the low-score
     *   sub-treasury, while score greater than or equal to the threshold is forwarded to the high-score
     *   sub-treasury.
     *
     * Reverts with {AtomicMintRequired} if no non-zero score can be consumed for a non-router transfer.
     *
     * @param from Address reported by the Hub as the source of the ERC1155 transfer.
     * @param _id ERC1155 token id being received.
     * @param _value Amount of `_id` being received.
     * @return A bytes4 constant equal to this function's selector, indicating successful receipt.
     */
    function onERC1155Received(address, address from, uint256 _id, uint256 _value, bytes memory)
        external
        onlyHub
        returns (bytes4)
    {
        if (!HUB.isTrusted(GROUP, address(uint160(_id)))) {
            revert CollateralIsNotTrustedByGroup();
        }

        address subTreasury;
        if (from == MINT_ROUTER) {
            subTreasury = HIGH_SCORE_SUB_TREASURY;
        } else {
            // ask policy
            uint256 score = MINT_POLICY.consumeScore(keccak256(abi.encode(from, block.timestamp)));
            if (score == 0) revert AtomicMintRequired();
            subTreasury = score < HIGH_SCORE_THRESHOLD ? LOW_SCORE_SUB_TREASURY : HIGH_SCORE_SUB_TREASURY;
        }

        HUB.safeTransferFrom(address(this), subTreasury, _id, _value, "");

        return this.onERC1155Received.selector;
    }
}

/**
 * @title ScoreSubTreasury
 * @notice ERC1155 holding organization used by {ScoreTreasury} for one score tier.
 * @dev
 * A sub-treasury is deployed by {ScoreTreasury}, registers itself as a Hub organization, and trusts
 * the associated group. It only accepts ERC1155 transfers sent by the parent treasury through the Hub.
 *
 * Whenever it receives collateral from the parent treasury, it burns any group-token balance it holds.
 * This keeps group-token balances from accumulating inside the sub-treasury after Hub flows that may
 * leave group id tokens alongside collateral.
 */
contract ScoreSubTreasury {
    // =================================================
    //                       ERRORS
    // =================================================

    /**
     * @notice Thrown when a function is called by an account other than the Hub.
     */
    error OnlyHub();

    /**
     * @notice Thrown when a received ERC1155 transfer does not originate from the parent treasury.
     */
    error OnlyTreasury();

    // =================================================
    //                     CONSTANTS
    // =================================================

    /**
     * @notice The Hub contract that manages trust relationships and other Circles operations.
     */
    IHub public immutable HUB;

    /**
     * @notice Parent treasury authorized to send ERC1155 tokens into this sub-treasury.
     */
    address public immutable TREASURY;

    /**
     * @notice The address of the group for which this sub-treasury is created.
     */
    address public immutable GROUP;

    // =================================================
    //                    MODIFIERS
    // =================================================

    /**
     * @notice Ensures the function is only called by the Hub.
     * @dev Reverts if `msg.sender` is not the Hub contract.
     */
    modifier onlyHub() {
        if (msg.sender != address(HUB)) {
            revert OnlyHub();
        }
        _;
    }

    /**
     * @notice Ensures an ERC1155 transfer was sent from the parent treasury.
     * @dev Reverts with {OnlyTreasury} if `from` is not {TREASURY}.
     * @param from Address reported by the Hub as the source of the ERC1155 transfer.
     */
    modifier onlyTreasury(address from) {
        if (from != TREASURY) {
            revert OnlyTreasury();
        }
        _;
    }

    // =================================================
    //                    CONSTRUCTOR
    // =================================================

    /**
     * @notice Deploys a sub-treasury and registers it as a Hub organization.
     * @dev
     * The deploying contract becomes {TREASURY}. The sub-treasury registers an organization named
     * `string.concat(_groupName, "-sub-treasury")`, then trusts the associated group with the maximum
     * expiry value.
     *
     * @param _hub Address of the Circles Hub.
     * @param _group Group avatar address associated with the parent treasury.
     * @param _groupName Human-readable group name used to derive the organization name.
     * @param _metadataDigest Initial metadata digest used during Hub organization registration.
     */
    constructor(address _hub, address _group, string memory _groupName, bytes32 _metadataDigest) {
        HUB = IHub(_hub);
        GROUP = _group;
        TREASURY = msg.sender;

        string memory treasuryName = string.concat(_groupName, "-sub-treasury");
        HUB.registerOrganization(treasuryName, _metadataDigest);
        HUB.trust(_group, type(uint96).max);
    }

    // =================================================
    //                EXTERNAL FUNCTIONS
    // =================================================

    /**
     * @notice Burns all group-token balance currently held by this sub-treasury.
     * @dev
     * The group token id is derived from `GROUP` as `uint256(uint160(GROUP))`. If this sub-treasury
     * holds no group-token balance, the function is a no-op.
     */
    function burn() public {
        uint256 id = uint256(uint160(GROUP));
        uint256 amount = HUB.balanceOf(address(this), id);
        if (amount > 0) HUB.burn(id, amount, "");
    }

    /**
     * @notice Updates this sub-treasury organization's metadata digest in a name registry.
     * @dev Only callable by the parent treasury.
     * @param nameRegistry Address of the name registry contract to update.
     * @param _metadataDigest New off-chain metadata digest for this sub-treasury organization.
     */
    function updateMetadataDigest(address nameRegistry, bytes32 _metadataDigest) external onlyTreasury(msg.sender) {
        INameRegistry(nameRegistry).updateMetadataDigest(_metadataDigest);
    }

    // =================================================
    //         ERC1155 RECEIVER FUNCTIONS
    // =================================================

    /**
     * @notice Handles receipt of a single ERC1155 token from the parent treasury through the Hub.
     * @dev
     * Only callable by the Hub, and the transfer source reported by the Hub must be the parent treasury.
     * After receiving the token, the sub-treasury burns any group-token balance it holds.
     *
     * @param from Address reported by the Hub as the source of the ERC1155 transfer.
     * @return A bytes4 constant equal to this function's selector, indicating successful receipt.
     */
    function onERC1155Received(address, address from, uint256, uint256, bytes memory)
        external
        onlyHub
        onlyTreasury(from)
        returns (bytes4)
    {
        burn();
        return this.onERC1155Received.selector;
    }
}
