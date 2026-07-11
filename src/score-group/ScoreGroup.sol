// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import {IHub} from "src/score-group/interfaces/IHub.sol";
import {ILiftERC20} from "src/score-group/interfaces/ILiftERC20.sol";
import {INameRegistry} from "src/score-group/interfaces/INameRegistry.sol";
import {IOffchainScoreBasedMintPolicy} from "src/score-group/interfaces/IOffchainScoreBasedMintPolicy.sol";
import {ScoreGroupMintRouter} from "src/score-group/ScoreGroupMintRouter.sol";
import {ScoreTreasury} from "src/score-group/ScoreTreasury.sol";

/**
 * @title ScoreGroup
 * @notice Deploys and manages a Circles score-based group with a dedicated treasury, mint router, and ERC20 wrappers.
 * @dev
 * This contract is intended to be deployed as the group avatar that is registered in the Circles Hub.
 * During construction it:
 * - deploys a {ScoreGroupMintRouter};
 * - deploys a {ScoreTreasury};
 * - registers this contract as a custom Hub group using {SCORE_MINT_POLICY};
 * - initializes the off-chain score based mint policy for this group;
 * - attempts to register a short name in the Name Registry; and
 * - ensures both demurrage and stable ERC20 wrappers exist for the group token.
 *
 * Membership/collateral eligibility is represented through Hub trust from this group to human avatars.
 * Humans may opt out so that third parties cannot re-add trust for them, while the opted-out human may later
 * call {trust} for themselves to clear the opt-out flag and opt back in.
 */
