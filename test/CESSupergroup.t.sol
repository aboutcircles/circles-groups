// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import "src/supergroup/ISupergroup.sol";
import {IHub} from "src/circles/IHub.sol";
import {CirclesTypes} from "src/circles/Types.sol";
import {CESSupergroup} from "src/projects/ces/CESSupergroup.sol";
import {SupergroupOperator} from "src/operator/SupergroupOperator.sol";
import {UpgradeableRenounceableProxy} from "circles-contracts-v2/groups/UpgradeableRenounceableProxy.sol";

contract CESSupergroupTest is Test {
    IHub public constant HUB_V2 = IHub(address(0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8));
    address testBacker = address(0x6CA3184659B8188c42F04E75c43D83C6b9963f21);
    address testAccount = address(0xc175a0c71f1eDA836ebbF3Ab0e32Fc8865FdEe91);
    address deployer = address(0x543587975);
    address implementationCESSupergroup;
    address proxy;
    SupergroupOperator superGroupOperator;

    // params
    address service = address(0x45351432);
    uint256 fee = 0;
    address feeCollection = address(0x34325);
    uint256 redemptionBurnRate = 0;
    //address[] operators;
    string name = "name";
    string symbol = "symbol";
    bytes32 metadataDigest = bytes32(hex"4322587975927343");

    uint96 expiry = type(uint96).max;

    uint256 blockNumber = 38206714;
    uint256 gnosis;

    function setUp() public {
        gnosis = vm.createFork(vm.envString("GNOSIS_RPC"), blockNumber);
        vm.selectFork(gnosis);

        // deploy implementaion (from EOA)
        vm.prank(deployer);
        implementationCESSupergroup = address(new CESSupergroup());

        // deploy proxy (from EOA)
        address[] memory operators;
        bytes memory data = abi.encodeWithSignature(
            "setup(address,uint256,address,uint256,address[],string,string,bytes32)",
            service,
            fee,
            feeCollection,
            redemptionBurnRate,
            operators,
            name,
            symbol,
            metadataDigest
        );
        vm.prank(deployer);
        proxy = address(new UpgradeableRenounceableProxy(implementationCESSupergroup, data));

        // deploy operator
        superGroupOperator = new SupergroupOperator(ISupergroup(proxy));

        // set operator
        vm.prank(deployer);
        CESSupergroup(proxy).setAuthorizedOperator(address(superGroupOperator), true);
    }

    function test_DefaultFlow() public {
        address[] memory backers = new address[](1);
        backers[0] = testBacker;
        // make call from service to trust backer
        vm.prank(service);
        CESSupergroup(proxy).trustBatch(backers, expiry);

        // make call from owner to trust test account
        vm.prank(deployer);
        CESSupergroup(proxy).trust(testAccount, expiry);

        // call Hub.operateMatrixFlow from test account to group
        bool accountZero = testAccount < proxy;
        address[] memory flowVertices = new address[](2);
        flowVertices[0] = accountZero ? testAccount : proxy;
        flowVertices[1] = accountZero ? proxy : testAccount;
        CirclesTypes.FlowEdge[] memory flow = new CirclesTypes.FlowEdge[](1);
        flow[0].amount = uint192(5 ether);
        flow[0].streamSinkId = uint16(1);
        // allocate three coordinates per flow edge
        uint16[] memory coordinates = new uint16[](3);
        // first index indicates which Circles to use
        // for our example, we use the Circles of the sender
        coordinates[0] = uint16(accountZero ? 0 : 1);
        // the second coordinate refers to the sender
        coordinates[1] = uint16(accountZero ? 0 : 1);
        // the third coordinate specifies the receiver
        coordinates[2] = uint16(accountZero ? 1 : 0);
        bytes memory packedCoordinates = packCoordinates(coordinates);

        // Lastly we need to define the streams
        CirclesTypes.Stream[] memory streams = new CirclesTypes.Stream[](1);
        // the source coordinate for Alice
        streams[0].sourceCoordinate = uint16(accountZero ? 0 : 1);
        // the flow edges that constitute the termination of this stream
        streams[0].flowEdgeIds = new uint16[](1);
        streams[0].flowEdgeIds[0] = uint16(0);
        // and optional data
        streams[0].data = new bytes(0);

        vm.prank(testAccount);
        HUB_V2.operateFlowMatrix(flowVertices, flow, streams, packedCoordinates);
    }

    function packCoordinates(uint16[] memory _coordinates) private pure returns (bytes memory packedData_) {
        packedData_ = new bytes(_coordinates.length * 2);

        for (uint256 i = 0; i < _coordinates.length; i++) {
            packedData_[2 * i] = bytes1(uint8(_coordinates[i] >> 8)); // High byte
            packedData_[2 * i + 1] = bytes1(uint8(_coordinates[i] & 0xFF)); // Low byte
        }
    }
}
