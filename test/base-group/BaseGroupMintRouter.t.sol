// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import "forge-std/StdCheats.sol";
import {Test, console} from "forge-std/Test.sol";
import "circles-contracts-v2/hub/TypeDefinitions.sol";
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

        // Register 2 new human: 1 as sourceAvatar and 1 as sinkAvatar
        // group only trust sourceAvatar token
        // sinkAvatar only receive group token

        sourceAvatar = makeAddr("sourceAvatar");
        sinkAvatar = makeAddr("sinkAvatar");

        // register avatars as human
        _registerHuman(sourceAvatar);
        _registerHuman(sinkAvatar);
        _setOperatorApproval(sourceAvatar, sourceAvatar);
        _setOperatorApproval(sinkAvatar, sinkAvatar);

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
    }

    /**
     * @notice Tests the core functionality of the mint router.
     * @dev This test verifies that a group mint can be successfully executed when the group
     * acts as an intermediate node in a flow matrix operation. It simulates a flow from a
     * source avatar, through the router, to the group, and finally to a sink avatar.
     * @param crcAmount The amount of CRC to be used in the flow.
     */
    function testRouter(uint192 crcAmount) public {
        vm.assume(crcAmount > 0);
        _setCRCBalance(uint256(uint160(sourceAvatar)), sourceAvatar, today, crcAmount);

        // Construct parameter for operateFlowMatrix

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
            sourceCoordinate: indexes[0], // group -> sinkAvatar
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

        vm.prank(sourceAvatar);
        vm.expectEmit();
        emit GroupMint(address(router), address(group), address(group), collateral, groupMintAmount);
        HUB_V2.operateFlowMatrix(flowVertices, flowEdges, streams, packCoordinate);

        assertEq(HUB_V2.balanceOf(sinkAvatar, uint256(uint160(address(baseGroup)))), crcAmount);
    }

    /**
     * @notice Tests the disabling of a CRC for routing.
     * @dev Verifies that the router admin can disable a previously enabled CRC,
     * which results in the router no longer trusting the specified CRC token.
     * @param crc The address of the CRC token to disable.
     */
    function testDisableCRCForRouter(address crc) public {
        vm.assume(crc != address(0) && crc!= SENTINEL);
        vm.assume(HUB_V2.isTrusted(address(router), crc) == false);

        _setTrust(address(router), crc);

        address[] memory crcArray = new address[](1);
        crcArray[0] = crc;
        vm.prank(routerAdmin);

        router.disableCRCForRouting(crcArray);

        // set trust to 0 will set to block.timestamp, hence require for to warp to next block to allow trust = false
        vm.warp(block.timestamp + 1);
        assertEq(HUB_V2.isTrusted(address(router), crc), false);
        assertFalse(HUB_V2.isApprovedForAll(address(router), crc));
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

    /**
     * @notice Tests the conditions for enabling CRC for routing.
     * @dev This test checks various scenarios for the `enableCRCForRouting` function, including:
     * - Reverting if the router is frozen.
     * - Reverting if the group is not a valid base group.
     * - Reverting if the CRC address is not a registered human.
     * - Handling cases where the group trusts or does not trust the CRC.
     * @param _frozen A boolean to simulate the router's frozen state.
     * @param _baseGroup The address of the base group.
     * @param _crc The address of the CRC token to enable.
     */
    function testEnableCRCForRouting(bool _frozen, address _baseGroup, address _crc) public {
        vm.assume(_crc != address(0) && _crc!= SENTINEL);
        vm.assume(_baseGroup != address(0) && _baseGroup!= SENTINEL);
        address[] memory crcArray = new address[](1);
        crcArray[0] = _crc;
        if (_frozen) {
            vm.expectRevert();
            router.enableCRCForRouting(_baseGroup, crcArray);
        }
        _frozen = false;
        if (!baseGroupFactory.deployedByFactory(_baseGroup)) {
            vm.expectRevert();
            router.enableCRCForRouting(_baseGroup, crcArray);
        }

        if (!HUB_V2.isHuman(_crc)) {
            vm.expectRevert();
            // enable routing for base group which is created in the setUp()
            router.enableCRCForRouting(address(baseGroup), crcArray);
            _registerHuman(_crc);
        }

        if (!HUB_V2.isTrusted(address(baseGroup), _crc)) {
            // If group don't trust crc, calling enableCRCForRouting will not change the trust relationship
            vm.prank(routerAdmin);
            router.enableCRCForRouting(address(baseGroup), crcArray);
            assertFalse(HUB_V2.isTrusted(address(router), _crc));
        } else {
            vm.prank(routerAdmin);
            router.enableCRCForRouting(address(baseGroup), crcArray);
            assertTrue(HUB_V2.isTrusted(address(router), _crc));
        }
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
