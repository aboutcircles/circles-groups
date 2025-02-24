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

        // Get group's redemption handler address and check active collateral
        address redemptionHandler = ICoreMembersGroup(cmGroup).redemptionHandler();
        (uint256[] memory collateralIds, uint256[] memory balances, uint256 totalLength) =
            ICMGRedemptionHandler(redemptionHandler).getActiveCollateral();

        // Verify single collateral is tracked
        assertEq(collateralIds.length, 1);
        assertEq(balances.length, 1);
        assertEq(totalLength, 1);

        // Verify collateral ID and balance match Alice's deposit
        assertEq(collateralIds[0], uint256(uint160(alice)));
        assertEq(balances[0], 101 * CRC);
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

        // Get group's redemption handler address and check active collateral
        address redemptionHandler = ICoreMembersGroup(cmGroup).redemptionHandler();
        (uint256[] memory collateralIds, uint256[] memory balances, uint256 totalLength) =
            ICMGRedemptionHandler(redemptionHandler).getActiveCollateral();

        // Verify single collateral is tracked
        assertEq(collateralIds.length, 1);
        assertEq(balances.length, 1);
        assertEq(totalLength, 1);

        // Verify collateral ID and balance match Bob's deposit
        assertEq(collateralIds[0], uint256(uint160(bob)));
        assertEq(balances[0], 230 * CRC);
    }

    function testDirectRedemptionViaCMGRedemptionOperator() public {
        testGroupMintCollateralWithGroupMint();

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

    function testCanListActiveCollateralAfterMinting() public {
        // Have Alice mint 101 CRC and Bob mint 230 CRC into group circles
        testGroupMintCollateralWithGroupMint(); // Alice mints 101 gCRC
        testGroupMintCollateralWithSafeTransfer(); // Bob mints 230 gCRC

        // Get group's redemption handler address
        address redemptionHandler = ICoreMembersGroup(cmGroup).redemptionHandler();

        // Get list of active collateral from offset 0
        (uint256[] memory collateralIds, uint256[] memory balances, uint256 totalLength) =
            ICMGRedemptionHandler(redemptionHandler).getActiveCollateral();

        // Verify returned array lengths match expected active collateral count
        assertEq(collateralIds.length, 2);
        assertEq(balances.length, 2);
        assertEq(totalLength, 2);

        // Verify collateral IDs match Alice and Bob's token IDs
        assertEq(collateralIds[0], uint256(uint160(alice)));
        assertEq(collateralIds[1], uint256(uint160(bob)));

        // Verify balances match what was minted
        assertEq(balances[0], 101 * CRC);
        assertEq(balances[1], 230 * CRC);
    }

    // function testCanFindCollateralForLargeRedemption() public {
    //     // Have Alice mint 101 CRC and Bob mint 230 CRC into group circles
    //     testGroupMintCollateralWithGroupMint(); // Alice mints 101 gCRC
    //     testGroupMintCollateralWithSafeTransfer(); // Bob mints 230 gCRC

    //     // Get group's redemption handler address
    //     address redemptionHandler = ICoreMembersGroup(cmGroup).redemptionHandler();

    //     // Have redemption handler search for 250 CRC worth of collateral
    //     (uint256[] memory foundIds, uint256[] memory foundAmounts) = ICMGRedemptionHandler(redemptionHandler).findCollateral(
    //         cmGroup,
    //         10 * CRC,
    //         false // don't accept partial fills
    //     );

    //     // Verify it found sufficient collateral
    //     uint256 total = 0;
    //     for(uint256 i = 0; i < foundAmounts.length; i++) {
    //         total += foundAmounts[i];
    //     }
    //     assertEq(total, 10 * CRC);

    //     // Verify returned collateral IDs match Alice and Bob's
    //     // assertEq(foundIds[0], uint256(uint160(alice)));
    //     // assertEq(foundIds[1], uint256(uint160(bob)));
    // }

    // function testRedeemWithFoundCollateralForLargeRedemption() public {
    //     // Have Alice mint 101 CRC and Bob mint 230 CRC into group circles
    //     testGroupMintCollateralWithGroupMint(); // Alice mints 101 gCRC
    //     testGroupMintCollateralWithSafeTransfer(); // Bob mints 230 gCRC

    //     // Transfer Bob's group circles to Alice so she has enough to redeem 250 CRC
    //     vm.startPrank(bob);
    //     mockCircles.mockHub().safeTransferFrom(bob, alice, uint256(uint160(cmGroup)), 230 * CRC, "");
    //     vm.stopPrank();

    //     // Verify Alice now has enough group circles (101 + 230 = 331)
    //     // assertEq(mockCircles.mockHub().balanceOf(alice, uint256(uint160(cmGroup))), 331 * CRC);

    //     // Have Alice redeem 250 CRC worth of collateral from the group automatically
    //     vm.startPrank(alice);
    //     mockCircles.redemptionOperator().redeemWithFoundCollateral(cmGroup, 250 * CRC, false);
    //     vm.stopPrank();

    //     // Verify Alice's summed balances after redemption
    //     uint256 aliceAliceCirclesBalance = mockCircles.mockHub().balanceOf(alice, uint256(uint160(alice)));
    //     uint256 aliceBobCirclesBalance = mockCircles.mockHub().balanceOf(alice, uint256(uint160(bob)));

    //     // // Started with 1000 CRC, minted 101 gCRC, received 230 gCRC from Bob, redeemed 250 gCRC worth
    //     // // Initial gCRC balance: 101 + 230 = 331
    //     // // Final gCRC balance: 331 - 250 = 81
    //     // assertEq(mockCircles.mockHub().balanceOf(alice, uint256(uint160(cmGroup))), 81 * CRC);
    //     // // Total collateral balance of personal Circles should be: 1000 - 101 + 250 = 1149
    //     // assertEq(aliceAliceCirclesBalance + aliceBobCirclesBalance, 1149 * CRC);

    //     // // Verify Bob's balances - only his original CRC mint transaction should be reflected
    //     // assertEq(mockCircles.mockHub().balanceOf(bob, uint256(uint160(bob))), 770 * CRC); // Original - minted
    //     // assertEq(mockCircles.mockHub().balanceOf(bob, uint256(uint160(cmGroup))), 0); // Transferred all gCRC to Alice
    // }

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
