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

    function setUp() public {
        // Create test addresses
        owner = makeAddr("owner");
        service = makeAddr("service");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        mockCircles = new MockCirclesDeployment();

        // Register Alice and Bob as people and mint initial CRC
        mockCircles.mockHub().registerHuman(alice, 1000 * CRC);
        mockCircles.mockHub().registerHuman(bob, 1000 * CRC);

        // Have Alice and Bob authorize the redemption operator as ERC1155 operator
        vm.startPrank(alice);
        mockCircles.mockHub().setApprovalForAll(address(mockCircles.redemptionOperator()), true);
        vm.stopPrank();

        vm.startPrank(bob);
        mockCircles.mockHub().setApprovalForAll(address(mockCircles.redemptionOperator()), true);
        vm.stopPrank();
    }

    // Test group deployment
    function testCreateCoreMembersGroupWithoutInitialConditions() public {
        address[] memory noInitialConditions = new address[](0);

        vm.startPrank(owner);
        cmGroup = mockCircles.createCMGroup(service, noInitialConditions, "NoConditionsCMG", "CMG", bytes32(0));

        // Verify owner is set correctly
        assertEq(ICoreMembersGroup(cmGroup).owner(), owner);
    }

    // Test group trusting members
    function testTrustAliceAndBob() public {
        testCreateCoreMembersGroupWithoutInitialConditions();

        // Trust Alice and Bob from group (as owner)
        vm.startPrank(owner);
        ICoreMembersGroup(cmGroup).trust(alice, type(uint96).max);
        ICoreMembersGroup(cmGroup).trust(bob, type(uint96).max);
        vm.stopPrank();

        // Verify trust was established
        assertTrue(mockCircles.mockHub().isTrusted(cmGroup, alice));
        assertTrue(mockCircles.mockHub().isTrusted(cmGroup, bob));
    }

    // Test group minting with deposited CRC collateral
    function testGroupMintCollateralWithGroupMint() public {
        testTrustAliceAndBob();

        // Have Alice send 101 of her CRC to mint handler
        vm.startPrank(alice);
        address[] memory collateralAvatars = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        collateralAvatars[0] = alice;
        amounts[0] = 101 * CRC;
        mockCircles.mockHub().groupMint(cmGroup, collateralAvatars, amounts, "");
        vm.stopPrank();

        // Verify Alice's CRC was deposited
        assertEq(mockCircles.mockHub().balanceOf(alice, uint256(uint160(alice))), 899 * CRC);
        assertEq(mockCircles.mockHub().balanceOf(alice, uint256(uint160(cmGroup))), 101 * CRC);
    }

    function testGroupMintCollateralWithSafeTransfer() public {
        testTrustAliceAndBob();

        // Have Bob send 230 of his CRC directly to mint handler via safeTransfer
        vm.startPrank(bob);
        mockCircles.mockHub().safeTransferFrom(
            bob, ICoreMembersGroup(cmGroup).mintHandler(), uint256(uint160(bob)), 230 * CRC, ""
        );
        vm.stopPrank();

        // Verify Bob's CRC was received and converted to group CRC
        assertEq(mockCircles.mockHub().balanceOf(bob, uint256(uint160(bob))), 770 * CRC);
        assertEq(mockCircles.mockHub().balanceOf(bob, uint256(uint160(cmGroup))), 230 * CRC);
    }

    function testDirectRedemptionViaCMGRedemptionOperator() public {
        testGroupMintCollateralWithGroupMint();

        // Verify Alice has approved redemption operator
        assertTrue(mockCircles.mockHub().isApprovedForAll(alice, address(mockCircles.redemptionOperator())));

        // Have Alice redeem 75 of her CRC circles (collateral) from the group
        vm.startPrank(alice);
        uint256[] memory redemptionIds = new uint256[](1);
        uint256[] memory redemptionValues = new uint256[](1);
        redemptionIds[0] = uint256(uint160(alice)); // Alice's own CRC id
        redemptionValues[0] = 75 * CRC;

        mockCircles.redemptionOperator().redeem(cmGroup, redemptionIds, redemptionValues);
        vm.stopPrank();

        // Verify Alice's balances after redemption
        // She minted 101 CRC into gCRC, then redeemed 75 CRC back
        assertEq(mockCircles.mockHub().balanceOf(alice, uint256(uint160(alice))), 974 * CRC); // Original - minted + redeemed
        assertEq(mockCircles.mockHub().balanceOf(alice, uint256(uint160(cmGroup))), 26 * CRC); // Minted - redeemed
    }

    // full flow test
    function testFullFlowCMGMintAndAutomaticRedemption() public {
        testCreateCoreMembersGroupWithoutInitialConditions();
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
