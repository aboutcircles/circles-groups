// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {IHub} from "src/score-group/interfaces/IHub.sol";

/**
 * @title ScoreGroupMintRouter
 * @notice Router organization used to make selected personal CRCs routeable into a ScoreGroup mint path.
 * @dev
 * This contract is a Hub organization registered during construction. Its purpose is to sit on the
 * Circles Hub trust graph as an intermediate routing avatar between personal CRC collateral and the
 * configured ScoreGroup.
 *
 * The contract has two distinct responsibilities:
 *
 * 1. Admin-curated trust gate:
 *    The immutable `ADMIN` can call {enableCRCForRouting} and {disableCRCForRouting} to decide which
 *    personal CRC avatars this router trusts through `HUB.trust`. Only CRCs trusted by this router can
 *    be used on a Hub trust path that terminates at the router and then continues to the ScoreGroup.
 *
 * 2. Permissionless operator approval:
 *    Anyone can call {setApprovalForCRC} to make the provided addresses ERC1155 operators for this
 *    router on the Hub. This allows those operators to drive Hub flow operations involving the router.
 *    This approval does not itself make arbitrary collateral mintable; the collateral still has to be
 *    trusted by this router and by the configured ScoreGroup according to Hub flow validation.
 *
 * The configured ScoreGroup address is immutable and is additionally used by {enableCRCForRouting} to
 * require that every enabled personal CRC is already trusted by the ScoreGroup.
 *
 * Security notes:
 * - The admin controls the router's trusted CRC set.
 * - Operator approval is intentionally permissionless and broad for the addresses supplied by callers.
 * - This contract does not custody CRCs outside the execution of Hub flow operations.
 * - There is no admin rotation, group rotation, or approval-revocation function in this contract.
 */
