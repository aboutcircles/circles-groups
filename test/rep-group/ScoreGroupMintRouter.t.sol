// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import "forge-std/StdCheats.sol";
import {Test} from "forge-std/Test.sol";
import "circles-contracts-v2/hub/TypeDefinitions.sol";
import {IERC1155Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {BaseGroup} from "src/base-group/BaseGroup.sol";
import {BaseGroupFactory} from "src/base-group/BaseGroupFactory.sol";
import {ScoreGroupMintRouter} from "src/rep-group/ScoreGroupMintRouter.sol";
import {IHub} from "./interfaces/IHub.sol";

/**
 * @title ScoreGroupMintRouterTest
 * @notice Test suite for the ScoreGroupMintRouter contract.
 * @dev This contract contains a suite of tests to verify the functionality of the ScoreGroupMintRouter,
 * ensuring that group minting via flow matrix operations, access control, and configuration settings
 * work as expected.
 */
contract ScoreGroupMintRouterTest is Test {
    event GroupMint(
        address indexed sender, address indexed receiver, address indexed group, uint256[] collateral, uint256[] amounts
    );

    error CirclesErrorAddressUintArgs(address, uint256, uint8);

    // BaseGroupFactory address is hardcoded inside the contracts under test, hence we rely on the
    // forked deployment at this address to create the base group used as the ScoreGroup.
    BaseGroupFactory constant baseGroupFactory = BaseGroupFactory(0xD0B5Bd9962197BEaC4cbA24244ec3587f19Bd06d);

    address group;
    address owner;
    address routerAdmin;

    ScoreGroupMintRouter router;

    address[] gnosisMembers = [
        0x42cEDde51198D1773590311E2A340DC06B24cB37,
        0xF7bD3d83df90B4682725ADf668791D4D1499207f,
        0x14aaB8D72B68c79cbb7873D003585a7C3EF98633,
        0xfDEA8140093878BfcA93aAA35d3D3087F4Ab136d
    ];

    address HUB = 0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8;

    /**
     * @notice Sets up the test environment.
     * @dev Creates a fresh BaseGroup via the deployed factory and deploys a fresh
     *      ScoreGroupMintRouter with `routerAdmin` as the privileged address.
     */
    function setUp() public {
        owner = makeAddr("owner");
        routerAdmin = makeAddr("routerAdmin");
        address service = makeAddr("service");
        address feeCollection = makeAddr("feeCollection");
        address[] memory initialConditions;
        string memory groupName = "ScoreGroup";
        string memory groupSymbol = "SG";
        bytes32 metadataDigest = keccak256(abi.encodePacked("metadata"));

        (group,,) = baseGroupFactory.createBaseGroup(
            owner, service, feeCollection, initialConditions, groupName, groupSymbol, metadataDigest
        );

        router = new ScoreGroupMintRouter(routerAdmin);
    }

    /**
     * @notice Verifies that {ScoreGroupMintRouter.enableCRCForRouting} records the Router as a
     *         truster of each personal CRC on the Hub.
     * @dev Asserts that all gnosis members are untrusted by the Router before the call and
     *      trusted afterward, confirming the admin-curated mint gate is correctly persisted.
     */
    function testEnableCRC() public {
        vm.assertFalse(IHub(HUB).isTrusted(address(router), gnosisMembers[0]));
        vm.assertFalse(IHub(HUB).isTrusted(address(router), gnosisMembers[1]));
        vm.assertFalse(IHub(HUB).isTrusted(address(router), gnosisMembers[2]));
        vm.assertFalse(IHub(HUB).isTrusted(address(router), gnosisMembers[3]));

        vm.prank(routerAdmin);
        router.enableCRCForRouting(gnosisMembers);

        vm.assertTrue(IHub(HUB).isTrusted(address(router), gnosisMembers[0]));
        vm.assertTrue(IHub(HUB).isTrusted(address(router), gnosisMembers[1]));
        vm.assertTrue(IHub(HUB).isTrusted(address(router), gnosisMembers[2]));
        vm.assertTrue(IHub(HUB).isTrusted(address(router), gnosisMembers[3]));
    }

    /**
     * @notice Verifies the three revert paths of {ScoreGroupMintRouter.enableCRCForRouting}.
     * @dev Covers:
     *  - {OnlyAdmin}: a non-admin caller cannot curate the trusted CRC set.
     *  - {OnlyHuman}: trusting a non-human (the Router itself, registered as an organization)
     *    is rejected.
     *  - {Frozen}: once the Router is frozen, even the admin cannot add new mint paths.
     */
    function testEnableCRCReverts() public {
        // ===================== Revert: OnlyAdmin =====================
        address nonAdmin = makeAddr("nonAdmin");
        vm.prank(nonAdmin);
        vm.expectRevert(ScoreGroupMintRouter.OnlyAdmin.selector);
        router.enableCRCForRouting(gnosisMembers);

        // ===================== Revert: OnlyHuman =====================
        address[] memory nonHumanArray = new address[](1);
        nonHumanArray[0] = address(router);
        vm.prank(routerAdmin);
        vm.expectRevert(ScoreGroupMintRouter.OnlyHuman.selector);
        router.enableCRCForRouting(nonHumanArray);

        // ===================== Revert: Frozen =====================
        vm.prank(routerAdmin);
        router.freeze(true);

        vm.prank(routerAdmin);
        vm.expectRevert(ScoreGroupMintRouter.Frozen.selector);
        router.enableCRCForRouting(gnosisMembers);
    }

    /**
     * @notice Verifies that {ScoreGroupMintRouter.disableCRCForRouting} cleanly rolls back trust
     *         for previously curated CRCs.
     * @dev First enables trust for all gnosis members, then disables them and asserts that
     *      `HUB.isTrusted(router, member)` is false for each. A 1s warp ensures the trust
     *      expiry (set to 0 by disable) is strictly in the past for the assertion.
     *      Note: `disableCRCForRouting` is permissionless, so no admin prank is needed.
     */
    function testDisableCRCForRouting() public {
        vm.prank(routerAdmin);
        router.enableCRCForRouting(gnosisMembers);

        vm.assertTrue(IHub(HUB).isTrusted(address(router), gnosisMembers[0]));
        vm.assertTrue(IHub(HUB).isTrusted(address(router), gnosisMembers[1]));
        vm.assertTrue(IHub(HUB).isTrusted(address(router), gnosisMembers[2]));
        vm.assertTrue(IHub(HUB).isTrusted(address(router), gnosisMembers[3]));

        router.disableCRCForRouting(gnosisMembers);

        vm.warp(block.timestamp + 1);

        vm.assertFalse(IHub(HUB).isTrusted(address(router), gnosisMembers[0]));
        vm.assertFalse(IHub(HUB).isTrusted(address(router), gnosisMembers[1]));
        vm.assertFalse(IHub(HUB).isTrusted(address(router), gnosisMembers[2]));
        vm.assertFalse(IHub(HUB).isTrusted(address(router), gnosisMembers[3]));
    }

    /**
     * @notice End-to-end happy path: an existing gnosis-group member mints group CRCs of the
     *         newly deployed group via the Router using `Hub.operateFlowMatrix`.
     * @dev Path: gnosisMembers[0] --gnosisMembers[0]CRC--> router --gnosisMembers[0]CRC--> group
     *      --groupCRC--> gnosisMembers[3]. Also exercises the missing-approval failure first:
     *      the call reverts with {ERC1155MissingApprovalForAll} until the source authorizes the
     *      Router as its operator via {setApprovalForCRC}, after which the mint succeeds and
     *      emits {GroupMint}.
     */
    function testRoutingFromGnosisGrpMemberToNewGrp() public {
        // ============================== Enable CRC For Routing ==============================
        vm.prank(routerAdmin);
        router.enableCRCForRouting(gnosisMembers);

        // ============================== Configure Group Trust ==============================
        // The new group must trust the gnosis members so their CRCs are accepted as collateral.
        vm.startPrank(owner);
        BaseGroup(group).trust(gnosisMembers[0], type(uint96).max);
        BaseGroup(group).trust(gnosisMembers[1], type(uint96).max);
        BaseGroup(group).trust(gnosisMembers[2], type(uint96).max);
        BaseGroup(group).trust(gnosisMembers[3], type(uint96).max);
        vm.stopPrank();

        // sink (gnosisMembers[3]) must trust the new group to receive its CRC
        vm.prank(gnosisMembers[3]);
        IHub(HUB).trust(group, type(uint96).max);

        uint192 crcAmount = _loadSourceBalance(gnosisMembers[0]);

        (
            address[] memory flowVertices,
            TypeDefinitions.FlowEdge[] memory flowEdges,
            TypeDefinitions.Stream[] memory streams,
            bytes memory packCoordinate,
            uint256[] memory collateral,
            uint256[] memory groupMintAmount
        ) = _buildSingleHopFlow(gnosisMembers[0], gnosisMembers[0], gnosisMembers[3], crcAmount);

        // First call: source has not approved the Router as operator -> reverts.
        vm.prank(gnosisMembers[0]);
        vm.expectRevert(
            abi.encodeWithSelector(IERC1155Errors.ERC1155MissingApprovalForAll.selector, gnosisMembers[0], router)
        );
        IHub(HUB).operateFlowMatrix(flowVertices, flowEdges, streams, packCoordinate);

        // Approve and retry.
        address[] memory ops = new address[](1);
        ops[0] = gnosisMembers[0];
        vm.prank(gnosisMembers[0]);
        router.setApprovalForCRC(ops, _repeatBool(true, 1));

        vm.prank(gnosisMembers[0]);
        vm.expectEmit();
        emit GroupMint(address(router), address(group), address(group), collateral, groupMintAmount);
        IHub(HUB).operateFlowMatrix(flowVertices, flowEdges, streams, packCoordinate);

        assertEq(IHub(HUB).balanceOf(gnosisMembers[3], uint256(uint160(address(group)))), crcAmount);
    }

    /**
     * @notice Demonstrates that an arbitrary newly-registered human (not trusted by the inviter,
     *         not a member of the source's group) can still drive a group mint through the Router,
     *         provided the group accepts the collateral CRC.
     * @dev The flow is: newHuman is registered, receives a balance of gnosisMembers[0]CRC via
     *      transfer, and then the inviter's trust on newHuman is revoked. Despite that revocation,
     *      newHuman successfully mints group CRC via the Router because the only trust constraints
     *      that matter are (a) Router trusts the collateral CRC, (b) group trusts the collateral
     *      CRC, and (c) the receiver trusts the group. The first attempt reverts with
     *      {ERC1155MissingApprovalForAll}; after `setApprovalForCRC([newHuman], [true])` the mint
     *      succeeds.
     */
    function testOperateFlowMatrixWithoutTrust() public {
        // ============================== Register New Human ==============================
        address newHuman = makeAddr("newHuman");

        // Inviter (gnosisMembers[0]) claims pending personal issuance so it has enough CRC
        // to cover the post-invitation-period INVITATION_COST (96 CRC) burn during registration.
        vm.warp(block.timestamp + 3 days);
        vm.prank(gnosisMembers[0]);
        IHub(HUB).personalMint();

        vm.prank(gnosisMembers[0]);
        IHub(HUB).trust(newHuman, type(uint96).max);

        vm.startPrank(newHuman);
        IHub(HUB).registerHuman(gnosisMembers[0], bytes32(0));
        IHub(HUB).setApprovalForAll(newHuman, true);
        vm.stopPrank();

        // ============================== Transfer Source CRC to newHuman ==============================
        uint192 crcAmount = _loadSourceBalance(gnosisMembers[0]);

        vm.prank(gnosisMembers[0]);
        IHub(HUB).safeTransferFrom(gnosisMembers[0], newHuman, uint256(uint160(gnosisMembers[0])), crcAmount, "");

        // Inviter (gnosisMembers[0]) untrusts newHuman to prove the mint does not depend on this trust.
        vm.prank(gnosisMembers[0]);
        IHub(HUB).trust(newHuman, uint96(block.timestamp));
        vm.warp(block.timestamp + 1);

        // ============================== Enable CRC For Routing ==============================
        vm.prank(routerAdmin);
        router.enableCRCForRouting(gnosisMembers);

        // ============================== Configure Group Trust ==============================
        vm.prank(owner);
        BaseGroup(group).trust(gnosisMembers[0], type(uint96).max);

        // newHuman must trust the group to receive the freshly minted group CRC.
        vm.prank(newHuman);
        IHub(HUB).trust(group, type(uint96).max);

        // newHuman is the flow source AND sink; gnosisMembers[0] is the collateral CRC token.
        (
            address[] memory flowVertices,
            TypeDefinitions.FlowEdge[] memory flowEdges,
            TypeDefinitions.Stream[] memory streams,
            bytes memory packCoordinate,
            uint256[] memory collateral,
            uint256[] memory groupMintAmount
        ) = _buildSingleHopFlow(newHuman, gnosisMembers[0], newHuman, crcAmount);

        // First call: newHuman has not approved Router as operator -> reverts.
        vm.prank(newHuman);
        vm.expectRevert(abi.encodeWithSelector(IERC1155Errors.ERC1155MissingApprovalForAll.selector, newHuman, router));
        IHub(HUB).operateFlowMatrix(flowVertices, flowEdges, streams, packCoordinate);

        // Approve newHuman as Router operator and retry.
        address[] memory ops = new address[](1);
        ops[0] = newHuman;
        vm.prank(newHuman);
        router.setApprovalForCRC(ops, _repeatBool(true, 1));

        vm.prank(newHuman);
        vm.expectEmit();
        emit GroupMint(address(router), address(group), address(group), collateral, groupMintAmount);
        IHub(HUB).operateFlowMatrix(flowVertices, flowEdges, streams, packCoordinate);

        assertEq(IHub(HUB).balanceOf(newHuman, uint256(uint160(address(group)))), crcAmount);
    }

    /**
     * @notice Verifies that the Router participates in a multi-hop flow with an intermediate
     *         personal-CRC holder before the Router edge.
     * @dev Path:
     *      gnosisMembers[0] --gnosisMembers[0]CRC--> gnosisMembers[1]
     *                       --gnosisMembers[0]CRC--> router
     *                       --gnosisMembers[0]CRC--> group
     *                       --groupCRC--> gnosisMembers[3]
     *      The 5-vertex / 4-edge layout is specific to this test, so its flow construction is
     *      kept inline rather than using {_buildSingleHopFlow}.
     */
    function testMultistepsOperateFlowMatrix() public {
        // ============================== Enable CRC For Routing ==============================
        vm.prank(routerAdmin);
        router.enableCRCForRouting(gnosisMembers);
        // Approval is permissionless; any caller can set it. Approve all gnosis members so any of
        // them can drive `operateFlowMatrix`.
        router.setApprovalForCRC(gnosisMembers, _repeatBool(true, gnosisMembers.length));

        // ============================== Configure Group Trust ==============================
        vm.prank(owner);
        BaseGroup(group).trust(gnosisMembers[0], type(uint96).max);

        // gnosisMembers[1] must trust gnosisMembers[0] so it can receive gnosisMembers[0]CRC.
        vm.prank(gnosisMembers[1]);
        IHub(HUB).trust(gnosisMembers[0], type(uint96).max);

        // gnosisMembers[1] approves gnosisMembers[0] as operator so the same flow call can move
        // gnosisMembers[0]CRC out of gnosisMembers[1] toward the router.
        vm.prank(gnosisMembers[1]);
        IHub(HUB).setApprovalForAll(gnosisMembers[0], true);

        vm.prank(gnosisMembers[3]);
        IHub(HUB).trust(group, type(uint96).max);

        uint192 crcAmount = _loadSourceBalance(gnosisMembers[0]);

        // ===================== Construct parameter for operateFlowMatrix =====================
        TypeDefinitions.FlowEdge[] memory flowEdges = new TypeDefinitions.FlowEdge[](4);
        TypeDefinitions.Stream[] memory streams = new TypeDefinitions.Stream[](1);
        bytes memory packCoordinate;
        address[] memory flowVertices = new address[](5); // source, gnosisMembers[1], router, group, sink
        flowVertices[0] = gnosisMembers[0];
        flowVertices[1] = gnosisMembers[1];
        flowVertices[2] = address(router);
        flowVertices[3] = address(group);
        flowVertices[4] = gnosisMembers[3];
        uint16[] memory indexes;
        (flowVertices, indexes) = _sortWithMapping(flowVertices);

        flowEdges[0] = TypeDefinitions.FlowEdge({streamSinkId: uint16(0), amount: crcAmount});
        flowEdges[1] = TypeDefinitions.FlowEdge({streamSinkId: uint16(0), amount: crcAmount});
        flowEdges[2] = TypeDefinitions.FlowEdge({streamSinkId: uint16(0), amount: crcAmount});
        flowEdges[3] = TypeDefinitions.FlowEdge({streamSinkId: uint16(1), amount: crcAmount});

        uint16[] memory flowEdgeIds = new uint16[](1);
        flowEdgeIds[0] = uint16(3); // last flowEdge is the terminating edge

        streams[0] = TypeDefinitions.Stream({
            sourceCoordinate: indexes[0], // gnosisMembers[0]
            flowEdgeIds: flowEdgeIds,
            data: bytes("")
        });

        uint16[] memory coords = new uint16[]((flowEdges.length) * 3);

        // gnosisMembers[0] --gnosisMembers[0]CRC--> gnosisMembers[1]
        coords[0] = uint16(indexes[0]);
        coords[1] = uint16(indexes[0]);
        coords[2] = uint16(indexes[1]);

        // gnosisMembers[1] --gnosisMembers[0]CRC--> router
        coords[3] = uint16(indexes[0]);
        coords[4] = uint16(indexes[1]);
        coords[5] = uint16(indexes[2]);

        // router --gnosisMembers[0]CRC--> group
        coords[6] = uint16(indexes[0]);
        coords[7] = uint16(indexes[2]);
        coords[8] = uint16(indexes[3]);

        // group --groupCRC--> gnosisMembers[3]
        coords[9] = uint16(indexes[3]);
        coords[10] = uint16(indexes[3]);
        coords[11] = uint16(indexes[4]);

        packCoordinate = _packCoordinates(coords);

        uint256[] memory collateral = new uint256[](1);
        collateral[0] = uint256(uint160(gnosisMembers[0]));
        uint256[] memory groupMintAmount = new uint256[](1);
        groupMintAmount[0] = crcAmount;

        vm.prank(gnosisMembers[0]);
        vm.expectEmit();
        emit GroupMint(address(router), address(group), address(group), collateral, groupMintAmount);
        IHub(HUB).operateFlowMatrix(flowVertices, flowEdges, streams, packCoordinate);

        assertEq(IHub(HUB).balanceOf(gnosisMembers[3], uint256(uint160(address(group)))), crcAmount);
    }

    /**
     * @notice Lifecycle test: verifies that revoking approval and disabling trust each break the
     *         routing path with the expected, distinct revert reasons.
     * @dev
     *  Phase 1: trust + approval => mint succeeds.
     *  Phase 2: setApprovalForCRC([who], [false]) => Hub reverts with ERC1155MissingApprovalForAll
     *           because gnosisMembers[0] is no longer an approved operator of the Router.
     *  Phase 3: re-approve, then disableCRCForRouting => Hub reverts with
     *           CirclesErrorAddressUintArgs(router, gnosisMembers[0]TokenId, 0x21) because the
     *           gnosisMembers[0] -> router edge is no longer a permitted flow.
     */
    function testRevokeApprovalThenUntrustLifecycle() public {
        // ============================== Setup ==============================
        vm.prank(routerAdmin);
        router.enableCRCForRouting(gnosisMembers);

        vm.prank(owner);
        BaseGroup(group).trust(gnosisMembers[0], type(uint96).max);

        vm.prank(gnosisMembers[3]);
        IHub(HUB).trust(group, type(uint96).max);

        address[] memory who = new address[](1);
        who[0] = gnosisMembers[0];

        vm.prank(gnosisMembers[0]);
        router.setApprovalForCRC(who, _repeatBool(true, 1));

        uint192 fullBalance = _loadSourceBalance(gnosisMembers[0]);
        require(fullBalance >= 3, "source has too little CRC for 3 phases");
        // 1/3 per phase so phases 2 and 3 (which revert) still have unspent CRC after phase 1.
        uint192 amountPerPhase = fullBalance / 3;

        (
            address[] memory flowVertices,
            TypeDefinitions.FlowEdge[] memory flowEdges,
            TypeDefinitions.Stream[] memory streams,
            bytes memory packCoordinate,
            uint256[] memory collateral,
            uint256[] memory groupMintAmount
        ) = _buildSingleHopFlow(gnosisMembers[0], gnosisMembers[0], gnosisMembers[3], amountPerPhase);

        // ============================== Phase 1: trust + approval => success ==============================
        vm.prank(gnosisMembers[0]);
        vm.expectEmit();
        emit GroupMint(address(router), address(group), address(group), collateral, groupMintAmount);
        IHub(HUB).operateFlowMatrix(flowVertices, flowEdges, streams, packCoordinate);

        assertEq(IHub(HUB).balanceOf(gnosisMembers[3], uint256(uint160(address(group)))), amountPerPhase);

        // ============================== Phase 2: revoke approval => ERC1155MissingApprovalForAll ==============================
        vm.prank(gnosisMembers[0]);
        router.setApprovalForCRC(who, _repeatBool(false, 1));

        vm.prank(gnosisMembers[0]);
        vm.expectRevert(
            abi.encodeWithSelector(IERC1155Errors.ERC1155MissingApprovalForAll.selector, gnosisMembers[0], router)
        );
        IHub(HUB).operateFlowMatrix(flowVertices, flowEdges, streams, packCoordinate);

        // ============================== Phase 3: re-approve + disable trust => FlowEdgeNotPermitted ==============================
        vm.prank(gnosisMembers[0]);
        router.setApprovalForCRC(who, _repeatBool(true, 1));

        router.disableCRCForRouting(gnosisMembers);

        // disableCRCForRouting sets trust expiry to 0; warp 1s to ensure it is in the past
        // for isPermittedFlow checks during the next operateFlowMatrix call.
        vm.warp(block.timestamp + 1);

        // The first edge gnosisMembers[0] -> router carrying gnosisMembers[0]CRC fails because
        // the Router no longer trusts gnosisMembers[0]. Hub reverts with
        // CirclesErrorAddressUintArgs(to=router, tokenId=gnosisMembers[0], 0x21).
        vm.prank(gnosisMembers[0]);
        vm.expectRevert(
            abi.encodeWithSelector(
                CirclesErrorAddressUintArgs.selector, address(router), uint256(uint160(gnosisMembers[0])), uint8(0x21)
            )
        );
        IHub(HUB).operateFlowMatrix(flowVertices, flowEdges, streams, packCoordinate);
    }

    // =================================================
    //                INTERNAL HELPERS
    // =================================================

    /**
     * @notice Reads the on-chain personal-CRC balance of `source` for its own avatar id and
     *         returns it cast to `uint192` (the type FlowEdge expects for amounts).
     * @dev Reverts if the balance is zero (test pre-condition not met) or exceeds `uint192`.
     * @param source Personal CRC avatar whose own-CRC balance is used as the flow amount.
     * @return crcAmount The source's own-CRC balance, safe to use as a FlowEdge amount.
     */
    function _loadSourceBalance(address source) internal view returns (uint192 crcAmount) {
        uint256 balance = IHub(HUB).balanceOf(source, uint256(uint160(source)));
        require(balance > 0, "source has no CRC on fork");
        require(balance <= type(uint192).max, "balance exceeds uint192");
        crcAmount = uint192(balance);
    }

    /**
     * @notice Builds the parameters for a single-hop `Hub.operateFlowMatrix` call routing
     *         `collateralCRC` from `source` through the Router into the test group, then
     *         emitting freshly minted group CRC to `sink`.
     * @dev Constructs the flow:
     *      source --collateralCRC--> router --collateralCRC--> group --groupCRC--> sink
     *      The role addresses (source, router, group, sink, collateralCRC) are deduplicated and
     *      sorted via {_dedupeAndSort} to satisfy the Hub's "vertices must be in ascending order"
     *      rule. {_indexOf} is then used to resolve each edge's coordinates against the deduped
     *      and sorted vertex array, so callers can freely pass overlapping role addresses (e.g.
     *      `source == collateralCRC`, `sink == source`).
     * @param source Avatar where the flow originates.
     * @param collateralCRC Personal CRC token traversing the source -> router -> group hops.
     *                      Often equal to `source` (when the source spends its own CRC).
     * @param sink Avatar that receives the freshly minted group CRC.
     * @param amount Flow amount applied uniformly to all three edges.
     * @return flowVertices Deduped, ascending-sorted vertex set for the flow matrix.
     * @return flowEdges 3 edges, terminating edge (index 2) has streamSinkId = 1.
     * @return streams Single stream sourced at `source`, terminating at edge index 2.
     * @return packCoordinate Packed coordinate bytes for the flow matrix.
     * @return collateral Collateral id list (single entry: token id of `collateralCRC`).
     * @return groupMintAmount Mint amount list (single entry: `amount`).
     */
    function _buildSingleHopFlow(address source, address collateralCRC, address sink, uint192 amount)
        internal
        view
        returns (
            address[] memory flowVertices,
            TypeDefinitions.FlowEdge[] memory flowEdges,
            TypeDefinitions.Stream[] memory streams,
            bytes memory packCoordinate,
            uint256[] memory collateral,
            uint256[] memory groupMintAmount
        )
    {
        // Collect all role addresses; dedupe + sort to satisfy Hub's vertex ordering rule.
        {
            address[] memory raw = new address[](5);
            raw[0] = source;
            raw[1] = address(router);
            raw[2] = address(group);
            raw[3] = sink;
            raw[4] = collateralCRC;
            flowVertices = _dedupeAndSort(raw);
        }

        // 3 edges: source -> router, router -> group (both carrying collateralCRC), group -> sink (groupCRC).
        flowEdges = new TypeDefinitions.FlowEdge[](3);
        flowEdges[0] = TypeDefinitions.FlowEdge({streamSinkId: uint16(0), amount: amount});
        flowEdges[1] = TypeDefinitions.FlowEdge({streamSinkId: uint16(0), amount: amount});
        flowEdges[2] = TypeDefinitions.FlowEdge({streamSinkId: uint16(1), amount: amount});

        streams = _buildSingleStream(flowVertices, source);
        packCoordinate = _buildSingleHopCoords(flowVertices, source, sink, collateralCRC);

        collateral = new uint256[](1);
        collateral[0] = uint256(uint160(collateralCRC));
        groupMintAmount = new uint256[](1);
        groupMintAmount[0] = amount;
    }

    /**
     * @notice Builds the single-stream descriptor used by {_buildSingleHopFlow}.
     * @dev Extracted into its own function so {_buildSingleHopFlow}'s stack stays under the
     *      EVM's 16-slot ceiling (otherwise the combination of named return values + per-vertex
     *      indices triggers `Stack too deep`).
     * @param flowVertices The deduped + sorted vertex array; used to resolve the source coordinate.
     * @param source The avatar that originates the flow (whose sorted index becomes
     *               `streams[0].sourceCoordinate`).
     */
    function _buildSingleStream(address[] memory flowVertices, address source)
        internal
        pure
        returns (TypeDefinitions.Stream[] memory streams)
    {
        uint16[] memory flowEdgeIds = new uint16[](1);
        flowEdgeIds[0] = uint16(2); // terminating edge index
        streams = new TypeDefinitions.Stream[](1);
        streams[0] = TypeDefinitions.Stream({
            sourceCoordinate: _indexOf(flowVertices, source), flowEdgeIds: flowEdgeIds, data: bytes("")
        });
    }

    /**
     * @notice Builds the packed coordinate bytes for the single-hop flow (3 edges, 9 coords).
     * @dev Extracted from {_buildSingleHopFlow} for the same stack-depth reason as
     *      {_buildSingleStream}. Reads `router` and `group` from contract storage, hence `view`.
     * @param flowVertices Deduped + sorted vertex array against which all coords are resolved.
     * @param source Flow originator (referenced by edge 0 as `from`).
     * @param sink Group-CRC receiver (referenced by edge 2 as `to`).
     * @param collateralCRC Personal CRC token id traversed on edges 0 and 1.
     */
    function _buildSingleHopCoords(address[] memory flowVertices, address source, address sink, address collateralCRC)
        internal
        view
        returns (bytes memory)
    {
        uint16[] memory coords = new uint16[](9);
        uint16 srcIdx = _indexOf(flowVertices, source);
        uint16 rtrIdx = _indexOf(flowVertices, address(router));
        uint16 grpIdx = _indexOf(flowVertices, address(group));
        uint16 sinkIdx = _indexOf(flowVertices, sink);
        uint16 crcIdx = _indexOf(flowVertices, collateralCRC);
        // collateralCRC: source -> router
        coords[0] = crcIdx;
        coords[1] = srcIdx;
        coords[2] = rtrIdx;
        // collateralCRC: router -> group
        coords[3] = crcIdx;
        coords[4] = rtrIdx;
        coords[5] = grpIdx;
        // groupCRC: group -> sink
        coords[6] = grpIdx;
        coords[7] = grpIdx;
        coords[8] = sinkIdx;
        return _packCoordinates(coords);
    }

    /**
     * @notice Sorts `raw` ascending and removes consecutive duplicates.
     * @dev Used by {_buildSingleHopFlow} so callers can pass overlapping role addresses without
     *      violating Hub's ascending-vertex rule.
     */
    function _dedupeAndSort(address[] memory raw) internal pure returns (address[] memory) {
        // Bubble sort
        for (uint256 i = 0; i < raw.length; i++) {
            for (uint256 j = 0; j < raw.length - i - 1; j++) {
                if (raw[j] > raw[j + 1]) {
                    (raw[j], raw[j + 1]) = (raw[j + 1], raw[j]);
                }
            }
        }
        if (raw.length == 0) return raw;
        uint256 unique = 1;
        for (uint256 i = 1; i < raw.length; i++) {
            if (raw[i] != raw[i - 1]) ++unique;
        }
        address[] memory result = new address[](unique);
        result[0] = raw[0];
        uint256 idx = 1;
        for (uint256 i = 1; i < raw.length; i++) {
            if (raw[i] != raw[i - 1]) {
                result[idx++] = raw[i];
            }
        }
        return result;
    }

    /**
     * @notice Returns the index of `target` in `arr`, or reverts if absent.
     */
    function _indexOf(address[] memory arr, address target) internal pure returns (uint16) {
        for (uint16 i = 0; i < arr.length; ++i) {
            if (arr[i] == target) return i;
        }
        revert("address not found in vertex array");
    }

    /**
     * @notice Builds a `bool[]` of length `length` filled with `value`.
     * @dev Convenience helper for the unified {ScoreGroupMintRouter.setApprovalForCRC} signature
     *      `(address[], bool[])` so tests can express "approve all" / "revoke all" concisely.
     */
    function _repeatBool(bool value, uint256 length) internal pure returns (bool[] memory result) {
        result = new bool[](length);
        for (uint256 i; i < length;) {
            result[i] = value;
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Sorts an array of addresses in ascending order
     *         and returns both the sorted array and a mapping (as an array)
     *         that indicates the original index for each sorted element.
     *          Helper function from MintRedemptionFlow.t.sol
     * @param arr The array of addresses to sort.
     * @return sortedAddresses The sorted array of addresses.
     * @return indexes An array where each element is the original index
     *         of the corresponding address in the sorted array.
     */
    function _sortWithMapping(address[] memory arr)
        internal
        pure
        returns (address[] memory sortedAddresses, uint16[] memory indexes)
    {
        uint16[] memory permutation = new uint16[](arr.length);
        for (uint16 i; i < arr.length;) {
            permutation[i] = i;
            unchecked {
                ++i;
            }
        }

        for (uint256 i = 0; i < arr.length; i++) {
            for (uint256 j = 0; j < arr.length - i - 1; j++) {
                if (arr[j] > arr[j + 1]) {
                    address temp = arr[j];
                    arr[j] = arr[j + 1];
                    arr[j + 1] = temp;

                    uint16 tempIndex = permutation[j];
                    permutation[j] = permutation[j + 1];
                    permutation[j + 1] = tempIndex;
                }
            }
        }

        indexes = new uint16[](arr.length);
        for (uint16 i = 0; i < arr.length; i++) {
            indexes[permutation[i]] = i;
        }
        return (arr, indexes);
    }

    /**
     * @notice helper function from FlowMatrixGenerator.sol
     * @dev Packs `coords` (of length 3*E) into 6*E bytes:
     *      for each triple (c0, c1, c2), produce c0(16 bits), c1(16 bits), c2(16 bits).
     */
    function _packCoordinates(uint16[] memory coords) internal pure returns (bytes memory) {
        require(coords.length % 3 == 0, "Coords length must be multiple of 3");
        uint256 edgeCount = coords.length / 3;
        bytes memory result = new bytes(edgeCount * 6);

        for (uint256 i = 0; i < edgeCount; i++) {
            uint16 c0 = coords[3 * i + 0];
            uint16 c1 = coords[3 * i + 1];
            uint16 c2 = coords[3 * i + 2];

            uint256 offset = i * 6;
            result[offset + 0] = bytes1(uint8(c0 >> 8));
            result[offset + 1] = bytes1(uint8(c0 & 0xFF));
            result[offset + 2] = bytes1(uint8(c1 >> 8));
            result[offset + 3] = bytes1(uint8(c1 & 0xFF));
            result[offset + 4] = bytes1(uint8(c2 >> 8));
            result[offset + 5] = bytes1(uint8(c2 & 0xFF));
        }
        return result;
    }
}
