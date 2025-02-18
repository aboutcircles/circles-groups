// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import {Test} from "forge-std/Test.sol";
import "test/mock-circles/MockCirclesDeployment.sol";

contract CMGRedemptionHandlerTest is Test {
    // Constants
    uint256 public constant CRC = 1e18;
    uint256 public constant MAX_NUMBER_REDEMPTION_IDS = 100;
    uint256 public constant MAX_REDEEM_PER_ID = 500 * CRC;

    // State

    /// @notice Mock Circles Deployment
    MockCirclesDeployment public mockCircles;

    // Test addresses
    address public cmGroup;
    address public owner;
    address public service;
    address public alice;
    address public bob;

    // Handler instance
    CMGRedemptionHandler public redemptionHandler;

    function setUp() public {
        // Create test addresses
        owner = makeAddr("owner");
        service = makeAddr("service");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        mockCircles = new MockCirclesDeployment();
    }

    // Test group deployment
    function testCreateCoreMembersGroupWithoutInitialConditions() public {
        address[] memory noInitialConditions = new address[](0);

        cmGroup = mockCircles.createCMGroup(service, noInitialConditions, "NoConditionsCMG", "CMG", bytes32(0));
    }

    // // Test basic collateral management
    // function testRegisterCollateral() public {}

    // // Test redemption functionality
    // function testBasicRedemption() public {}
    // function testPartialRedemption() public {}
    // function testMaxRedeemPerIdLimit() public {}

    // // Test collateral search functionality
    // function testFindCollateralSimple() public {}
    // function testFindCollateralComplex() public {}
    // function testFindCollateralWithCursor() public {}

    // // Test ERC1155 reception
    // function testSingleTokenReception() public {}
    // function testBatchTokenReception() public {}

    // // Test conversion state management
    // function testConversionStateFlow() public {}
    // function testFailOngoingConversion() public {}

    // // Test edge cases
    // function testInsufficientCollateral() public {}
    // function testZeroAmountRedemption() public {}
    // function testEmptyCollateralList() public {}
}
