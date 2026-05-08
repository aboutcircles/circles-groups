// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {IHub} from "src/base-group/interfaces/IHub.sol";
import {IBaseGroupFactory} from "src/base-group/interfaces/IBaseGroupFactory.sol";

/**
 * @title BaseGroupMintRouter
 * @notice Technical helper that enables CRCs for routing for a BaseGroup minting along a path.
 * @dev
 *  - Intended to be minimally visible: no duplicate events; Hub emits authoritative events.
 *  - Exposes exactly ONE public action for normal operation: {enableCRCForRouting}.
 *  - Admin actions exist ONLY to roll the entire state back when migrating away from this router.
 *  - Contract should not hold CRC; there are no callbacks.
 */
contract BaseGroupMintRouter {
    // =================================================
    //                      ERRORS
    // =================================================

    /// @notice Operation is blocked while the router is frozen.
    error Frozen();
    /// @notice Caller is not the Admin.
    error OnlyAdmin();
    /// @notice Address is not recognized as a human by the Hub.
    error OnlyHuman();
    /// @notice Provided baseGroup was not deployed by the Base Group Factory.
    error OnlyBaseGroup();

    // =================================================
    //             CONSTANTS & IMMUTABLES
    // =================================================

    /// @notice Circles Hub v2.
    IHub internal constant HUB = IHub(address(0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8));
    /// @notice Base Group Factory.
    IBaseGroupFactory internal constant BASE_GROUP_FACTORY =
        IBaseGroupFactory(address(0xD0B5Bd9962197BEaC4cbA24244ec3587f19Bd06d));
    /// @notice Privileged address allowed to run rollback-only admin actions.
    address internal immutable ADMIN;

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
        HUB.registerOrganization("BaseGroupMintRouter", bytes32(0));
    }

    // =================================================
    //                PUBLIC FUNCTION (ONLY)
    // =================================================

    /**
     * @notice Enable CRCs to be routed into a BaseGroup through this Router.
     * @dev
     *  The Router is an organization and therefore a node in the Hub’s trust graph.
     *  Minting a BaseGroup CRC happens along a trust path: Router  →  BaseGroup
     *
     *  To support this flow:
     *   - The Router approves human addresses as operators (`setApprovalForAll`) so they can call `operateFlowMatrix`.
     *   - The Router must also trust CRCs that are trusted by the BaseGroup, so those CRCs are accepted as valid
     *     collateral for group minting when routed through the Router.
     *
     *  Requirements:
     *   - Reverts {Frozen} if the Router is frozen.
     *   - Reverts {OnlyBaseGroup} if `baseGroup` was not deployed by the factory.
     *   - For each CRC in `crcArray`:
     *       * Reverts {OnlyHuman} if `HUB.isHuman(crc)` is false (only human CRCs are valid).
     *       * If the BaseGroup already trusts the CRC, the Router also trusts it via `HUB.trust(crc, type(uint96).max)`.
     *       * Grants operator approval via `HUB.setApprovalForAll(crc, true)`.
     *
     * @param baseGroup The BaseGroup instance into which CRC routing is enabled.
     * @param crcArray  List of human CRC addresses to approve and, if trusted by the BaseGroup, also be trusted by the Router.
     */
    function enableCRCForRouting(address baseGroup, address[] memory crcArray) external {
        if (frozen) revert Frozen();
        if (!BASE_GROUP_FACTORY.deployedByFactory(baseGroup)) revert OnlyBaseGroup();

        for (uint256 i; i < crcArray.length;) {
            address crc = crcArray[i];
            if (!HUB.isHuman(crc)) revert OnlyHuman();
            if (HUB.isTrusted(baseGroup, crc)) HUB.trust(crc, type(uint96).max);
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
