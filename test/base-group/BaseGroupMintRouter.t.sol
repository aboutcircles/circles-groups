// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "forge-std/StdCheats.sol";
import "circles-contracts-v2/hub/Hub.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IHub} from "src/base-group/interfaces/IHub.sol";

contract BaseGroupMintRouterTest is Test {
    // struct IHub.FlowEdge {
    //     uint16 streamSinkId;
    //     uint192 amount;
    // }

    // struct IHub.Stream {
    //     uint16 sourceCoordinate;
    //     uint16[] flowEdgeIds; // todo: this can possible be packed more compactly manually, evaluate
    //     bytes data;
    // }

    // Get all token balances, filter out the token that is trusted by group
    // curl -X POST --data '{
    //   "jsonrpc": "2.0",
    //   "id": 1,
    //   "method": "circles_getTokenBalances",
    //   "params": [
    //     "0x948F7b1Ff398fA2994e4980ecDBe2c040E7273bc"
    //   ]
    // }' -H "Content-Type: application/json" http://rpc.aboutcircles.com

    address deployer = makeAddr("deployer");
    // Fork id for Gnosis chain
    uint256 gnosisFork;

    // Hub instance (the fork uses the real deployed Hub)
    IHub hub = IHub(0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8);

    address me = 0x948F7b1Ff398fA2994e4980ecDBe2c040E7273bc;
    address offer = 0xB3129372E52B910B6994EAEF77BbC1892EA48779;
    address router = 0xDC287474114cC0551a81DdC2EB51783fBF34802F;
    address group = 0x86533d1aDA8Ffbe7b6F7244F9A1b707f7f3e239b;

    // trusted by group, hold by me
    address trustedAddress = 0xd3F989B17d8d409A2d2795EAA6b187BB012ee500;

    uint192 holdAmount = 465235330257;

    function setUp() public {
        // Fork Gnosis chain using RPC URL in environment variable (e.g., GNOSIS_RPC)
        string memory rpcUrl = "https://rpc.gnosischain.com";

        gnosisFork = vm.createFork(rpcUrl);
        vm.selectFork(gnosisFork);
    }

    function testRouter() public {
        address[] memory flowVertices = new address[](5);
        IHub.FlowEdge[] memory flowEdges = new IHub.FlowEdge[](3);
        IHub.Stream[] memory streams = new IHub.Stream[](1);
        bytes memory packCoordinate;

        flowVertices[0] = group;
        flowVertices[1] = me;
        flowVertices[2] = offer;
        flowVertices[3] = trustedAddress;
        flowVertices[4] = router;

        flowEdges[0] = IHub.FlowEdge({streamSinkId: uint16(0), amount: holdAmount});
        flowEdges[1] = IHub.FlowEdge({streamSinkId: uint16(0), amount: holdAmount});
        flowEdges[2] = IHub.FlowEdge({streamSinkId: uint16(1), amount: holdAmount});

        uint16[] memory flowEdgeIds = new uint16[](1);
        flowEdgeIds[0] = uint16(2);

        streams[0] = IHub.Stream({
            sourceCoordinate: uint16(1), // TODO
            flowEdgeIds: flowEdgeIds,
            data: bytes("")
        });
        uint16[] memory coords = new uint16[]((flowEdges.length) * 3);
        coords[0] = uint16(3);
        coords[1] = uint16(1);
        coords[2] = uint16(4);

        coords[3] = uint16(3);
        coords[4] = uint16(4);
        coords[5] = uint16(0);

        coords[6] = uint16(0);
        coords[7] = uint16(0);
        coords[8] = uint16(2);

        packCoordinate = _packCoordinates(coords);

        vm.prank(me);
        hub.operateFlowMatrix(flowVertices, flowEdges, streams, packCoordinate);
    }

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
