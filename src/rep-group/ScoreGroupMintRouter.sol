// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {IHub} from "src/base-group/interfaces/IHub.sol";
import {IBaseGroupFactory} from "src/base-group/interfaces/IBaseGroupFactory.sol";

// Dev: migrate gnosis group members to new group
// 1. trust group CRC only(?) -> Not needed, because new group don't trust gnosis group CRC
// 2. trust personalCRC only (?)
// Migration workflow: gnosis group member -> redeem collateral from group -> get colalteral -> route through Router -> mint new group CRC
//
// 1. Using the original Router logic: personalCRC -> Router -> group
// 2. With new Router: router -> redeem gnosis CRC to collateral -> MintRouter -> new group mint
/**
 * @title BaseGroupMintRouter
 * @notice Technical helper that enables CRCs for routing for a BaseGroup minting along a path.
 * @dev
 *  - Intended to be minimally visible: no duplicate events; Hub emits authoritative events.
 *  - Exposes exactly ONE public action for normal operation: {enableCRCForRouting}.
 *  - Admin actions exist ONLY to roll the entire state back when migrating away from this router.
 *  - Contract should not hold CRC; there are no callbacks.
 */
contract ScoreGroupMintRouter {
    // =================================================
    //                      ERRORS
    // =================================================

    /// @notice Operation is blocked while the router is frozen.
    error Frozen();
    /// @notice Caller is not the Admin.
    error OnlyAdmin();
    /// @notice Address is not recognized as a human by the Hub.
    error OnlyHuman();

    error NotGroupMember();

    // =================================================
    //             CONSTANTS & IMMUTABLES
    // =================================================

    /// @notice Circles Hub v2.
    IHub internal constant HUB = IHub(address(0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8));

    /// @notice Privileged address allowed to run rollback-only admin actions.
    address internal immutable ADMIN;

    address public GNOSIS_GROUP = 0xC19BC204eb1c1D5B3FE500E5E5dfaBaB625F286c;

    // =================================================
    //                      STORAGE
    // =================================================

    /// @notice Global switch that blocks the public enable function when true.
    bool frozen;

    // =================================================
    //                    MODIFIERS
    // =================================================

    /// @notice Ensures the function is only called by the Admin.
    /// @dev Reverts with {OnlyAdmin} if `msg.sender` is not the Admin.
    modifier onlyAdmin() {
        if (msg.sender != ADMIN) revert OnlyAdmin();
        _;
    }

    // =================================================
    //                   CONSTRUCTOR
    // =================================================

    /**
     * @notice Deploys the router and registers it in the Hub as an organization.
     * @param admin The admin address that can perform rollback-only actions.
     */
    constructor(address admin) {
        ADMIN = admin;
        HUB.registerOrganization("ScoreGroupMintRouter", bytes32(0));
    }

    // =================================================
    //                PUBLIC FUNCTION (ONLY)
    // =================================================

    /**
     * @notice Enable CRCs to be routed into a ScoreGroup through this Router.
     * @dev
     *  The Router is an organization and therefore a node in the Hub’s trust graph.
     *  Minting a ScoreGroup CRC happens along a trust path: Router  →  ScoreGroup
     *
     *  To support this flow:
     *   - The Router approves human addresses as operators (`setApprovalForAll`) so they can call `operateFlowMatrix`.
     *   - The Router must also trust CRCs that are trusted by the GnosisGroup, so those CRCs are accepted as valid
     *     collateral for group minting when routed through the Router.
     *
     *  Requirements:
     *   - Reverts {Frozen} if the Router is frozen.
     *   - For each CRC in `crcArray`:
     *       * Reverts {OnlyHuman} if `HUB.isHuman(crc)` is false (only human CRCs are valid).
     *       * If the GnosisGroup already trusts the CRC, the Router also trusts it via `HUB.trust(crc, type(uint96).max)`.
     *       * Grants operator approval via `HUB.setApprovalForAll(crc, true)`.
     *
     * @param crcArray  List of human CRC addresses to approve and, if trusted by the GnosisGroup, also be trusted by the Router.
     */
    function enableCRCForRouting(address[] memory crcArray) external onlyAdmin {
        if (frozen) revert Frozen();

        for (uint256 i; i < crcArray.length;) {
            address crc = crcArray[i];
            if (!HUB.isHuman(crc)) revert OnlyHuman();
            if (HUB.isTrusted(GNOSIS_GROUP, crc)) HUB.trust(crc, type(uint96).max);

            HUB.setApprovalForAll(crc, true);
            unchecked {
                ++i;
            }
        }
    }

    // =================================================
    //        ADMIN ROLLBACK FUNCTIONS (MIGRATIONS)
    // =================================================

    /**
     * @notice Freeze or unfreeze the Router.
     * @dev
     *  Freezing blocks new Router → BaseGroup edges from being created via {enableCRCForRouting}.
     *  This is used during migrations to ensure no new paths are established while state is being rolled back.
     *
     *  Requirements:
     *   - Admin-only.
     *
     * @param _freeze Set to true to block {enableCRCForRouting}, false to allow it again.
     */
    function freeze(bool _freeze) external onlyAdmin {
        frozen = _freeze;
    }

    /**
     * @notice Roll back Router state for a list of CRCs by removing trust and revoking approvals.
     * @dev
     *  The Router is a node in the Hub’s trust graph, forming a path: Router → BaseGroup.
     *
     *  This function dismantles that path during migration to a new Router:
     *   - Removes Router’s trust in the CRC (if set).
     *   - Revokes operator approval (`setApprovalForAll`) so the CRC can no longer call `operateFlowMatrix` through this Router.
     *
     *  Requirements:
     *   - Admin-only. Intended solely for rollback / migration, not day-to-day use.
     *   - For each CRC in `crcArray`:
     *       * If the Router currently trusts the CRC (`HUB.isTrusted(address(this), crc)`), it resets trust to 0.
     *       * Calls `HUB.setApprovalForAll(crc, false)` to revoke operator status.
     *
     * @param crcArray List of CRC addresses whose routing and operator rights are revoked from this Router.
     */
    function disableCRCForRouting(address[] memory crcArray) external onlyAdmin {
        for (uint256 i; i < crcArray.length;) {
            address crc = crcArray[i];
            // untrust
            if (HUB.isTrusted(address(this), crc)) HUB.trust(crc, uint96(0));
            // revoke approval
            HUB.setApprovalForAll(crc, false);
            unchecked {
                ++i;
            }
        }
    }
}
