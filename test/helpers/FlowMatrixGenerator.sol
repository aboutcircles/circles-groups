// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {HubStorageWrites} from "./HubStorageWrites.sol";
import "circles-contracts-v2/hub/TypeDefinitions.sol";

contract FlowMatrixGenerator is HubStorageWrites {
    uint256 internal constant MIN_TOTAL_AMOUNT = 100 ether;
    uint256 internal constant MAX_TOTAL_AMOUNT = 10_000 ether;
    uint256 internal constant MIN_TERMINATED_EDGES = 1;
    uint256 internal constant MAX_TERMINATED_EDGES = 10;
    uint160 internal constant MAX_ADDRESS_OFFSET = uint160(type(uint32).max);
    uint160 internal constant MIN_ADDRESS_OFFSET = uint160(type(uint8).max);
    uint256 internal constant NUMBER_VERTICES_PER_FLOW = 3;

    function generateFlowMatrix(
        uint256 totalAmount, // min 100, max 10_000
        uint256 numberOfTerminatedEdges, // fuzz from 1 to 10, also equal number of collateral ids for now
        uint64 lastUpdatedDay, // from block state
        address[2] memory groupAndDestination // constants: group and mintHandler (next iteration: should be compatible mintHandler/redemptionHandler)
    )
        internal
        returns (
            address sourceAvatar,
            address[] memory flowVertices,
            TypeDefinitions.FlowEdge[] memory flowEdges,
            TypeDefinitions.Stream[] memory streams,
            uint256[] memory redemptionIds,
            uint256[] memory redemptionAmounts,
            bytes memory packedCoordinates
        )
    {
        // polish fuzzing values
        totalAmount = _polishFuzzedTotalAmount(totalAmount);
        numberOfTerminatedEdges = _polishFuzzedNumberOfTerminatedEdges(numberOfTerminatedEdges);

        // set value for sourceAvatar
        sourceAvatar = address(uint160(groupAndDestination[1]) - MAX_ADDRESS_OFFSET);
        // set source state
        _setSourceState(sourceAvatar, lastUpdatedDay, totalAmount);

        // lets for now for simplicity say that every flow has 4 edges in total:
        // (init edge from - source, terminal edge to - destination, and 2 intermediate edges)
        // later we will have randomness here and different number of edges at each flow and also common vertices at different flows
        // so, it means that we need 3 intermidiate vertices per flow and source and destination vertices
        uint256 numberOfVertices = numberOfTerminatedEdges * NUMBER_VERTICES_PER_FLOW + 2;

        flowVertices = new address[](numberOfVertices);

        // set source and destination vertices
        flowVertices[0] = sourceAvatar;
        flowVertices[numberOfVertices - 1] = groupAndDestination[1];

        // generate vertices
        // start after source and end before destination
        for (uint160 i = 1; i < numberOfVertices - 1;) {
            // generate vertix
            address vertix = address(uint160(sourceAvatar) + MIN_ADDRESS_OFFSET * i);
            // register vertix as human
            _registerHuman(vertix);
            flowVertices[i] = vertix;

            unchecked {
                ++i;
            }
        }

        uint16[] memory coords;
        {
            uint256 numEdges = numberOfTerminatedEdges * (NUMBER_VERTICES_PER_FLOW + 1);
            coords = new uint16[](3 * numEdges);
            flowEdges = new TypeDefinitions.FlowEdge[](numEdges);
        }

        // for now have only 1 stream
        streams = new TypeDefinitions.Stream[](1);
        streams[0] = TypeDefinitions.Stream({
            sourceCoordinate: uint16(0),
            flowEdgeIds: new uint16[](numberOfTerminatedEdges),
            data: ""
        });
        redemptionIds = new uint256[](numberOfTerminatedEdges);
        redemptionAmounts = new uint256[](numberOfTerminatedEdges);
        uint256[] memory flowAmounts = _generateFlowAmounts(totalAmount, numberOfTerminatedEdges);

        // generate edges
        // iterate through flows
        for (uint256 i; i < numberOfTerminatedEdges;) {
            // iterate through flow edges
            for (uint256 k; k < NUMBER_VERTICES_PER_FLOW + 1;) {
                uint256 index = i * (NUMBER_VERTICES_PER_FLOW + 1) + k;
                _setEdgeState(lastUpdatedDay, flowVertices, flowAmounts[i], k, index - i);
                // set coordinates
                coords[3 * index + 0] = k != 0 ? uint16(index - i) : uint16(0); // id
                coords[3 * index + 1] = k != 0 ? uint16(index - i) : uint16(0); // from
                coords[3 * index + 2] =
                    k != NUMBER_VERTICES_PER_FLOW ? uint16(index + 1 - i) : uint16(flowVertices.length - 1); // to
                // set edge
                flowEdges[index] = TypeDefinitions.FlowEdge({streamSinkId: 0, amount: uint192(flowAmounts[i])});
                if (k == NUMBER_VERTICES_PER_FLOW) {
                    // group trust collateral
                    _setTrust(groupAndDestination[0], flowVertices[index - i]);
                    flowEdges[index].streamSinkId = 1;
                    redemptionIds[i] = uint256(uint160(flowVertices[index - i]));
                    redemptionAmounts[i] = flowAmounts[i];
                    streams[0].flowEdgeIds[i] = uint16(index);
                }
                unchecked {
                    ++k;
                }
            }
            unchecked {
                ++i;
            }
        }
        packedCoordinates = _packCoordinates(coords);
    }

    // Internal helpers

    function _polishFuzzedTotalAmount(uint256 totalAmount) internal pure returns (uint256) {
        totalAmount %= (MAX_TOTAL_AMOUNT + 1);
        if (totalAmount < MIN_TOTAL_AMOUNT) totalAmount = MIN_TOTAL_AMOUNT;
        return totalAmount;
    }

    function _polishFuzzedNumberOfTerminatedEdges(uint256 numberOfTerminatedEdges) internal pure returns (uint256) {
        numberOfTerminatedEdges %= (MAX_TERMINATED_EDGES + 1);
        if (numberOfTerminatedEdges < MIN_TERMINATED_EDGES) numberOfTerminatedEdges = MIN_TERMINATED_EDGES;
        return numberOfTerminatedEdges;
    }

    function _setSourceState(address sourceAvatar, uint64 lastUpdatedDay, uint256 totalAmount) internal {
        // make source approval to operate itself
        _setOperatorApproval(sourceAvatar, sourceAvatar);
        // register source as human
        _registerHuman(sourceAvatar);
        // set source balance of own id as totalAmount
        _setCRCBalance(uint256(uint160(sourceAvatar)), sourceAvatar, lastUpdatedDay, uint192(totalAmount));
    }

    function _setEdgeState(
        uint64 lastUpdatedDay,
        address[] memory flowVertices,
        uint256 flowAmount,
        uint256 k,
        uint256 index
    ) internal {
        address vertixFrom = k != 0 ? flowVertices[index] : flowVertices[0];
        address vertixTo =
            k != NUMBER_VERTICES_PER_FLOW ? flowVertices[index + 1] : flowVertices[flowVertices.length - 1];
        // set balances
        if (k != 0) _setCRCBalance(uint256(uint160(vertixFrom)), vertixFrom, lastUpdatedDay, uint192(flowAmount));
        // set trust connection
        _setTrust(vertixTo, vertixFrom);
    }

    function _generateFlowAmounts(uint256 totalAmount, uint256 numberOfTerminatedEdges)
        internal
        pure
        returns (uint256[] memory flowAmounts)
    {
        uint256 unusedAmount = totalAmount;
        flowAmounts = new uint256[](numberOfTerminatedEdges);
        for (uint256 i; i < numberOfTerminatedEdges;) {
            uint256 flowAmount = unusedAmount / numberOfTerminatedEdges;
            if (i == numberOfTerminatedEdges - 1) flowAmount = unusedAmount;
            flowAmounts[i] = flowAmount;
            unusedAmount -= flowAmount;
            unchecked {
                ++i;
            }
        }
    }

    /**
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
