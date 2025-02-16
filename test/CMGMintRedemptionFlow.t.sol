// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "forge-std/StdCheats.sol";
import "circles-contracts-v2/hub/Hub.sol";
import "src/core-members-group/CoreMembersGroup.sol";
import "src/core-members-group/helpers/CMGroupDeployer.sol";
import {FlowMatrixGenerator} from "test/helpers/FlowMatrixGenerator.sol";
import "circles-contracts-v2/hub/TypeDefinitions.sol";

/// @dev Need to move from fork into mock mode. Mock mode requires HubMock and StandardTreasuryMock, specific requirements will be added later.
contract CMGMintRedemptionFlowTest is Test, FlowMatrixGenerator {
    address deployer = makeAddr("deployer");
    // Fork id for Gnosis chain
    uint256 gnosisFork;

    // Hub instance (the fork uses the real deployed Hub)
    Hub hub = Hub(HUB);
    // StandardTreasury instance (interface declared inside src/circles/IStandardTreasury; inhereted by CoreMembersGroup).
    IStandardTreasury standardTreasury = IStandardTreasury(address(0x08F90aB73A515308f03A718257ff9887ED330C6e));

    // Deployer for CoreMembersGroup
    CMGroupDeployer cmgDeployer;

    // The deployed CoreMembersGroup proxy (for our test group)
    address groupProxy;
    CoreMembersGroup coreMembersGroup;
    uint256 groupTokenId;
    address vault;

    uint64 today;
    address mintHandler;
    address redemptionHandler;

    function setUp() public {
        // Fork Gnosis chain using RPC URL in environment variable (e.g., GNOSIS_RPC)
        string memory rpcUrl = vm.envString("GNOSIS_RPC");
        gnosisFork = vm.createFork(rpcUrl);
        vm.selectFork(gnosisFork);

        // Deploy the CMGroupDeployer (which deploys the CoreMembersGroup master copy)
        cmgDeployer = new CMGroupDeployer();

        // setup Hub today
        today = hub.day(block.timestamp);

        // Deploy a CoreMembersGroup instance using the deployer.
        // In our deployer, the createCMGroup() function requires:
        // _service, _name, _symbol, _metadataDigest.
        address service = makeAddr("service");
        address[] memory _initialConditions;
        string memory groupName = "TestGroup";
        string memory groupSymbol = "TG";
        bytes32 metadataDigest = keccak256(abi.encodePacked("metadata"));

        // Let the deployer create the group; msg.sender in this call will be the group owner.
        vm.prank(deployer);
        groupProxy = cmgDeployer.createCMGroup(service, _initialConditions, groupName, groupSymbol, metadataDigest);
        coreMembersGroup = CoreMembersGroup(groupProxy);
        groupTokenId = uint256(uint160(address(coreMembersGroup)));
        mintHandler = coreMembersGroup.mintHandler();
        redemptionHandler = coreMembersGroup.redemptionHandler();

        // Now the CoreMembersGroup is deployed and registered in the Hub.
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
            [groupProxy, mintHandler] // testing constants: group and mintHandler
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

        // As we are testing against groups utilizing StandardTreasury, we can have extra effect check - collateral balance of vault.
        // Get vault
        vault = standardTreasury.vaults(groupProxy);
        // Check single collateral balance of vault
        assertEq(
            redemptionAmounts[0],
            hub.balanceOf(vault, redemptionIds[0]),
            "Collateral balance hold by vault does not match"
        );
    }

    // -------------------------------------------------------------------------
    // Test Flow 2: Batch Group Mint Flow (multiple collaterals)
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
            [groupProxy, mintHandler] // constants: group and mintHandler
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

        // As we are testing against groups utilizing StandardTreasury, we can have extra effect check - collateral balances of vault.
        // Get vault
        vault = standardTreasury.vaults(groupProxy);
        // Check collateral balances of vault
        for (uint256 i; i < redemptionIds.length;) {
            assertEq(
                redemptionAmounts[i],
                hub.balanceOf(vault, redemptionIds[i]),
                "Collateral balances hold by vault does not match"
            );
            unchecked {
                ++i;
            }
        }
    }

    // -------------------------------------------------------------------------
    // Test Flow 3: Redemption Flow
    // -------------------------------------------------------------------------
    function testGroupRedemptionFlow(uint256 totalAmount, uint256 numberOfTerminatedEdges) public {
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
            [groupProxy, mintHandler] // constants: group and mintHandler
        );

        // Hub calls the appropriate handler (mintHandler) as destination.
        // Impersonate source avatar to call the operateFlowMatrix function.
        vm.prank(sourceAvatar);
        hub.operateFlowMatrix(flowVertices, flowEdges, streams, packedCoordinates);

        // At this point, the Hub (via the mintHandler) should have minted group CRC (gCRC)
        // and transferred them to the source avatar.

        // At the same time collateral should be holded by either group treasury or vault (in case StandardTreasury).

        // Now source avatar friend should call operateFlowMatrix with crafted redemption data and redemption handler as destination.
        // Lets craft input for this call.
        // TODO: implement simple generateFlowMatrix function for such case (without group trust collateral and with data for stream)
        // TODO: even better to refactor existing one into more generic, so it generates matrix flow for such case - one terminated edge:
        //       id - groupCRC, from - source avatar, to - redemptionHandler; and few intermediate edges in one stream. kind of insert terminated id and from.
        // temporary build simple stream with one flow
        address sourceAvatarFriend = address(uint160(sourceAvatar) - MAX_ADDRESS_OFFSET);
        // set friend state
        _setSourceState(sourceAvatarFriend, today, _polishFuzzedTotalAmount(totalAmount));
        // set trust connection
        _setTrust(sourceAvatar, sourceAvatarFriend);
        flowVertices = new address[](4); // friend, source, group, redemptionHandler
        flowVertices[0] = sourceAvatarFriend;
        flowVertices[1] = sourceAvatar;
        flowVertices[2] = groupProxy;
        flowVertices[3] = redemptionHandler;
        uint16[] memory indexes;
        (flowVertices, indexes) = sortWithMapping(flowVertices);
        {
            // generate packedCoordinates
            uint16[] memory coords = new uint16[](6); // 2 edges: from friend to source, from source to redemptionHandler
            coords[0] = indexes[0]; // id   (edge 0)
            coords[1] = indexes[0]; // from (edge 0)
            coords[2] = indexes[1]; // to   (edge 0)
            coords[3] = indexes[2]; // id   (edge 1)
            coords[4] = indexes[1]; // from (edge 1)
            coords[5] = indexes[3]; // to   (edge 1)
            packedCoordinates = _packCoordinates(coords);
        }
        {
            // generate flow edges
            flowEdges = new TypeDefinitions.FlowEdge[](2);
            flowEdges[0] =
                TypeDefinitions.FlowEdge({streamSinkId: 0, amount: uint192(_polishFuzzedTotalAmount(totalAmount))});
            flowEdges[1] =
                TypeDefinitions.FlowEdge({streamSinkId: 1, amount: uint192(_polishFuzzedTotalAmount(totalAmount))});
        }
        {
            // generate streams
            streams = new TypeDefinitions.Stream[](1);
            // As we are testing against groups utilizing StandardTreasury. Lets try to specify our redemption intent.

            // Encode redemption policy data.
            bytes memory userData =
                abi.encode(BaseMintPolicyDefinitions.BaseRedemptionPolicy(redemptionIds, redemptionAmounts));
            // Pack into Metadata struct (similar encoding as in protocol contracts).
            bytes32 METADATATYPE_GROUPREDEEM = keccak256("CIRCLESv2:RESERVED_DATA:CirclesGroupRedeem");
            bytes memory redemptionData = abi.encode(TypeDefinitions.Metadata(METADATATYPE_GROUPREDEEM, "", userData));
            streams[0] = TypeDefinitions.Stream({
                sourceCoordinate: indexes[0],
                flowEdgeIds: new uint16[](1),
                data: redemptionData // use redemption data to tell redemptionHandler what collateral is requested
            });
            streams[0].flowEdgeIds[0] = uint16(1);
        }

        // Now source avatar friend is ready to call operateFlowMatrix with crafted input.
        vm.prank(sourceAvatarFriend);
        hub.operateFlowMatrix(flowVertices, flowEdges, streams, packedCoordinates);

        // After redemption, source avatar friend should have received collateral tokens.
        // Check the collateral balance.
        for (uint256 i; i < redemptionIds.length;) {
            assertEq(
                redemptionAmounts[i],
                hub.balanceOf(sourceAvatarFriend, redemptionIds[i]),
                "Collateral balances are not received by source avatar friend"
            );
            unchecked {
                ++i;
            }
        }
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
        indexes = new uint16[](arr.length);
        for (uint16 i; i < arr.length;) {
            indexes[i] = i;
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
                    uint16 tempIndex = indexes[j];
                    indexes[j] = indexes[j + 1];
                    indexes[j + 1] = tempIndex;
                }
            }
        }
        return (arr, indexes);
    }
}
