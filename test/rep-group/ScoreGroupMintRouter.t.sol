// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import "forge-std/StdCheats.sol";
import {Test, console} from "forge-std/Test.sol";
import "circles-contracts-v2/hub/TypeDefinitions.sol";
import {IERC1155Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {BaseMintPolicy} from "src/base-group/BaseMintPolicy.sol";
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
// setup: Fork test, selected members lists for testing, create fake new group, make sure the new group is accepted
// test: trust enable/disable, operateFlowMatrix,
contract ScoreGroupMintRouterTest is Test {
    event GroupMint(
        address indexed sender, address indexed receiver, address indexed group, uint256[] collateral, uint256[] amounts
    );

    error CirclesErrorAddressUintArgs(address, uint256, uint8);

    // Factory for base group

    BaseGroupFactory constant baseGroupFactory = BaseGroupFactory(0xD0B5Bd9962197BEaC4cbA24244ec3587f19Bd06d);

    // The deployed base group (for our test group)
    address gnosisGrp;
    address group;
    uint256 groupTokenId;
    address mintHandler;
    address treasury;

    ScoreGroupMintRouter router;
    uint64 today;

    address sourceAvatar;
    address sinkAvatar;
    address owner;
    address routerAdmin;
    address alice;
    address bob;
    address[] gnosisMembers = [
        0x42cEDde51198D1773590311E2A340DC06B24cB37,
        0xF7bD3d83df90B4682725ADf668791D4D1499207f,
        0x14aaB8D72B68c79cbb7873D003585a7C3EF98633,
        0xfDEA8140093878BfcA93aAA35d3D3087F4Ab136d
    ];
    address HUB = 0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8;

    /**
     * @notice Sets up the test environment.
     * @dev Deploys and configures the necessary contracts for testing the ScoreGroupMintRouter.
     * This includes setting up Circles V2, creating a base group, deploying the router,
     * registering human avatars, and enabling CRC for routing.
     */
    function setUp() public {
        // ============================== Create Group ==============================
        // BaseGroupFactory address is hardcoded in the ScoreGroupMintRouter contract, hence need to set BaseGroupFactory bytecode to the address 0xD0B5Bd9962197BEaC4cbA24244ec3587f19Bd06d

        owner = makeAddr("owner");
        routerAdmin = makeAddr("routerAdmin");
        address service = makeAddr("service");
        address feeCollection = makeAddr("feeCollection");
        address[] memory initialConditions;
        string memory groupName = "ScoreGroup";
        string memory groupSymbol = "SG";
        bytes32 metadataDigest = keccak256(abi.encodePacked("metadata"));

        (group, mintHandler, treasury) = baseGroupFactory.createBaseGroup(
            owner, service, feeCollection, initialConditions, groupName, groupSymbol, metadataDigest
        );

        gnosisGrp = 0xC19BC204eb1c1D5B3FE500E5E5dfaBaB625F286c;

        groupTokenId = uint256(uint160(group));

        // ============================== Create ScoreGroupMintRouter ==============================
        router = new ScoreGroupMintRouter(routerAdmin);
    }

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

    function testEnableCRCReverts() public {
        // ===================== Revert: OnlyAdmin =====================
        address nonAdmin = makeAddr("nonAdmin");
        vm.prank(nonAdmin);
        vm.expectRevert(ScoreGroupMintRouter.OnlyAdmin.selector);
        router.enableCRCForRouting(gnosisMembers);

        // ===================== Revert: OnlyHuman =====================
        // A non-human address (the freshly deployed router itself is registered as an organization, not human)
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

    function testDisableCRCForRouting() public {
        // First enable so trust is set on the Router for the gnosis members
        vm.prank(routerAdmin);
        router.enableCRCForRouting(gnosisMembers);

        vm.assertTrue(IHub(HUB).isTrusted(address(router), gnosisMembers[0]));
        vm.assertTrue(IHub(HUB).isTrusted(address(router), gnosisMembers[1]));
        vm.assertTrue(IHub(HUB).isTrusted(address(router), gnosisMembers[2]));
        vm.assertTrue(IHub(HUB).isTrusted(address(router), gnosisMembers[3]));

        // Then disable and verify trust is removed
        vm.prank(routerAdmin);
        router.disableCRCForRouting(gnosisMembers);

        vm.warp(block.timestamp + 1);

        vm.assertFalse(IHub(HUB).isTrusted(address(router), gnosisMembers[0]));
        vm.assertFalse(IHub(HUB).isTrusted(address(router), gnosisMembers[1]));
        vm.assertFalse(IHub(HUB).isTrusted(address(router), gnosisMembers[2]));
        vm.assertFalse(IHub(HUB).isTrusted(address(router), gnosisMembers[3]));
    }

    function testRoutingFromGnosisGrpMemberToNewGrp() public {
        // ============================== Enable CRC For Routing ==============================
        vm.prank(routerAdmin);
        router.enableCRCForRouting(gnosisMembers);

        // ============================== Configure Group Trust ==============================
        // The new group must trust the gnosis members so their CRCs are accepted as collateral.
        // Trust must be issued by the group avatar itself, so route through BaseGroup.trust().
        vm.startPrank(owner);
        BaseGroup(group).trust(gnosisMembers[0], type(uint96).max);
        BaseGroup(group).trust(gnosisMembers[1], type(uint96).max);
        BaseGroup(group).trust(gnosisMembers[2], type(uint96).max);
        BaseGroup(group).trust(gnosisMembers[3], type(uint96).max);
        vm.stopPrank();

        // sink (gnosisMembers[3]) must trust the new group to receive its CRC
        vm.prank(gnosisMembers[3]);
        IHub(HUB).trust(group, type(uint96).max);

        // use the source's on-chain CRC balance for the flow
        uint256 sourceBalance = IHub(HUB).balanceOf(gnosisMembers[0], uint256(uint160(gnosisMembers[0])));
        require(sourceBalance > 0, "source has no CRC on fork");
        require(sourceBalance <= type(uint192).max, "balance exceeds uint192");
        uint192 crcAmount = uint192(sourceBalance);

        // ===================== Construct parameter for operateFlowMatrix =====================

        // gnosisMembers[0] --gnosisMembers[0]CRC--> router --gnosisMembers[0]CRC--> group --groupCRC--> gnosisMembers[3]

        TypeDefinitions.FlowEdge[] memory flowEdges = new TypeDefinitions.FlowEdge[](3);
        TypeDefinitions.Stream[] memory streams = new TypeDefinitions.Stream[](1);
        bytes memory packCoordinate;
        address[] memory flowVertices = new address[](4); // source, router, group, sink
        flowVertices[0] = gnosisMembers[0];
        flowVertices[1] = address(router);
        flowVertices[2] = address(group);
        flowVertices[3] = gnosisMembers[3];
        uint16[] memory indexes;
        (flowVertices, indexes) = _sortWithMapping(flowVertices);

        flowEdges[0] = TypeDefinitions.FlowEdge({streamSinkId: uint16(0), amount: crcAmount});
        flowEdges[1] = TypeDefinitions.FlowEdge({streamSinkId: uint16(0), amount: crcAmount});
        flowEdges[2] = TypeDefinitions.FlowEdge({streamSinkId: uint16(1), amount: crcAmount});

        uint16[] memory flowEdgeIds = new uint16[](1);
        flowEdgeIds[0] = uint16(2); // last flowEdge is the terminating edge

        streams[0] = TypeDefinitions.Stream({
            sourceCoordinate: indexes[0], // gnosisMembers[0]
            flowEdgeIds: flowEdgeIds,
            data: bytes("")
        });

        uint16[] memory coords = new uint16[]((flowEdges.length) * 3);

        // gnosisMembers[0] --gnosisMembers[0]CRC--> router
        coords[0] = uint16(indexes[0]);
        coords[1] = uint16(indexes[0]);
        coords[2] = uint16(indexes[1]);

        // router --gnosisMembers[0]CRC--> group
        coords[3] = uint16(indexes[0]);
        coords[4] = uint16(indexes[1]);
        coords[5] = uint16(indexes[2]);

        // group --groupCRC--> gnosisMembers[3]
        coords[6] = uint16(indexes[2]);
        coords[7] = uint16(indexes[2]);
        coords[8] = uint16(indexes[3]);

        packCoordinate = _packCoordinates(coords);

        uint256[] memory collateral = new uint256[](1);
        collateral[0] = uint256(uint160(gnosisMembers[0]));
        uint256[] memory groupMintAmount = new uint256[](1);
        groupMintAmount[0] = crcAmount;

        // ===================== call operateFlowMatrix =====================
        vm.prank(gnosisMembers[0]);
        vm.expectEmit();
        emit GroupMint(address(router), address(group), address(group), collateral, groupMintAmount);
        IHub(HUB).operateFlowMatrix(flowVertices, flowEdges, streams, packCoordinate);

        assertEq(IHub(HUB).balanceOf(gnosisMembers[3], uint256(uint160(address(group)))), crcAmount);
    }

    function testOperateFlowMatrixWithRouter() public {
        // gnosisMembers[0] --gnosisMembers[0]CRC--> gnosisMembers[1] --gnosisMembers[0]CRC--> router --gnosisMembers[0]CRC--> group --groupCRC--> gnosisMembers[3]

        // ============================== Enable CRC For Routing ==============================
        vm.prank(routerAdmin);
        router.enableCRCForRouting(gnosisMembers);

        // ============================== Configure Group Trust ==============================
        // Group trusts gnosisMembers[0] so its personal CRC is accepted as collateral.
        vm.prank(owner);
        BaseGroup(group).trust(gnosisMembers[0], type(uint96).max);

        // gnosisMembers[1] must trust gnosisMembers[0] so it can receive gnosisMembers[0]CRC.
        vm.prank(gnosisMembers[1]);
        IHub(HUB).trust(gnosisMembers[0], type(uint96).max);

        // gnosisMembers[1] approves gnosisMembers[0] as operator so the same flow call
        // can also send gnosisMembers[0]CRC out of gnosisMembers[1] toward the router.
        vm.prank(gnosisMembers[1]);
        IHub(HUB).setApprovalForAll(gnosisMembers[0], true);

        // sink (gnosisMembers[3]) must trust the new group to receive its CRC.
        vm.prank(gnosisMembers[3]);
        IHub(HUB).trust(group, type(uint96).max);

        // use the source's on-chain CRC balance for the flow
        uint256 sourceBalance = IHub(HUB).balanceOf(gnosisMembers[0], uint256(uint160(gnosisMembers[0])));
        require(sourceBalance > 0, "source has no CRC on fork");
        require(sourceBalance <= type(uint192).max, "balance exceeds uint192");
        uint192 crcAmount = uint192(sourceBalance);

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

        // ===================== call operateFlowMatrix =====================
        vm.prank(gnosisMembers[0]);
        vm.expectEmit();
        emit GroupMint(address(router), address(group), address(group), collateral, groupMintAmount);
        IHub(HUB).operateFlowMatrix(flowVertices, flowEdges, streams, packCoordinate);

        assertEq(IHub(HUB).balanceOf(gnosisMembers[3], uint256(uint160(address(group)))), crcAmount);
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
