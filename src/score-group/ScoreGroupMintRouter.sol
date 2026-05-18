// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {IHub} from "src/base-group/interfaces/IHub.sol";

/**
 * @title ScoreGroupMintRouter
 * @notice Technical helper that routes personal CRCs into a ScoreGroup mint along a Hub trust path.
 * @dev
 *  Design split between admin and public:
 *   - Admin-only: {enableCRCForRouting} establishes which personal CRCs the Router itself trusts.
 *     Trust on the Router is what makes a CRC eligible to terminate at the Router and from there
 *     be forwarded into the ScoreGroup as collateral. This is the only privileged hook into the
 *     mint path: gate the set of CRCs that can ever produce a group mint.
 *   - Public: {setApprovalForCRC} lets anyone authorize themselves (or any address they pass in)
 *     as an ERC1155 operator on the Router so they can call `Hub.operateFlowMatrix` and push
 *     CRCs through the Router → ScoreGroup edge. Routing is permissionless; the only constraint
 *     is that the collateral CRC must be (a) trusted by the Router (admin-curated) and
 *     (b) trusted by the ScoreGroup as valid collateral.
 *
 *  The Router is registered as a Hub organization at construction so it can sit on the trust graph.
 */
contract ScoreGroupMintRouter {
    // =================================================
    //                      ERRORS
    // =================================================

    /// @notice Caller is not the Admin.
    error OnlyAdmin();
    /// @notice Address is not recognized as a human by the Hub.
    error OnlyHuman();

    error OnlyGroupMember();

    error ArrayLengthMismatch();
    // =================================================
    //             CONSTANTS & IMMUTABLES
    // =================================================

    /// @notice Circles Hub v2.
    IHub internal constant HUB = IHub(address(0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8));

    address internal immutable GROUP;

    /// @notice Privileged address allowed to curate the trusted CRC set ({trustCRCForMinting})
    /// and to perform rollback actions during migrations.
    address internal immutable ADMIN;

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
     * @notice Admin-curated set of personal CRCs that the Router will accept on its
     *         Hub trust edges, making them eligible to be routed into a ScoreGroup mint.
     * @dev
     *  This is the single privileged hook into the mint path. Only CRCs added here can
     *  ever flow `... → Router → ScoreGroup` and result in a group mint, because the
     *  ScoreGroup edge requires the Router to trust the inbound CRC under the Hub's
     *  `isPermittedFlow` rules.
     *
     *  For each CRC in `crcArray` the Router calls `HUB.trust(crc, type(uint96).max)`
     *  so the Hub records the Router as a truster of that CRC.
     *
     *  Requirements:
     *   - Admin-only.
     *   - Reverts {Frozen} if the Router is frozen.
     *   - Reverts {OnlyHuman} if any entry is not a registered human in the Hub.
     *
     * @param crcArray  Personal CRC avatar addresses to be trusted by the Router.
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
     * @notice Roll back the admin-curated trust for a list of CRCs.
     * @dev
     *  Counterpart to {trustCRCForMinting}: removes the Router's trust in each listed CRC
     *  so it is no longer eligible to flow through the Router into the ScoreGroup mint
     *  path. Operator approvals granted via {setApprovalForCRC} are not touched here —
     *  use {revokeApprovalForCRC} for that.
     *
     *
     * @param crcArray List of CRC addresses whose trust on the Router is revoked.
     */
    function disableCRCForRouting(address[] memory crcArray) external onlyAdmin {
        for (uint256 i; i < crcArray.length;) {
            address crc = crcArray[i];
            // untrust
            HUB.trust(crc, uint96(0));

            unchecked {
                ++i;
            }
        }
    }

    // =================================================
    //              PERMISSIONLESS ROUTING
    // =================================================

    /**
     * @notice Authorize one or more addresses as ERC1155 operators on the Router so
     *         they can drive `Hub.operateFlowMatrix` calls that move CRCs out of the
     *         Router toward the ScoreGroup.
     * @dev
     *  Permissionless on purpose: anyone can call this and any address they pass in
     *  becomes an approved operator of the Router on the Hub. The Router never holds
     *  CRCs at rest — within a single `operateFlowMatrix` call CRCs flow
     *  `... → Router → ScoreGroup`, and the operator just needs ERC1155 approval to
     *  push the Router → Group hop.
     *
     *  Authorization here does not, on its own, allow a mint to happen. A mint also
     *  requires that:
     *   - the collateral CRC is trusted by the Router (via the admin-only
     *     {trustCRCForMinting}); and
     *   - the collateral CRC is trusted by the ScoreGroup as valid collateral.
     *
     *  Requirements:
     *   - Reverts {Frozen} if the Router is frozen.
     *
     * @param crcArray  Addresses to approve as Router operators on the Hub
     *                  (typically the addresses that will call `operateFlowMatrix`).
     */
    function setApprovalForCRC(address[] memory crcArray) external {
        for (uint256 i; i < crcArray.length;) {
            address crc = crcArray[i];

            HUB.setApprovalForAll(crc, true);
            unchecked {
                ++i;
            }
        }
    }
}