contract ScoreGroupMintRouter {
    // =================================================
    //                      ERRORS
    // =================================================

    /// @notice Reverts when a function restricted to the immutable admin is called by another address.
    error OnlyAdmin();

    /// @notice Reverts when an address expected to be a registered Hub human is not recognized as one.
    error OnlyHuman();

    /// @notice Reverts when a CRC avatar is not trusted by the configured ScoreGroup.
    error OnlyGroupMember();

    // =================================================
    //             CONSTANTS & IMMUTABLES
    // =================================================

    /// @notice Circles Hub v2 used for organization registration, trust checks, trust updates, and approvals.
    /// @dev The address is fixed at compile time and all Hub interactions are made through this instance.
    IHub internal constant HUB = IHub(address(0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8));

    /// @notice ScoreGroup avatar that receives routed collateral through the Hub trust path.
    /// @dev Used as the reference group for membership/collateral trust checks in {enableCRCForRouting}.
    address public immutable GROUP;

    /// @notice Address allowed to curate which personal CRCs are trusted by this router.
    /// @dev Set once in the constructor and cannot be changed by this contract.
    address public immutable ADMIN;

    // =================================================
    //                    MODIFIERS
    // =================================================

    /**
     * @notice Restricts execution to the immutable admin address.
     * @dev Reverts with {OnlyAdmin} if `msg.sender` is not `ADMIN`.
     */
    modifier onlyAdmin() {
        if (msg.sender != ADMIN) revert OnlyAdmin();
        _;
    }

    // =================================================
    //                   CONSTRUCTOR
    // =================================================

    /**
     * @notice Deploys the router, stores its immutable configuration, and registers it as a Hub organization.
     * @dev
     * The router name registered in the Hub is built by appending `"-score-mint-router"` to `_groupName`.
     * The registration uses `bytes32(0)` as the metadata digest argument.
     *
     * @param admin Address that will be allowed to enable and disable CRC routing trust.
     * @param _group ScoreGroup avatar address used for group trust checks and as the intended routing target.
     * @param _groupName Human-readable group name prefix used to derive the Hub organization name.
     */
    constructor(address admin, address _group, string memory _groupName) {
        ADMIN = admin;
        GROUP = _group;
        string memory routerName = string.concat(_groupName, "-score-mint-router");
        HUB.registerOrganization(routerName, bytes32(0));
    }

    // =================================================
    //                ADMIN-CURATED MINT GATE
    // =================================================

    /**
     * @notice Enables one or more personal CRC avatars as routeable collateral through this router.
     * @dev
     * For each address in `crcArray`, the function verifies that the address is a registered Hub human and
     * that the configured ScoreGroup currently trusts that address. If both checks pass, the router calls
     * `HUB.trust(crc, type(uint96).max)`, making the router trust the CRC at the maximum trust limit.
     *
     * This function is the admin-controlled gate for which personal CRCs can flow through this router in a
     * Hub trust path toward the ScoreGroup. It does not grant operator approvals; approvals are handled by
     * {setApprovalForCRC}.
     *
     * Requirements:
     * - Caller must be `ADMIN`; otherwise reverts with {OnlyAdmin} through {onlyAdmin}.
     * - Every `crcArray[i]` must satisfy `HUB.isHuman(crcArray[i])`; otherwise reverts with {OnlyHuman}.
     * - Every `crcArray[i]` must be trusted by `GROUP`; otherwise reverts with {OnlyGroupMember}.
     *
     * Effects:
     * - Sets this router's Hub trust limit for each CRC to `type(uint96).max`.
     * - Processes entries sequentially and reverts the entire transaction if any entry fails.
     *
     * @param crcArray Personal CRC avatar addresses to trust for routing through this router.
     */
    function enableCRCForRouting(address[] memory crcArray) external onlyAdmin {
        for (uint256 i; i < crcArray.length;) {
            address crc = crcArray[i];
            if (!HUB.isHuman(crc)) revert OnlyHuman();
            if (!HUB.isTrusted(GROUP, crc)) revert OnlyGroupMember();
            HUB.trust(crc, type(uint96).max);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Disables routing trust for one or more CRC avatars.
     * @dev
     * For each address in `crcArray`, the router calls `HUB.trust(crc, uint96(0))`, setting this router's
     * trust limit for the CRC to zero. This makes the CRC ineligible for routing through this router under
     * Hub flow rules, subject to the Hub's trust semantics.
     *
     * Requirements:
     * - Caller must be `ADMIN`; otherwise reverts with {OnlyAdmin} through {onlyAdmin}.
     *
     * Effects:
     * - Sets this router's Hub trust limit for each listed CRC to zero.
     *
     * @param crcArray CRC avatar addresses whose routing trust should be revoked on this router.
     */
    function disableCRCForRouting(address[] memory crcArray) external onlyAdmin {
        for (uint256 i; i < crcArray.length;) {
            address crc = crcArray[i];
            // untrust
            if (HUB.isTrusted(address(this), crc)) HUB.trust(crc, uint96(0));

            unchecked {
                ++i;
            }
        }
    }

    // =================================================
    //              PERMISSIONLESS ROUTING
    // =================================================

    /**
     * @notice Grants Hub ERC1155 operator approval from this router to valid supplied addresses.
     * @dev
     * This function is intentionally permissionless. Any caller may cause this router to approve
     * each supplied address that is recognized by the Hub as either a human or an organization.
     *
     * For every valid entry, the router calls `HUB.setApprovalForAll(crc, true)` from the router
     * context, making that address an ERC1155 operator for this router in the Hub.
     *
     * The approval is useful for driving `HUB.operateFlowMatrix` calls that include a
     * router-to-ScoreGroup hop. Approval alone does not enable minting with arbitrary collateral.
     * Successful routing still depends on Hub flow validation, including this router's trust in the
     * collateral CRC and the configured ScoreGroup's trust in that collateral.
     *
     * Entries that are neither Hub humans nor Hub organizations are ignored and do not cause a revert.
     * This contract does not provide a matching public or admin function to revoke these approvals.
     *
     * Effects:
     * - For each supplied address that is a Hub human or organization, sets
     *   `isApprovedForAll(address(this), crcArray[i])` to true in the Hub according to the Hub's
     *   ERC1155 approval semantics.
     * - Skips entries that are neither Hub humans nor Hub organizations.
     * - Processes entries sequentially and reverts the entire transaction if a Hub approval call reverts.
     *
     * @param crcArray Addresses to conditionally approve as operators for this router on the Hub.
     */
    function setApprovalForCRC(address[] memory crcArray) external {
        for (uint256 i; i < crcArray.length;) {
            address crc = crcArray[i];
            if (HUB.isHuman(crc) || HUB.isOrganization(crc)) HUB.setApprovalForAll(crc, true);
            unchecked {
                ++i;
            }
        }
    }
}