contract ScoreGroup {
    // =================================================
    //                       ERRORS
    // =================================================

    /// @notice Reverts when an address expected to be a Circles human is not registered as a human in the Hub.
    error OnlyHuman();

    /// @notice Reverts when metadata is updated by an address other than {METADATA_MANAGER}.
    error OnlyMetadataManager();

    /// @notice Thrown when calling parameters are invalid (e.g., zero addresses).
    error InvalidCallingParameters();

    /// @notice Reverts when a third party attempts to trust a human that has opted out of group trust.
    error OptedOut();

    // =================================================
    //                    EVENTS
    // =================================================

    /**
     * @notice Emitted after the score group has completed constructor initialization.
     * @param metadataManager Address allowed to update group and treasury metadata digests.
     * @param merkleTreeManager Address whose Merkle tree registry namespace is used for score proof verification.
     * @param mintRouter Address of the deployed score group mint router.
     * @param treasury Address of the deployed score treasury.
     * @param stableERC20 Address of the stable ERC20 wrapper for this group token.
     * @param demurrageERC20 Address of the demurrage ERC20 wrapper for this group token.
     */
    event ScoreGroupInitialized(
        address indexed metadataManager,
        address indexed merkleTreeManager,
        address indexed mintRouter,
        address treasury,
        address stableERC20,
        address demurrageERC20
    );

    /**
     * @notice Emitted when a human's opt-out status changes.
     * @param member Human avatar whose opt-out flag changed.
     * @param optedOut True when the member opted out; false when the member opted back in.
     */
    event OptOutStatusChanged(address indexed member, bool optedOut);

    // =================================================
    //                     CONSTANTS
    // =================================================

    /// @notice Circles v2 Hub.
    IHub public constant HUB = IHub(address(0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8));

    /// @notice Circles v2 LiftERC20 contract.
    ILiftERC20 public constant LIFT_ERC20 = ILiftERC20(address(0x5F99a795dD2743C36D63511f0D4bc667e6d3cDB5));

    /// @notice Circles v2 Name Registry contract.
    INameRegistry public constant NAME_REGISTRY = INameRegistry(address(0xA27566fD89162cC3D40Cb59c87AAaA49B85F3474));

    /// @notice Address of the score mint policy used when registering this group.
    address public constant SCORE_MINT_POLICY = address(0x450D68272e43c4Cab7cbC7faA37893A50FAE9569);

    /// @notice The group's treasury contract, deployed during initialization.
    /// @dev Immutable once set in the constructor.
    ScoreTreasury public immutable SCORE_TREASURY;

    /// @notice Router used as the migration/path mint router for this score group.
    /// @dev Deployed during construction and passed to the mint policy initialization.
    ScoreGroupMintRouter public immutable MINT_ROUTER;

    /// @notice Stable ERC20 wrapper address for this group token.
    /// @dev Created or fetched through {LIFT_ERC20} during construction using wrapper type `1`.
    address public immutable STABLE_ERC20;

    /// @notice Demurrage ERC20 wrapper address for this group token.
    /// @dev Created or fetched through {LIFT_ERC20} during construction using wrapper type `0`.
    address public immutable DEMURRAGE_ERC20;

    /// @notice Address authorized to update the group's metadata digest.
    /// @dev Also indirectly updates metadata on both score sub-treasuries through {SCORE_TREASURY}.
    address public immutable METADATA_MANAGER;

    /// @notice Merkle tree manager namespace used by this group for score proof verification.
    /// @dev Passed to the score mint policy during construction and stored immutably for external discovery.
    address public immutable MERKLE_TREE_MANAGER;

    // =================================================
    //                    STATE
    // =================================================

    /// @notice Tracks whether a human has opted out from being trusted by third parties on behalf of the group.
    /// @dev If true, only the human itself may call {trust} for its own avatar, which clears the opt-out flag.
    mapping(address => bool) public optOuts;

    // =================================================
    //                  CONSTRUCTOR
    // =================================================

    /**
     * @notice Deploys and registers a score-based Circles group.
     * @dev
     * Reverts with {InvalidCallingParameters} if any of `_metadataManager`, `_mintRouterAdmin`, or
     * `_merkleTreeManager` is the zero address.
     *
     * The constructor registers this contract as a custom group in the Hub, using {SCORE_MINT_POLICY} as the
     * mint policy and the newly deployed {SCORE_TREASURY} as the treasury. It then initializes the mint policy
     * for this group with `_merkleTreeManager` as the trusted Merkle tree registry namespace and the deployed
     * mint router.
     *
     * Short-name registration is best-effort: failure of `NAME_REGISTRY.registerShortName()` is intentionally
     * ignored. ERC20 wrapper creation through {LIFT_ERC20} is not best-effort and will revert if either wrapper
     * cannot be ensured.
     *
     * @param _metadataManager Address authorized to update metadata for the group and treasury hierarchy.
     * @param _mintRouterAdmin Admin address for the deployed {ScoreGroupMintRouter}.
     * @param _merkleTreeManager Address whose Merkle tree registry namespace is used for this group's score proof verification.
     * @param _name Human-readable group name used for Hub registration and related router/treasury names.
     * @param _symbol Group token symbol used for Hub registration.
     * @param _metadataDigest Initial metadata digest registered for the group and treasury hierarchy.
     */
    constructor(
        address _metadataManager,
        address _mintRouterAdmin,
        address _merkleTreeManager,
        string memory _name,
        string memory _symbol,
        bytes32 _metadataDigest
    ) {
        if (_metadataManager == address(0) || _mintRouterAdmin == address(0) || _merkleTreeManager == address(0)) {
            revert InvalidCallingParameters();
        }

        METADATA_MANAGER = _metadataManager;

        MERKLE_TREE_MANAGER = _merkleTreeManager;

        MINT_ROUTER = new ScoreGroupMintRouter(_mintRouterAdmin, address(this), _name);

        // Deploy the treasury for this group.
        SCORE_TREASURY = new ScoreTreasury(
            address(HUB), address(this), SCORE_MINT_POLICY, address(MINT_ROUTER), _name, _metadataDigest
        );

        // Register the group in the Hub with the base mint policy and the newly deployed treasury.
        HUB.registerCustomGroup(SCORE_MINT_POLICY, address(SCORE_TREASURY), _name, _symbol, _metadataDigest);

        IOffchainScoreBasedMintPolicy(SCORE_MINT_POLICY).initializeGroup(_merkleTreeManager, address(MINT_ROUTER));

        // Registers a short name for this group in the Name Registry without a nonce, limited by 250_000 gas.
        try NAME_REGISTRY.registerShortName{gas: 250_000}() {} catch {}

        // Deploy ERC20s for the group via the LIFT_ERC20 contract.
        DEMURRAGE_ERC20 = LIFT_ERC20.ensureERC20(address(this), uint8(0));
        STABLE_ERC20 = LIFT_ERC20.ensureERC20(address(this), uint8(1));

        emit ScoreGroupInitialized(
            _metadataManager,
            _merkleTreeManager,
            address(MINT_ROUTER),
            address(SCORE_TREASURY),
            STABLE_ERC20,
            DEMURRAGE_ERC20
        );
    }

    // =================================================
    //               EXTERNAL FUNCTIONS
    // =================================================

    /**
     * @notice Trusts a human avatar as group collateral/member in the Hub.
     * @dev
     * Reverts with {OnlyHuman} if `_trustReceiver` is not a Hub human or does not satisfy the additional
     * avatar check performed by {_onlyHuman}.
     *
     * If `_trustReceiver` previously opted out and the caller is not `_trustReceiver`, reverts with {OptedOut}.
     * If `_trustReceiver` is the caller, the call clears any existing opt-out flag and emits
     * {OptOutStatusChanged} with `false` before setting Hub trust.
     *
     * The Hub trust expiry is set to `type(uint96).max`.
     *
     * @param _trustReceiver Human avatar to trust from this group.
     */
    function trust(address _trustReceiver) public {
        _onlyHuman(_trustReceiver);
        _optOutCheck(_trustReceiver);
        _trust(_trustReceiver, type(uint96).max);
    }

    /**
     * @notice Trusts multiple human avatars as group collateral/members in the Hub.
     * @dev
     * Calls {trust} for each entry in `_members`. Processing is sequential and the whole transaction reverts if
     * any individual trust operation reverts.
     *
     * Duplicate entries are not filtered and will result in repeated Hub trust calls.
     *
     * @param _members Human avatars to trust from this group.
     */
    function trustBatch(address[] memory _members) external {
        for (uint256 i; i < _members.length;) {
            trust(_members[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Opts the caller out of third-party group trust management.
     * @dev
     * Reverts with {OnlyHuman} if the caller is not a Hub human or does not satisfy the additional avatar check
     * performed by {_onlyHuman}.
     *
     * If the group currently trusts the caller, the group trust is revoked by setting the Hub trust expiry to `0`.
     * The caller's opt-out flag is then set to true and {OptOutStatusChanged} is emitted.
     *
     * An opted-out human may later call {trust} with its own address to clear the opt-out flag and restore trust.
     */
    function optOut() external {
        _onlyHuman(msg.sender);
        if (HUB.isTrusted(address(this), msg.sender)) _trust(msg.sender, 0);
        optOuts[msg.sender] = true;
        emit OptOutStatusChanged(msg.sender, true);
    }

    /**
     * @notice Updates the metadata digest for this group and its treasury hierarchy.
     * @dev
     * Reverts with {OnlyMetadataManager} unless called by {METADATA_MANAGER}.
     *
     * Updates this group's metadata through the Name Registry and delegates treasury/sub-treasury metadata updates
     * to {SCORE_TREASURY}.
     *
     * @param _metadataDigest New off-chain metadata digest to register.
     */
    function updateMetadataDigest(bytes32 _metadataDigest) external {
        if (msg.sender != METADATA_MANAGER) revert OnlyMetadataManager();
        NAME_REGISTRY.updateMetadataDigest(_metadataDigest);
        SCORE_TREASURY.updateMetadataDigest(address(NAME_REGISTRY), _metadataDigest);
    }

    // =================================================
    //               INTERNAL FUNCTIONS
    // =================================================

    /**
     * @notice Sets this group's Hub trust expiry for a receiver.
     * @dev Executes `HUB.trust(_trustReceiver, _expiry)` from this contract's context.
     * @param _trustReceiver Avatar to trust or untrust.
     * @param _expiry Hub trust expiry value; `0` revokes trust and `type(uint96).max` grants effectively maximum trust.
     */
    function _trust(address _trustReceiver, uint96 _expiry) internal {
        HUB.trust(_trustReceiver, _expiry);
    }

    /**
     * @notice Validates that an avatar is a Hub human and supports the expected Circles v2 avatar interface.
     * @dev
     * First checks `HUB.isHuman(avatar)` and reverts with {OnlyHuman} if false.
     *
     * The inline assembly then performs a low-level staticcall against `avatar` and validates the returned data
     * hash. If the staticcall fails or the response hash does not match the expected value, the function reverts
     * with the OnlyHuman error.
     *
     * @param avatar Address to validate as a human avatar.
     */
    function _onlyHuman(address avatar) internal view {
        if (!HUB.isHuman(avatar)) revert OnlyHuman();
        assembly {
            let pointer := mload(0x40)
            mstore(0x40, add(pointer, 0x44))
            mstore(pointer, 0x5624b25b553c9d7e83c58cdf3a427b0c81460372fe0d5da8900473788d506425)
            mstore(add(pointer, 0x20), 0xc7ffdc5c00000000000000000000000000000000000000000000000000000000)
            mstore(add(pointer, 0x40), 0x0000000100000000000000000000000000000000000000000000000000000000)
            if or(
                iszero(
                    eq(
                        keccak256(add(pointer, 0x44), 0x60),
                        0xbc542b7979ff2bed60ccd2c45b7437d0c0580d139eefafaffc4eec6c7686af06
                    )
                ),
                iszero(staticcall(gas(), avatar, pointer, 0x44, add(pointer, 0x44), 0x60))
            ) {
                mstore(0, 0x9aa42e7200000000000000000000000000000000000000000000000000000000)
                revert(0, 0x04)
            }
        }
    }

    /**
     * @notice Enforces opt-out rules before trusting a receiver.
     * @dev
     * If `_trustReceiver` has opted out and the caller is not `_trustReceiver`, reverts with {OptedOut}.
     *
     * If `_trustReceiver` is the caller, this function clears the receiver's opt-out flag and emits
     * {OptOutStatusChanged} with `false`. This allows a human that previously opted out to opt back in by calling
     * {trust} for its own address.
     *
     * @param _trustReceiver Avatar that is about to be trusted.
     */
    function _optOutCheck(address _trustReceiver) internal {
        if (optOuts[_trustReceiver] && _trustReceiver != msg.sender) revert OptedOut();
        if (_trustReceiver == msg.sender) {
            optOuts[_trustReceiver] = false;
            emit OptOutStatusChanged(msg.sender, false);
        }
    }
}
