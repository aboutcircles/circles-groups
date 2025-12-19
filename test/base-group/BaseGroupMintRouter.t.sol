// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import "forge-std/StdCheats.sol";
import {Test, console} from "forge-std/Test.sol";
import "circles-contracts-v2/hub/TypeDefinitions.sol";
import {IERC1155Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {BaseMintPolicy} from "src/base-group/BaseMintPolicy.sol";
import {BaseGroup} from "src/base-group/BaseGroup.sol";
import {BaseGroupFactory} from "src/base-group/BaseGroupFactory.sol";
import {BaseGroupMintRouter} from "src/base-group/BaseGroupMintRouter.sol";
import {CirclesV2Setup} from "./helpers/CirclesV2Setup.sol";
import {HubStorageWrites} from "./helpers/HubStorageWrites.sol";

/**
 * @title BaseGroupMintRouterTest
 * @notice Test suite for the BaseGroupMintRouter contract.
 * @dev This contract contains a suite of tests to verify the functionality of the BaseGroupMintRouter,
 * ensuring that group minting via flow matrix operations, access control, and configuration settings
 * work as expected.
 */
contract BaseGroupMintRouterTest is Test, HubStorageWrites, CirclesV2Setup {
    event GroupMint(
        address indexed sender, address indexed receiver, address indexed group, uint256[] collateral, uint256[] amounts
    );

    error CirclesErrorAddressUintArgs(address, uint256, uint8);

    address constant BASE_MINT_POLICY = address(0xCDFc5135AEC0aFbf102C108e7f5C8A88C6112842);
    address constant BASE_GROUP_FACTORY = address(0xD0B5Bd9962197BEaC4cbA24244ec3587f19Bd06d);
    // Factory for base group
    BaseGroupFactory baseGroupFactory;

    // The deployed base group (for our test group)
    BaseGroup baseGroup;
    address group;
    uint256 groupTokenId;
    address mintHandler;
    address treasury;

    BaseGroupMintRouter router;
    uint64 today;

    address sourceAvatar;
    address sinkAvatar;
    address owner;
    address routerAdmin;
    address alice;
    address bob;

    /**
     * @notice Sets up the test environment.
     * @dev Deploys and configures the necessary contracts for testing the BaseGroupMintRouter.
     * This includes setting up Circles V2, creating a base group, deploying the router,
     * registering human avatars, and enabling CRC for routing.
     */
    function setUp() public override {
        // setup contract bytecode and storage layout
        super.setUp();
        // set correct starting timestamp
        vm.warp(INVITATION_ONLY_TIME + 1 days);

        // setup HUB_V2 today
        today = HUB_V2.day(block.timestamp);
        // BASE_MINT_POLICY is hardcoded in BaseGroup.sol and will be called during BaseGroup contract creation
        vm.etch(BASE_MINT_POLICY, type(BaseMintPolicy).runtimeCode);

        // ============================== Create Group ==============================
        // BaseGroupFactory address is hardcoded in the BaseGroupMintRouter contract, hence need to set BaseGroupFactory bytecode to the address 0xD0B5Bd9962197BEaC4cbA24244ec3587f19Bd06d
        baseGroupFactory = new BaseGroupFactory();
        vm.etch(BASE_GROUP_FACTORY, address(baseGroupFactory).code);
        baseGroupFactory = BaseGroupFactory(BASE_GROUP_FACTORY);

        owner = makeAddr("owner");
        routerAdmin = makeAddr("routerAdmin");
        address service = makeAddr("service");
        address feeCollection = makeAddr("feeCollection");
        address[] memory initialConditions;
        string memory groupName = "TestGroup";
        string memory groupSymbol = "TG";
        bytes32 metadataDigest = keccak256(abi.encodePacked("metadata"));

        (group, mintHandler, treasury) = baseGroupFactory.createBaseGroup(
            owner, service, feeCollection, initialConditions, groupName, groupSymbol, metadataDigest
        );

        baseGroup = BaseGroup(group);
        groupTokenId = uint256(uint160(group));

        // ============================== Create BaseGroupMintRouter ==============================
        router = new BaseGroupMintRouter(routerAdmin);

        // ============================== Register Humans ==============================

        // Register 4 new human

        sourceAvatar = makeAddr("sourceAvatar");
        sinkAvatar = makeAddr("sinkAvatar");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        // register avatars as human and set Operator Approval
        _registerHuman(sourceAvatar);
        _registerHuman(sinkAvatar);
        _registerHuman(alice);
        _registerHuman(bob);
        _setOperatorApproval(sourceAvatar, sourceAvatar);
        _setOperatorApproval(sinkAvatar, sinkAvatar);
        _setOperatorApproval(alice, alice);
        _setOperatorApproval(bob, bob);
    }

    /**
     * @notice Tests the core functionality of the mint router.
     * @dev This test verifies that a group mint can be successfully executed when the group
     * acts as an intermediate node in a flow matrix operation. It simulates a flow from a
     * source avatar, through the router, to the group, and finally to a sink avatar.
     * @param crcAmount The amount of CRC to be used in the flow.
     */
    function testFlowWithRouterBasic(uint192 crcAmount) public {
        // Configure trust
        vm.prank(owner);
        baseGroup.trust(sourceAvatar, type(uint96).max);

        // sinkAvatar only trust group
        _setTrust(sinkAvatar, address(baseGroup));

        // ============================== Enable CRC For Routing ==============================
        // group only trust sourceAvatar
        address[] memory acceptedCRC = new address[](1);
        acceptedCRC[0] = sourceAvatar;

        // configure router
        router.enableCRCForRouting(address(baseGroup), acceptedCRC);

        vm.assume(crcAmount > 0);
        _setCRCBalance(uint256(uint160(sourceAvatar)), sourceAvatar, today, crcAmount);

        // ===================== Construct parameter for operateFlowMatrix =====================

        // sourceAvatar --> router --> group --> sinkAvatar

        TypeDefinitions.FlowEdge[] memory flowEdges = new TypeDefinitions.FlowEdge[](3);
        TypeDefinitions.Stream[] memory streams = new TypeDefinitions.Stream[](1);
        bytes memory packCoordinate;
        address[] memory flowVertices = new address[](4); // sourceAvatar, group, router, sinkAvatar
        flowVertices[0] = sourceAvatar;
        flowVertices[1] = address(router);
        flowVertices[2] = address(baseGroup);
        flowVertices[3] = sinkAvatar;
        uint16[] memory indexes;
        (flowVertices, indexes) = _sortWithMapping(flowVertices);

        flowEdges[0] = TypeDefinitions.FlowEdge({streamSinkId: uint16(0), amount: crcAmount});
        flowEdges[1] = TypeDefinitions.FlowEdge({streamSinkId: uint16(0), amount: crcAmount});
        flowEdges[2] = TypeDefinitions.FlowEdge({streamSinkId: uint16(1), amount: crcAmount});

        uint16[] memory flowEdgeIds = new uint16[](1);
        flowEdgeIds[0] = uint16(2); // the last flowEdges is terminated edge

        streams[0] = TypeDefinitions.Stream({
            sourceCoordinate: indexes[0], // source Avatar
            flowEdgeIds: flowEdgeIds,
            data: bytes("")
        });

        uint16[] memory coords = new uint16[]((flowEdges.length) * 3);

        // sourceAvatar --sourceCRC-->router
        coords[0] = uint16(indexes[0]);
        coords[1] = uint16(indexes[0]);
        coords[2] = uint16(indexes[1]);

        // router --sourceCRC--> group
        coords[3] = uint16(indexes[0]);
        coords[4] = uint16(indexes[1]);
        coords[5] = uint16(indexes[2]);

        // group --groupCRC--> sinkAvatar
        coords[6] = uint16(indexes[2]);
        coords[7] = uint16(indexes[2]);
        coords[8] = uint16(indexes[3]);

        packCoordinate = _packCoordinates(coords);

        uint256[] memory collateral = new uint256[](1);
        collateral[0] = uint256(uint160(sourceAvatar));
        uint256[] memory groupMintAmount = new uint256[](1);
        groupMintAmount[0] = crcAmount;

        // ===================== call operateFlowMatrix =====================
        vm.prank(sourceAvatar);
        vm.expectEmit();
        emit GroupMint(address(router), address(group), address(group), collateral, groupMintAmount);
        HUB_V2.operateFlowMatrix(flowVertices, flowEdges, streams, packCoordinate);

        assertEq(HUB_V2.balanceOf(sinkAvatar, uint256(uint160(address(baseGroup)))), crcAmount);
    }

    /**
     * @notice Tests complex flow routing through multiple intermediaries.
     * @dev This test verifies that the router can handle a complex flow path:
     * sourceAvatar -> alice -> bob -> router -> group -> sinkAvatar.
     * The router must correctly manage CRC approvals for multiple accepted tokens
     * and facilitate group minting through this multi-hop path.
     * @param crcAmount The amount of CRC to be routed through the flow.
     */
    function testFlowWithRouter(uint192 crcAmount) public {
        // Base group only trust alice
        vm.prank(owner);
        baseGroup.trust(alice, type(uint96).max);

        // sinkAvatar only trust group
        _setTrust(sinkAvatar, address(baseGroup));

        // alice only trust sourceAvatar
        _setTrust(alice, sourceAvatar);

        // bob only trust alice
        _setTrust(bob, alice);

        // ============================== Enable CRC For Routing ==============================
        // group only trust alice
        address[] memory acceptedCRC = new address[](2);
        acceptedCRC[0] = sourceAvatar; // router set approval for source
        acceptedCRC[1] = alice; // router trust alice because group trust alice

        // configure router
        router.enableCRCForRouting(address(baseGroup), acceptedCRC);
        vm.assume(crcAmount > 0);
        _setCRCBalance(uint256(uint160(sourceAvatar)), sourceAvatar, today, crcAmount);
        _setCRCBalance(uint256(uint160(alice)), alice, today, crcAmount);

        // ===================== Construct parameter for operateFlowMatrix =====================

        // sourceAvatar --> alice --> bob --> router --> group --> sinkAvatar

        TypeDefinitions.FlowEdge[] memory flowEdges = new TypeDefinitions.FlowEdge[](5);
        TypeDefinitions.Stream[] memory streams = new TypeDefinitions.Stream[](1);
        bytes memory packCoordinate;
        address[] memory flowVertices = new address[](6);
        flowVertices[0] = sourceAvatar;
        flowVertices[1] = alice;
        flowVertices[2] = bob;
        flowVertices[3] = address(router);
        flowVertices[4] = address(baseGroup);
        flowVertices[5] = sinkAvatar;
        uint16[] memory indexes;
        (flowVertices, indexes) = _sortWithMapping(flowVertices);

        flowEdges[0] = TypeDefinitions.FlowEdge({streamSinkId: uint16(0), amount: crcAmount});
        flowEdges[1] = TypeDefinitions.FlowEdge({streamSinkId: uint16(0), amount: crcAmount});
        flowEdges[2] = TypeDefinitions.FlowEdge({streamSinkId: uint16(0), amount: crcAmount});
        flowEdges[3] = TypeDefinitions.FlowEdge({streamSinkId: uint16(0), amount: crcAmount});
        flowEdges[4] = TypeDefinitions.FlowEdge({streamSinkId: uint16(1), amount: crcAmount});

        uint16[] memory flowEdgeIds = new uint16[](1);
        flowEdgeIds[0] = uint16(4); // the last flowEdges is terminated edge

        streams[0] = TypeDefinitions.Stream({
            sourceCoordinate: indexes[0], // source Avatar
            flowEdgeIds: flowEdgeIds,
            data: bytes("")
        });

        uint16[] memory coords = new uint16[]((flowEdges.length) * 3);

        // sourceAvatar --sourceCRC-->alice
        coords[0] = uint16(indexes[0]);
        coords[1] = uint16(indexes[0]);
        coords[2] = uint16(indexes[1]);

        // alice --aliceCRC--> bob
        coords[3] = uint16(indexes[1]);
        coords[4] = uint16(indexes[1]);
        coords[5] = uint16(indexes[2]);

        // bob --aliceCRC-->router
        coords[6] = uint16(indexes[1]);
        coords[7] = uint16(indexes[2]);
        coords[8] = uint16(indexes[3]);

        // router --aliceCRC--> group
        coords[9] = uint16(indexes[1]);
        coords[10] = uint16(indexes[3]);
        coords[11] = uint16(indexes[4]);

        // group --groupCRC--> sinkAvatar
        coords[12] = uint16(indexes[4]);
        coords[13] = uint16(indexes[4]);
        coords[14] = uint16(indexes[5]);

        packCoordinate = _packCoordinates(coords);

        uint256[] memory collateral = new uint256[](1);
        collateral[0] = uint256(uint160(alice));
        uint256[] memory groupMintAmount = new uint256[](1);
        groupMintAmount[0] = crcAmount;

        // ===================== call operateFlowMatrix =====================

        vm.prank(sourceAvatar);
        vm.expectEmit();
        emit GroupMint(address(router), address(group), address(group), collateral, groupMintAmount);
        HUB_V2.operateFlowMatrix(flowVertices, flowEdges, streams, packCoordinate);

        assertEq(HUB_V2.balanceOf(sinkAvatar, uint256(uint160(address(baseGroup)))), crcAmount);
    }

    /**
     * @notice Tests direct group minting without router intermediary.
     * @dev Verifies that group minting works correctly in a simple flow:
     * sourceAvatar -> group -> sinkAvatar. This demonstrates the baseline
     * functionality where the group can mint tokens directly without needing
     * the router as an intermediary.
     * @param crcAmount The amount of CRC to be used in the direct flow.
     */
    function testFlowWithoutRouterDirectGroupAfterSource(uint192 crcAmount) public {
        vm.prank(owner);
        baseGroup.trust(sourceAvatar, type(uint96).max);

        // sinkAvatar only trust group
        _setTrust(sinkAvatar, address(baseGroup));

        vm.assume(crcAmount > 0);
        _setCRCBalance(uint256(uint160(sourceAvatar)), sourceAvatar, today, crcAmount);

        // ===================== Construct parameter for operateFlowMatrix =====================

        // sourceAvatar --> group --> sinkAvatar

        TypeDefinitions.FlowEdge[] memory flowEdges = new TypeDefinitions.FlowEdge[](2);
        TypeDefinitions.Stream[] memory streams = new TypeDefinitions.Stream[](1);
        bytes memory packCoordinate;
        address[] memory flowVertices = new address[](3); // sourceAvatar, group, router, sinkAvatar
        flowVertices[0] = sourceAvatar;
        flowVertices[1] = address(baseGroup);
        flowVertices[2] = sinkAvatar;
        uint16[] memory indexes;
        (flowVertices, indexes) = _sortWithMapping(flowVertices);

        flowEdges[0] = TypeDefinitions.FlowEdge({streamSinkId: uint16(0), amount: crcAmount});
        flowEdges[1] = TypeDefinitions.FlowEdge({streamSinkId: uint16(1), amount: crcAmount});

        uint16[] memory flowEdgeIds = new uint16[](1);
        flowEdgeIds[0] = uint16(1); // the last flowEdges is terminated edge

        streams[0] = TypeDefinitions.Stream({
            sourceCoordinate: indexes[0], // source Avatar
            flowEdgeIds: flowEdgeIds,
            data: bytes("")
        });

        uint16[] memory coords = new uint16[]((flowEdges.length) * 3);

        // sourceAvatar --sourceCRC-->group
        coords[0] = uint16(indexes[0]);
        coords[1] = uint16(indexes[0]);
        coords[2] = uint16(indexes[1]);

        // group --groupCRC--> sinkAvatar
        coords[3] = uint16(indexes[1]);
        coords[4] = uint16(indexes[1]);
        coords[5] = uint16(indexes[2]);

        packCoordinate = _packCoordinates(coords);

        uint256[] memory collateral = new uint256[](1);
        collateral[0] = uint256(uint160(sourceAvatar));
        uint256[] memory groupMintAmount = new uint256[](1);
        groupMintAmount[0] = crcAmount;

        // ===================== call operateFlowMatrix =====================

        vm.prank(sourceAvatar);
        vm.expectEmit();
        emit GroupMint(sourceAvatar, address(group), address(group), collateral, groupMintAmount);
        HUB_V2.operateFlowMatrix(flowVertices, flowEdges, streams, packCoordinate);

        assertEq(HUB_V2.balanceOf(sinkAvatar, uint256(uint160(address(baseGroup)))), crcAmount);
    }

    // Show the flow will fail because the node before group(alice) is not approved by operator
    /**
     * @notice Tests flow failure when router is not used for intermediary approval.
     * @dev This test demonstrates that flows fail when an intermediary node (alice)
     * is not properly approved by the source avatar's operator. The flow
     * sourceAvatar -> alice -> group -> sinkAvatar should fail because alice
     * lacks proper approval from sourceAvatar to spend their tokens.
     * @param crcAmount The amount of CRC that should fail to be routed.
     */
    function testFlowWithoutRouter(uint192 crcAmount) public {
        vm.prank(owner);
        baseGroup.trust(sourceAvatar, type(uint96).max);

        // sinkAvatar only trust group
        _setTrust(sinkAvatar, address(baseGroup));

        _setTrust(alice, sourceAvatar);

        vm.assume(crcAmount > 0);
        _setCRCBalance(uint256(uint160(sourceAvatar)), sourceAvatar, today, crcAmount);

        // ===================== Construct parameter for operateFlowMatrix =====================

        // sourceAvatar --> alice --> group --> sinkAvatar

        TypeDefinitions.FlowEdge[] memory flowEdges = new TypeDefinitions.FlowEdge[](3);
        TypeDefinitions.Stream[] memory streams = new TypeDefinitions.Stream[](1);
        bytes memory packCoordinate;
        address[] memory flowVertices = new address[](4); // sourceAvatar, group, router, sinkAvatar
        flowVertices[0] = sourceAvatar;
        flowVertices[1] = alice;
        flowVertices[2] = address(baseGroup);
        flowVertices[3] = sinkAvatar;
        uint16[] memory indexes;
        (flowVertices, indexes) = _sortWithMapping(flowVertices);

        flowEdges[0] = TypeDefinitions.FlowEdge({streamSinkId: uint16(0), amount: crcAmount});
        flowEdges[1] = TypeDefinitions.FlowEdge({streamSinkId: uint16(0), amount: crcAmount});
        flowEdges[2] = TypeDefinitions.FlowEdge({streamSinkId: uint16(1), amount: crcAmount});

        uint16[] memory flowEdgeIds = new uint16[](1);
        flowEdgeIds[0] = uint16(1); // the last flowEdges is terminated edge

        streams[0] = TypeDefinitions.Stream({
            sourceCoordinate: indexes[0], // source Avatar
            flowEdgeIds: flowEdgeIds,
            data: bytes("")
        });

        uint16[] memory coords = new uint16[]((flowEdges.length) * 3);

        // sourceAvatar --sourceCRC-->alice
        coords[0] = uint16(indexes[0]);
        coords[1] = uint16(indexes[0]);
        coords[2] = uint16(indexes[1]);

        // alice --sourceCRC-->group
        coords[3] = uint16(indexes[0]);
        coords[4] = uint16(indexes[1]);
        coords[5] = uint16(indexes[2]);

        // group --groupCRC--> sinkAvatar
        coords[6] = uint16(indexes[2]);
        coords[7] = uint16(indexes[2]);
        coords[8] = uint16(indexes[3]);

        packCoordinate = _packCoordinates(coords);

        uint256[] memory collateral = new uint256[](1);
        collateral[0] = uint256(uint160(sourceAvatar));
        uint256[] memory groupMintAmount = new uint256[](1);
        groupMintAmount[0] = crcAmount;

        // ===================== call operateFlowMatrix =====================

        vm.prank(sourceAvatar);
        vm.expectRevert(
            abi.encodeWithSelector(IERC1155Errors.ERC1155MissingApprovalForAll.selector, sourceAvatar, alice)
        );
        HUB_V2.operateFlowMatrix(flowVertices, flowEdges, streams, packCoordinate);

        assertEq(HUB_V2.balanceOf(sinkAvatar, uint256(uint160(address(baseGroup)))), 0);
    }

    /**
     * @notice Tests router behavior when group or treasury acts as sink.
     * @dev This test verifies two scenarios:
     * 1. When the group itself is the sink node (should fail due to missing ERC1155Receiver)
     * 2. When the group treasury is the sink node (should fail due to permission restrictions)
     * Both cases should revert with specific errors, demonstrating proper access control.
     * @param crcAmount The amount of CRC to attempt routing to sink nodes.
     */
    function testGroupOrTreasuryAsSink(uint192 crcAmount) public {
        // =========================================================================
        // ========================= Try to send to group  =========================
        // =========================================================================
        vm.prank(owner);
        baseGroup.trust(sourceAvatar, type(uint96).max);

        // ============================== Enable CRC For Routing ==============================
        // group only trust sourceAvatar
        address[] memory acceptedCRC = new address[](1);
        acceptedCRC[0] = sourceAvatar;

        // configure router
        router.enableCRCForRouting(address(baseGroup), acceptedCRC);

        vm.assume(crcAmount > 0);
        _setCRCBalance(uint256(uint160(sourceAvatar)), sourceAvatar, today, crcAmount);

        // ===================== Construct parameter for operateFlowMatrix =====================

        // sourceAvatar --> router --> group

        TypeDefinitions.FlowEdge[] memory flowEdges = new TypeDefinitions.FlowEdge[](2);
        TypeDefinitions.Stream[] memory streams = new TypeDefinitions.Stream[](1);
        bytes memory packCoordinate;
        address[] memory flowVertices = new address[](3); // sourceAvatar, group, router, sinkAvatar
        flowVertices[0] = sourceAvatar;
        flowVertices[1] = address(router);
        flowVertices[2] = address(baseGroup);
        uint16[] memory indexes;
        (flowVertices, indexes) = _sortWithMapping(flowVertices);

        flowEdges[0] = TypeDefinitions.FlowEdge({streamSinkId: uint16(0), amount: crcAmount});
        flowEdges[1] = TypeDefinitions.FlowEdge({streamSinkId: uint16(1), amount: crcAmount});

        uint16[] memory flowEdgeIds = new uint16[](1);
        flowEdgeIds[0] = uint16(1); // the last flowEdges is terminated edge

        streams[0] = TypeDefinitions.Stream({
            sourceCoordinate: indexes[0], // source Avatar
            flowEdgeIds: flowEdgeIds,
            data: bytes("")
        });

        uint16[] memory coords = new uint16[]((flowEdges.length) * 3);

        // sourceAvatar --sourceCRC-->router
        coords[0] = uint16(indexes[0]);
        coords[1] = uint16(indexes[0]);
        coords[2] = uint16(indexes[1]);

        // router --sourceCRC--> group
        coords[3] = uint16(indexes[0]);
        coords[4] = uint16(indexes[1]);
        coords[5] = uint16(indexes[2]);

        packCoordinate = _packCoordinates(coords);

        uint256[] memory collateral = new uint256[](1);
        collateral[0] = uint256(uint160(sourceAvatar));
        uint256[] memory groupMintAmount = new uint256[](1);
        groupMintAmount[0] = crcAmount;

        // ===================== call operateFlowMatrix =====================

        // Will revert since BaseGroup contract don't have ERC1155 receiver interface
        vm.prank(sourceAvatar);
        vm.expectRevert(abi.encodeWithSelector(IERC1155Errors.ERC1155InvalidReceiver.selector, address(baseGroup)));
        HUB_V2.operateFlowMatrix(flowVertices, flowEdges, streams, packCoordinate);

        // =========================================================================
        // ===================== Try to send to group Treasury =====================
        // =========================================================================
        flowVertices[0] = sourceAvatar;
        flowVertices[1] = address(router);
        flowVertices[2] = treasury;
        (flowVertices, indexes) = _sortWithMapping(flowVertices);

        flowEdges[0] = TypeDefinitions.FlowEdge({streamSinkId: uint16(0), amount: crcAmount});
        flowEdges[1] = TypeDefinitions.FlowEdge({streamSinkId: uint16(1), amount: crcAmount});

        streams[0] = TypeDefinitions.Stream({
            sourceCoordinate: indexes[0], // source Avatar
            flowEdgeIds: flowEdgeIds,
            data: bytes("")
        });

        // sourceAvatar --sourceCRC-->router
        coords[0] = uint16(indexes[0]);
        coords[1] = uint16(indexes[0]);
        coords[2] = uint16(indexes[1]);

        // router --sourceCRC--> group Treasury
        coords[3] = uint16(indexes[0]);
        coords[4] = uint16(indexes[1]);
        coords[5] = uint16(indexes[2]);

        packCoordinate = _packCoordinates(coords);
        assertTrue(HUB_V2.isApprovedForAll(sourceAvatar, sourceAvatar));
        assertTrue(
            HUB_V2.isApprovedForAll(flowVertices[streams[0].sourceCoordinate], sourceAvatar),
            "source avatar didn't approve"
        );

        // ===================== call operateFlowMatrix =====================
        // Will revert since isPermittedFlow(from: router, to: treasury, circlesId: sourceAvatar) is false
        vm.prank(sourceAvatar);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseGroupMintRouterTest.CirclesErrorAddressUintArgs.selector,
                address(treasury),
                uint256(uint160(sourceAvatar)),
                0x21
            )
        );
        HUB_V2.operateFlowMatrix(flowVertices, flowEdges, streams, packCoordinate);
    }

    /**
     * @notice Tests the freeze functionality of the router.
     * @dev Verifies that only the router admin can freeze and unfreeze the router.
     * @param nonAdmin An address that is not the router admin.
     */
    function testFreeze(address nonAdmin) public {
        vm.assume(nonAdmin != routerAdmin);

        vm.prank(nonAdmin);
        vm.expectRevert();
        router.freeze(true);

        vm.prank(routerAdmin);
        router.freeze(true);
        bytes32 isFrozen = vm.load(address(router), bytes32(0));

        // frozen should be true
        assertEq(isFrozen, 0x0000000000000000000000000000000000000000000000000000000000000001);
    }

    // Internal helpers

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
        // Initialize the indexes array to track original positions.
        // Each position i starts with the value i.
        uint16[] memory permutation = new uint16[](arr.length);
        for (uint16 i; i < arr.length;) {
            permutation[i] = i;
            unchecked {
                ++i;
            }
        }

        // We'll perform a bubble sort on the addresses array.
        // As we swap addresses, we swap the indexes as well.
        for (uint256 i = 0; i < arr.length; i++) {
            for (uint256 j = 0; j < arr.length - i - 1; j++) {
                // Compare addresses directly (addresses are comparable)
                if (arr[j] > arr[j + 1]) {
                    // Swap addresses
                    address temp = arr[j];
                    arr[j] = arr[j + 1];
                    arr[j + 1] = temp;

                    // Swap corresponding indexes to maintain mapping
                    uint16 tempIndex = permutation[j];
                    permutation[j] = permutation[j + 1];
                    permutation[j + 1] = tempIndex;
                }
            }
        }

        indexes = new uint16[](arr.length);
        for (uint16 i = 0; i < arr.length; i++) {
            // Place i at the index specified by arr[i]
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
            // 3 coords per edge
            uint16 c0 = coords[3 * i + 0];
            uint16 c1 = coords[3 * i + 1];
            uint16 c2 = coords[3 * i + 2];

            // Each coord => 2 bytes
            // so offset is i*6
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
