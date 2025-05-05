// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "forge-std/StdCheats.sol";
import "circles-contracts-v2/hub/Hub.sol";
import "circles-contracts-v2/hub/IHub.sol";
import "circles-contracts-v2/hub/TypeDefinitions.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {FlowMatrixGenerator} from "test/base-group/helpers/FlowMatrixGenerator.sol";
import {BaseTreasury} from "src/base-group/BaseTreasury.sol";
import {BaseMintHandler} from "src/base-group/BaseMintHandler.sol";
import {BaseGroup} from "src/base-group/BaseGroup.sol";
import {BaseGroupFactory} from "src/base-group/BaseGroupFactory.sol";

/// @dev Need to move from fork into mock mode. Mock mode requires HubMock, specific requirements will be added later.
contract MintRedemptionFlowTest is Test, FlowMatrixGenerator {
    address deployer = makeAddr("deployer");
    // Fork id for Gnosis chain
    uint256 gnosisFork;

    // Hub instance (the fork uses the real deployed Hub)
    Hub hub = Hub(HUB);

    // Factory for base group
    BaseGroupFactory baseGroupFactory;

    // The deployed base group (for our test group)
    BaseGroup baseGroup;
    address group;
    uint256 groupTokenId;
    address mintHandler;
    address treasury;

    address demurrage;
    address inflationary;

    uint64 today;

    function setUp() public {
        // Fork Gnosis chain using RPC URL in environment variable (e.g., GNOSIS_RPC)
        string memory rpcUrl = vm.envString("GNOSIS_RPC");
        gnosisFork = vm.createFork(rpcUrl);
        vm.selectFork(gnosisFork);

        // setup Hub today
        today = hub.day(block.timestamp);

        // Deploy BaseGroupFactory
        baseGroupFactory = new BaseGroupFactory();

        // Deploy a BaseGroup instance using the factory.
        // In our factory, the createBaseGroup() function requires:
        // _owner, _service, _feeCollection, _initialConditions, _name, _symbol, _metadataDigest.
        address owner = makeAddr("owner");
        address service = makeAddr("service");
        address feeCollection = makeAddr("feeCollection");
        address[] memory initialConditions;
        string memory groupName = "TestGroup";
        string memory groupSymbol = "TG";
        bytes32 metadataDigest = keccak256(abi.encodePacked("metadata"));

        // Let the deployer create the group.
        vm.prank(deployer);
        (group, mintHandler, treasury) = baseGroupFactory.createBaseGroup(
            owner, service, feeCollection, initialConditions, groupName, groupSymbol, metadataDigest
        );

        baseGroup = BaseGroup(group);
        groupTokenId = uint256(uint160(group));

        demurrage = BaseMintHandler(mintHandler).DEMURRAGE();
        inflationary = BaseMintHandler(mintHandler).INFLATIONARY();

        // Now the BaseGroup is deployed and registered in the Hub.
        // Optionally, call functions to set additional parameters on the group.
    }

    // -------------------------------------------------------------------------
    // Test Flow 1: Group Mint via operateFlowMatrix (Single collateral)
    // -------------------------------------------------------------------------
    function testGroupMintSingleFlow(uint256 totalAmount) public {
        // Generate flow matrix based on mint handler as path destination and fuzzed: amount.
        (
            address sourceAvatar,
            address[] memory flowVertices,
            TypeDefinitions.FlowEdge[] memory flowEdges,
            TypeDefinitions.Stream[] memory streams,
            uint256[] memory redemptionIds,
            uint256[] memory redemptionAmounts,
            bytes memory packedCoordinates
        ) = generateFlowMatrix(
            totalAmount, // min 100, max 10_000
            1, // one terminal edge, equal one collateral id
            today, // from block state
            [group, mintHandler] // testing constants: group and mintHandler
        );

        // Sanity check single flow - single collateral
        assertEq(redemptionIds.length, 1, "Sanity check failed: generateFlowMatrix");
        assertEq(redemptionAmounts.length, 1, "Sanity check failed: generateFlowMatrix");

        // Hub calls the appropriate handler (mintHandler) as destination.
        // Impersonate source avatar to call the operateFlowMatrix function.
        vm.prank(sourceAvatar);
        hub.operateFlowMatrix(flowVertices, flowEdges, streams, packedCoordinates);

        // At this point, the Hub (via the mintHandler) should have minted group CRC (gCRC)
        // and transferred them to the source avatar.
        // Check that source avatar now has a balance of group CRC.
        uint256 sourceAvatarBalance = hub.balanceOf(sourceAvatar, groupTokenId);
        assertEq(
            sourceAvatarBalance,
            _polishFuzzedTotalAmount(totalAmount),
            "Source avatar should receive total amount of group CRC"
        );

        // Check single collateral balance of treasury
        assertEq(
            redemptionAmounts[0],
            hub.balanceOf(treasury, redemptionIds[0]),
            "Collateral balance hold by treasury does not match"
        );
    }

    // -------------------------------------------------------------------------
    // Test Flow 2: Group Mint and return Demmurage ERC20 gCRC (Single collateral)
    // -------------------------------------------------------------------------
    function testERC20DemmurageGroupMintSingleFlow(uint256 totalAmount) public {
        // Generate flow matrix based on mint handler as path destination and fuzzed: amount.
        (
            address sourceAvatar,
            address[] memory flowVertices,
            TypeDefinitions.FlowEdge[] memory flowEdges,
            TypeDefinitions.Stream[] memory streams,
            uint256[] memory redemptionIds,
            uint256[] memory redemptionAmounts,
            bytes memory packedCoordinates
        ) = generateFlowMatrix(
            totalAmount, // min 100, max 10_000
            1, // one terminal edge, equal one collateral id
            today, // from block state
            [group, mintHandler] // testing constants: group and mintHandler
        );

        // Add data to the stream and specify it as Demmurage separator
        streams[0].data = hex"f3f5858942140fd2894eeb8b74cd0ed72d24fc6675d352a2884b1be2f32256fe";

        // Sanity check single flow - single collateral
        assertEq(redemptionIds.length, 1, "Sanity check failed: generateFlowMatrix");
        assertEq(redemptionAmounts.length, 1, "Sanity check failed: generateFlowMatrix");

        // Hub calls the appropriate handler (mintHandler) as destination.
        // Impersonate source avatar to call the operateFlowMatrix function.
        vm.prank(sourceAvatar);
        hub.operateFlowMatrix(flowVertices, flowEdges, streams, packedCoordinates);

        // At this point, the Hub (via the mintHandler) should have minted group CRC (gCRC)
        // wrap ERC1155 to Demurrage ERC20 and transferred ERC20 to the source avatar.
        // Check that source avatar now has a balance of ERC20 group CRC.

        assertEq(hub.balanceOf(sourceAvatar, groupTokenId), 0, "Source avatar should not receive group CRC as ERC1155");

        assertEq(
            IERC20(demurrage).balanceOf(sourceAvatar),
            _polishFuzzedTotalAmount(totalAmount),
            "Source avatar should receive group CRC as ERC20 demurrage"
        );

        // Check single collateral balance of treasury
        assertEq(
            redemptionAmounts[0],
            hub.balanceOf(treasury, redemptionIds[0]),
            "Collateral balance hold by treasury does not match"
        );
    }

    // -------------------------------------------------------------------------
    // Test Flow 3: Group Mint and return Inflationary ERC20 gCRC (Single collateral)
    // -------------------------------------------------------------------------
    function testERC20InflationaryGroupMintSingleFlow(uint256 totalAmount) public {
        // Generate flow matrix based on mint handler as path destination and fuzzed: amount.
        (
            address sourceAvatar,
            address[] memory flowVertices,
            TypeDefinitions.FlowEdge[] memory flowEdges,
            TypeDefinitions.Stream[] memory streams,
            uint256[] memory redemptionIds,
            uint256[] memory redemptionAmounts,
            bytes memory packedCoordinates
        ) = generateFlowMatrix(
            totalAmount, // min 100, max 10_000
            1, // one terminal edge, equal one collateral id
            today, // from block state
            [group, mintHandler] // testing constants: group and mintHandler
        );

        // Add data to the stream and specify it as Inflationary separator
        streams[0].data = hex"9d28938b56c0e8aae8dd05e12461cbabf8f699236c3fd7c54c7d3bb9fb443ed2";

        // Sanity check single flow - single collateral
        assertEq(redemptionIds.length, 1, "Sanity check failed: generateFlowMatrix");
        assertEq(redemptionAmounts.length, 1, "Sanity check failed: generateFlowMatrix");

        // Hub calls the appropriate handler (mintHandler) as destination.
        // Impersonate source avatar to call the operateFlowMatrix function.
        vm.prank(sourceAvatar);
        hub.operateFlowMatrix(flowVertices, flowEdges, streams, packedCoordinates);

        // At this point, the Hub (via the mintHandler) should have minted group CRC (gCRC)
        // wrap ERC1155 to Inflationary ERC20 and transferred ERC20 to the source avatar.
        // Check that source avatar now has a balance of ERC20 group CRC.

        assertEq(hub.balanceOf(sourceAvatar, groupTokenId), 0, "Source avatar should not receive group CRC as ERC1155");

        assertEq(
            IERC20(inflationary).balanceOf(sourceAvatar),
            hub.convertDemurrageToInflationaryValue(_polishFuzzedTotalAmount(totalAmount), today),
            "Source avatar should receive group CRC as ERC20 inflationary"
        );

        // Check single collateral balance of treasury
        assertEq(
            redemptionAmounts[0],
            hub.balanceOf(treasury, redemptionIds[0]),
            "Collateral balance hold by treasury does not match"
        );
    }

    // -------------------------------------------------------------------------
    // Test Flow 4: Batch Group Mint Flow (multiple collaterals)
    // -------------------------------------------------------------------------
    function testGroupMintBatchFlow(uint256 totalAmount, uint256 numberOfTerminatedEdges) public {
        // Generate flow matrix based on mint handler as path destination and fuzzed: amount and number of terminal edges,
        // which are in range from 1 to 10. 3 intermidiate vertices per flow.
        (
            address sourceAvatar,
            address[] memory flowVertices,
            TypeDefinitions.FlowEdge[] memory flowEdges,
            TypeDefinitions.Stream[] memory streams,
            uint256[] memory redemptionIds,
            uint256[] memory redemptionAmounts,
            bytes memory packedCoordinates
        ) = generateFlowMatrix(
            totalAmount, // min 100, max 10_000
            numberOfTerminatedEdges, // fuzz from 1 to 10, also equal number of collateral ids for now
            today, // from block state
            [group, mintHandler] // constants: group and mintHandler
        );

        // Hub calls the appropriate handler (mintHandler) as destination.
        // Impersonate source avatar to call the operateFlowMatrix function.
        vm.prank(sourceAvatar);
        hub.operateFlowMatrix(flowVertices, flowEdges, streams, packedCoordinates);

        // At this point, the Hub (via the mintHandler) should have minted group CRC (gCRC)
        // and transferred them to the source avatar.
        // Check that source avatar now has a balance of group CRC.
        uint256 sourceAvatarBalance = hub.balanceOf(sourceAvatar, groupTokenId);
        assertEq(
            sourceAvatarBalance,
            _polishFuzzedTotalAmount(totalAmount),
            "Source avatar should receive total amount of group CRC"
        );

        // Check collateral balances of treasury
        for (uint256 i; i < redemptionIds.length;) {
            assertEq(
                redemptionAmounts[i],
                hub.balanceOf(treasury, redemptionIds[i]),
                "Collateral balances hold by treasury does not match"
            );
            unchecked {
                ++i;
            }
        }
    }

    // -------------------------------------------------------------------------
    // Test Flow 5: Batch Group Mint Flow and return Demmurage ERC20 gCRC (multiple collaterals)
    // -------------------------------------------------------------------------
    function testERC20DemmurageGroupMintBatchFlow(uint256 totalAmount, uint256 numberOfTerminatedEdges) public {
        // Generate flow matrix based on mint handler as path destination and fuzzed: amount and number of terminal edges,
        // which are in range from 1 to 10. 3 intermidiate vertices per flow.
        (
            address sourceAvatar,
            address[] memory flowVertices,
            TypeDefinitions.FlowEdge[] memory flowEdges,
            TypeDefinitions.Stream[] memory streams,
            uint256[] memory redemptionIds,
            uint256[] memory redemptionAmounts,
            bytes memory packedCoordinates
        ) = generateFlowMatrix(
            totalAmount, // min 100, max 10_000
            numberOfTerminatedEdges, // fuzz from 1 to 10, also equal number of collateral ids for now
            today, // from block state
            [group, mintHandler] // constants: group and mintHandler
        );

        // Add data to the stream and specify it as Demmurage separator
        streams[0].data = hex"f3f5858942140fd2894eeb8b74cd0ed72d24fc6675d352a2884b1be2f32256fe";

        // Hub calls the appropriate handler (mintHandler) as destination.
        // Impersonate source avatar to call the operateFlowMatrix function.
        vm.prank(sourceAvatar);
        hub.operateFlowMatrix(flowVertices, flowEdges, streams, packedCoordinates);

        // At this point, the Hub (via the mintHandler) should have minted group CRC (gCRC)
        // wrap ERC1155 to Demurrage ERC20 and transferred ERC20 to the source avatar.
        // Check that source avatar now has a balance of ERC20 group CRC.
        assertEq(hub.balanceOf(sourceAvatar, groupTokenId), 0, "Source avatar should not receive group CRC as ERC1155");

        assertEq(
            IERC20(demurrage).balanceOf(sourceAvatar),
            _polishFuzzedTotalAmount(totalAmount),
            "Source avatar should receive group CRC as ERC20 demurrage"
        );

        // Check collateral balances of treasury
        for (uint256 i; i < redemptionIds.length;) {
            assertEq(
                redemptionAmounts[i],
                hub.balanceOf(treasury, redemptionIds[i]),
                "Collateral balances hold by treasury does not match"
            );
            unchecked {
                ++i;
            }
        }
    }

    // -------------------------------------------------------------------------
    // Test Flow 6: Batch Group Mint Flow and return Inflationary ERC20 gCRC (multiple collaterals)
    // -------------------------------------------------------------------------
    function testERC20InflationaryGroupMintBatchFlow(uint256 totalAmount, uint256 numberOfTerminatedEdges) public {
        // Generate flow matrix based on mint handler as path destination and fuzzed: amount and number of terminal edges,
        // which are in range from 1 to 10. 3 intermidiate vertices per flow.
        (
            address sourceAvatar,
            address[] memory flowVertices,
            TypeDefinitions.FlowEdge[] memory flowEdges,
            TypeDefinitions.Stream[] memory streams,
            uint256[] memory redemptionIds,
            uint256[] memory redemptionAmounts,
            bytes memory packedCoordinates
        ) = generateFlowMatrix(
            totalAmount, // min 100, max 10_000
            numberOfTerminatedEdges, // fuzz from 1 to 10, also equal number of collateral ids for now
            today, // from block state
            [group, mintHandler] // constants: group and mintHandler
        );

        // Add data to the stream and specify it as Inflationary separator
        streams[0].data = hex"9d28938b56c0e8aae8dd05e12461cbabf8f699236c3fd7c54c7d3bb9fb443ed2";

        // Hub calls the appropriate handler (mintHandler) as destination.
        // Impersonate source avatar to call the operateFlowMatrix function.
        vm.prank(sourceAvatar);
        hub.operateFlowMatrix(flowVertices, flowEdges, streams, packedCoordinates);

        // At this point, the Hub (via the mintHandler) should have minted group CRC (gCRC)
        // wrap ERC1155 to Inflationary ERC20 and transferred ERC20 to the source avatar.
        // Check that source avatar now has a balance of ERC20 group CRC.
        assertEq(hub.balanceOf(sourceAvatar, groupTokenId), 0, "Source avatar should not receive group CRC as ERC1155");

        assertEq(
            IERC20(inflationary).balanceOf(sourceAvatar),
            hub.convertDemurrageToInflationaryValue(_polishFuzzedTotalAmount(totalAmount), today),
            "Source avatar should receive group CRC as ERC20 inflationary"
        );

        // Check collateral balances of treasury
        for (uint256 i; i < redemptionIds.length;) {
            assertEq(
                redemptionAmounts[i],
                hub.balanceOf(treasury, redemptionIds[i]),
                "Collateral balances hold by treasury does not match"
            );
            unchecked {
                ++i;
            }
        }
    }

    // -------------------------------------------------------------------------
    // Test Flow 7: Redemption Flow
    // -------------------------------------------------------------------------

    function testGroupRedemptionFlow(uint256 totalAmount, uint256 numberOfTerminatedEdges) public {
        // -------------------------------------------------------------------------
        // Stage 1: Set working state by making batch of mints
        // -------------------------------------------------------------------------

        // Generate flow matrix based on mint handler as path destination and fuzzed: amount and number of terminal edges,
        // which are in range from 1 to 10. 3 intermidiate vertices per flow.
        (
            address sourceAvatar,
            address[] memory flowVertices,
            TypeDefinitions.FlowEdge[] memory flowEdges,
            TypeDefinitions.Stream[] memory streams,
            uint256[] memory redemptionIds,
            uint256[] memory redemptionAmounts,
            bytes memory packedCoordinates
        ) = generateFlowMatrix(
            totalAmount, // min 100, max 10_000
            numberOfTerminatedEdges, // fuzz from 1 to 10, also equal number of collateral ids for now
            today, // from block state
            [group, mintHandler] // constants: group and mintHandler
        );

        // Hub calls the appropriate handler (mintHandler) as destination.
        // Impersonate source avatar to call the operateFlowMatrix function.
        vm.prank(sourceAvatar);
        hub.operateFlowMatrix(flowVertices, flowEdges, streams, packedCoordinates);

        // At this point, the Hub (via the mintHandler) should have minted group CRC (gCRC)
        // and transferred them to the source avatar.
        // Check that source avatar now has a balance of group CRC.
        uint256 sourceAvatarBalance = hub.balanceOf(sourceAvatar, groupTokenId);
        assertEq(
            sourceAvatarBalance,
            _polishFuzzedTotalAmount(totalAmount),
            "Source avatar should receive total amount of group CRC"
        );

        // Check collateral balances of treasury
        for (uint256 i; i < redemptionIds.length;) {
            assertEq(
                redemptionAmounts[i],
                hub.balanceOf(treasury, redemptionIds[i]),
                "Collateral balances hold by treasury does not match"
            );
            unchecked {
                ++i;
            }
        }

        // -------------------------------------------------------------------------
        // Stage 2: Try out redemption via path
        // -------------------------------------------------------------------------
        // source gCRC -> treasury -> receiver ids[0]
        uint256 id = redemptionIds[0];
        uint256 amount = redemptionAmounts[0] / 2;
        address receiver = makeAddr("receiver");
        _registerHuman(receiver);
        _setTrust(receiver, address(uint160(id)));

        flowVertices = new address[](5); // source, group, treasury, id, receiver
        flowVertices[0] = sourceAvatar;
        flowVertices[1] = group;
        flowVertices[2] = treasury;
        flowVertices[3] = address(uint160(id));
        flowVertices[4] = receiver;
        uint16[] memory indexes;
        (flowVertices, indexes) = sortWithMapping(flowVertices);
        {
            // generate packedCoordinates
            uint16[] memory coords = new uint16[](6); // 2 edges: from source to treasury, from treasury to receiver
            coords[0] = indexes[1]; // id   (edge 0) // gCRC
            coords[1] = indexes[0]; // from (edge 0) // source
            coords[2] = indexes[2]; // to   (edge 0) // treasury
            coords[3] = indexes[3]; // id   (edge 1) // id
            coords[4] = indexes[2]; // from (edge 1) // treasury
            coords[5] = indexes[4]; // to   (edge 1) // receiver
            packedCoordinates = _packCoordinates(coords);
        }
        {
            // generate flow edges
            flowEdges = new TypeDefinitions.FlowEdge[](2);
            flowEdges[0] = TypeDefinitions.FlowEdge({streamSinkId: 0, amount: uint192(amount)});
            flowEdges[1] = TypeDefinitions.FlowEdge({streamSinkId: 1, amount: uint192(amount)});
        }
        {
            // generate streams
            streams = new TypeDefinitions.Stream[](1);

            streams[0] = TypeDefinitions.Stream({sourceCoordinate: indexes[0], flowEdgeIds: new uint16[](1), data: ""});
            streams[0].flowEdgeIds[0] = uint16(1);
        }

        vm.prank(sourceAvatar);
        hub.operateFlowMatrix(flowVertices, flowEdges, streams, packedCoordinates);

        // check balance changes
        // source
        /*
        // stack too deep
        assertEq(
                _polishFuzzedTotalAmount(totalAmount) - amount,
                hub.balanceOf(sourceAvatar, groupTokenId),
                "Source avatar should spend amount of gCRC"
        );
        */
        // treasury
        assertEq(amount, hub.balanceOf(treasury, groupTokenId), "Treasury should receive amount of gCRC");
        assertEq(redemptionAmounts[0] - amount, hub.balanceOf(treasury, id), "Treasury should transfer amount of id");
        // receiver
        //assertApproxEqAbs(amount, hub.balanceOf(vault, id), 1, "Receiver should receive amount of id"); // TODO: check why receiver balance - amount = 1
        assertEq(amount, hub.balanceOf(receiver, id), "Receiver should receive amount of id");

        // -------------------------------------------------------------------------
        // Stage 3: Burn treasury gCRC balance
        // -------------------------------------------------------------------------

        // now lets try to burn gCRC
        BaseTreasury(treasury).burn();
        // check balance changes
        assertEq(0, hub.balanceOf(treasury, groupTokenId), "Treasury balance of gCRC should be burned");
    }

    // TODO: for next redemption flow test we need to set extra collateral (attempt to redeem different).

    // Internal helpers

    /// @notice Sorts an array of addresses in ascending order
    ///         and returns both the sorted array and a mapping (as an array)
    ///         that indicates the original index for each sorted element.
    /// @param arr The array of addresses to sort.
    /// @return sortedAddresses The sorted array of addresses.
    /// @return indexes An array where each element is the original index
    ///         of the corresponding address in the sorted array.
    function sortWithMapping(address[] memory arr)
        public
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
}
