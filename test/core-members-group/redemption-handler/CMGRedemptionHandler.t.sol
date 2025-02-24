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

    function testGroupMintCollateralWithMultipleSafeTransfers() public {
        testTrustAliceAndBob();

        // Have Alice send 340 CRC via safeTransfer
        vm.startPrank(alice);
        mockCircles.mockHub().safeTransferFrom(
            alice, ICoreMembersGroup(cmGroup).mintHandler(), uint256(uint160(alice)), 340 * CRC, ""
        );
        vm.stopPrank();

        // Have Bob send 410 CRC via safeTransfer
        vm.startPrank(bob);
        mockCircles.mockHub().safeTransferFrom(
            bob, ICoreMembersGroup(cmGroup).mintHandler(), uint256(uint160(bob)), 410 * CRC, ""
        );
        vm.stopPrank();

        // Verify Alice's CRC was received and converted to group CRC
        assertEq(mockCircles.mockHub().balanceOf(alice, uint256(uint160(alice))), 660 * CRC);
        assertEq(mockCircles.mockHub().balanceOf(alice, uint256(uint160(cmGroup))), 340 * CRC);

        // Verify Bob's CRC was received and converted to group CRC
        assertEq(mockCircles.mockHub().balanceOf(bob, uint256(uint160(bob))), 590 * CRC);
        assertEq(mockCircles.mockHub().balanceOf(bob, uint256(uint160(cmGroup))), 410 * CRC);

        // Get group's redemption handler address and check active collateral
        address redemptionHandler = ICoreMembersGroup(cmGroup).redemptionHandler();
        (uint256[] memory collateralIds, uint256[] memory balances, uint256 totalLength) =
            ICMGRedemptionHandler(redemptionHandler).getActiveCollateral();

        // Verify multiple collateral is tracked
        assertEq(collateralIds.length, 2);
        assertEq(balances.length, 2);
        assertEq(totalLength, 2);

        // Verify collateral IDs and balances match deposits
        assertEq(collateralIds[0], uint256(uint160(alice)));
        assertEq(balances[0], 340 * CRC);
        assertEq(collateralIds[1], uint256(uint160(bob)));
        assertEq(balances[1], 410 * CRC);
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
        testGroupMintCollateralWithMultipleSafeTransfers();

        // Get group's redemption handler address
        address redemptionHandler = ICoreMembersGroup(cmGroup).redemptionHandler();

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
        assertEq(balances[0], 340 * CRC);
        assertEq(balances[1], 410 * CRC);
    }

    function testCanFindCollateralForLargeRedemption() public {
        testGroupMintCollateralWithMultipleSafeTransfers();

        // Get group's redemption handler address
        address redemptionHandler = ICoreMembersGroup(cmGroup).redemptionHandler();

        // Have redemption handler search for 250 CRC worth of collateral
        (uint256[] memory foundIds, uint256[] memory foundAmounts) = ICMGRedemptionHandler(redemptionHandler)
            .findCollateral(
            cmGroup,
            370 * CRC,
            false // don't accept partial fills
        );

        // Verify it found sufficient collateral
        uint256 total = 0;
        for (uint256 i = 0; i < foundAmounts.length; i++) {
            total += foundAmounts[i];
        }
        assertEq(total, 370 * CRC);

        // Verify returned collateral IDs match Alice and Bob's
        assertEq(foundIds[0], uint256(uint160(alice)));
        assertEq(foundAmounts[0], 340 * CRC);
        assertEq(foundIds[1], uint256(uint160(bob)));
        assertEq(foundAmounts[1], 30 * CRC);
    }

    function testRedeemWithFoundCollateralForLargeRedemption() public {
        testGroupMintCollateralWithMultipleSafeTransfers();

        // Transfer Bob's group circles to Alice so she has enough to redeem
        vm.startPrank(bob);
        mockCircles.mockHub().safeTransferFrom(bob, alice, uint256(uint160(cmGroup)), 410 * CRC, "");
        vm.stopPrank();

        // Verify Alice now has enough group circles (340 + 410 = 750)
        assertEq(mockCircles.mockHub().balanceOf(alice, uint256(uint160(cmGroup))), 750 * CRC);

        // Get redemption handler and check active collateral before redemption
        address redemptionHandler = ICoreMembersGroup(cmGroup).redemptionHandler();
        (uint256[] memory preCollateralIds, uint256[] memory preBalances, uint256 preTotalLength) =
            ICMGRedemptionHandler(redemptionHandler).getActiveCollateral();

        // Verify collateral state before redemption
        assertEq(preCollateralIds.length, 2);
        assertEq(preBalances.length, 2);
        assertEq(preTotalLength, 2);
        assertEq(preCollateralIds[0], uint256(uint160(alice)));
        assertEq(preBalances[0], 340 * CRC);
        assertEq(preCollateralIds[1], uint256(uint160(bob)));
        assertEq(preBalances[1], 410 * CRC);

        // Have Alice redeem 370 CRC worth of collateral from the group automatically
        vm.startPrank(alice);
        mockCircles.redemptionOperator().redeemWithFoundCollateral(cmGroup, 370 * CRC, false);
        vm.stopPrank();

        // Verify Alice's summed balances after redemption
        uint256 aliceAliceCirclesBalance = mockCircles.mockHub().balanceOf(alice, uint256(uint160(alice)));
        uint256 aliceBobCirclesBalance = mockCircles.mockHub().balanceOf(alice, uint256(uint160(bob)));

        // Started with 1000 CRC, minted 340 gCRC, received 410 gCRC from Bob, redeemed 370 gCRC worth
        // Initial gCRC balance: 340 + 410 = 750
        // Final gCRC balance: 750 - 370 = 380
        assertEq(mockCircles.mockHub().balanceOf(alice, uint256(uint160(cmGroup))), 380 * CRC);
        // Total collateral balance of personal Circles should be: 1000 aCRC - 340 aCRC + 370gCRC(redeemed) = 1030
        assertEq(aliceAliceCirclesBalance + aliceBobCirclesBalance, 1030 * CRC);

        // Verify Bob's balances - only his original CRC mint transaction should be reflected
        assertEq(mockCircles.mockHub().balanceOf(bob, uint256(uint160(bob))), 590 * CRC); // Original - minted
        assertEq(mockCircles.mockHub().balanceOf(bob, uint256(uint160(cmGroup))), 0); // Transferred all gCRC to Alice

        // Get redemption handler and check active collateral after redemption
        (uint256[] memory postCollateralIds, uint256[] memory postBalances, uint256 postTotalLength) =
            ICMGRedemptionHandler(redemptionHandler).getActiveCollateral();

        // Verify total tracked redemption IDs and balances after redemption
        assertEq(postCollateralIds.length, 1);
        assertEq(postBalances.length, 1);
        assertEq(postTotalLength, 1);

        // Verify collateral ID matches Bob's token ID (Alice's fully redeemed)
        assertEq(postCollateralIds[0], uint256(uint160(bob)));

        // Verify remaining balance tracked for Bob's collateral
        // Bob's collateral: 410 CRC - 30 CRC = 380 CRC
        assertEq(postBalances[0], 380 * CRC);
    }

    function testMultipleUsersRedeemingAllGCRC() public {
        testGroupMintCollateralWithMultipleSafeTransfers();

        // Bob currently has 410 gCRC and Alice has 340 gCRC
        // Transfer 210 of Bob's gCRC to Alice
        vm.startPrank(bob);
        mockCircles.mockHub().safeTransferFrom(bob, alice, uint256(uint160(cmGroup)), 210 * CRC, "");
        vm.stopPrank();

        // Verify balances after transfer
        assertEq(mockCircles.mockHub().balanceOf(alice, uint256(uint160(cmGroup))), 550 * CRC); // 340 + 210
        assertEq(mockCircles.mockHub().balanceOf(bob, uint256(uint160(cmGroup))), 200 * CRC); // 410 - 210

        // Bob redeems all his remaining 200 gCRC
        vm.startPrank(bob);
        mockCircles.redemptionOperator().redeemWithFoundCollateral(cmGroup, 200 * CRC, false);
        vm.stopPrank();

        // Verify Bob's redemption
        assertEq(mockCircles.mockHub().balanceOf(bob, uint256(uint160(cmGroup))), 0); // All gCRC redeemed
        uint256 bobTotalPersonalCircles = mockCircles.mockHub().balanceOf(bob, uint256(uint160(bob)))
            + mockCircles.mockHub().balanceOf(bob, uint256(uint160(alice)));
        assertEq(bobTotalPersonalCircles, 790 * CRC); // Original - minted + redeemed

        // Alice redeems all her remaining 550 gCRC
        vm.startPrank(alice);
        mockCircles.redemptionOperator().redeemWithFoundCollateral(cmGroup, 550 * CRC, false);
        vm.stopPrank();

        // Verify Alice's redemption
        assertEq(mockCircles.mockHub().balanceOf(alice, uint256(uint160(cmGroup))), 0); // All gCRC redeemed
        // Check Alice's total personal circles (original - minted + all redeemed)
        uint256 aliceTotalPersonalCircles = mockCircles.mockHub().balanceOf(alice, uint256(uint160(alice)))
            + mockCircles.mockHub().balanceOf(alice, uint256(uint160(bob)));
        assertEq(aliceTotalPersonalCircles, 1210 * CRC); // 1000 - 340 + 550

        // Get redemption handler and verify no collateral is tracked
        address redemptionHandler = ICoreMembersGroup(cmGroup).redemptionHandler();
        (uint256[] memory collateralIds, uint256[] memory balances, uint256 totalLength) =
            ICMGRedemptionHandler(redemptionHandler).getActiveCollateral();

        assertEq(collateralIds.length, 0);
        assertEq(balances.length, 0);
        assertEq(totalLength, 0);
    }

    function testMoreInvolvedSequenceMintAndRedeems() public {
        testTrustAliceAndBob();

        // Create additional users
        address charlie = makeAddr("charlie");
        address david = makeAddr("david");
        address els = makeAddr("els");

        // Register new users as humans with initial CRC
        mockCircles.mockHub().registerHuman(charlie, 1000 * CRC);
        mockCircles.mockHub().registerHuman(david, 1000 * CRC);
        mockCircles.mockHub().registerHuman(els, 1000 * CRC);

        // Trust new users
        vm.startPrank(owner);
        ICoreMembersGroup(cmGroup).trust(charlie, type(uint96).max);
        ICoreMembersGroup(cmGroup).trust(david, type(uint96).max);
        ICoreMembersGroup(cmGroup).trust(els, type(uint96).max);
        vm.stopPrank();

        // Authorize redemption operator for new users
        vm.startPrank(charlie);
        mockCircles.mockHub().setApprovalForAll(address(mockCircles.redemptionOperator()), true);
        vm.stopPrank();

        vm.startPrank(david);
        mockCircles.mockHub().setApprovalForAll(address(mockCircles.redemptionOperator()), true);
        vm.stopPrank();

        vm.startPrank(els);
        mockCircles.mockHub().setApprovalForAll(address(mockCircles.redemptionOperator()), true);
        vm.stopPrank();

        // Initial mints via safe transfers
        vm.startPrank(alice);
        mockCircles.mockHub().safeTransferFrom(
            alice, ICoreMembersGroup(cmGroup).mintHandler(), uint256(uint160(alice)), 200 * CRC, ""
        );
        vm.stopPrank();

        vm.startPrank(bob);
        mockCircles.mockHub().safeTransferFrom(
            bob, ICoreMembersGroup(cmGroup).mintHandler(), uint256(uint160(bob)), 300 * CRC, ""
        );
        vm.stopPrank();

        vm.startPrank(charlie);
        mockCircles.mockHub().safeTransferFrom(
            charlie, ICoreMembersGroup(cmGroup).mintHandler(), uint256(uint160(charlie)), 400 * CRC, ""
        );
        vm.stopPrank();

        // First round of redemptions
        vm.startPrank(alice);
        mockCircles.redemptionOperator().redeemWithFoundCollateral(cmGroup, 150 * CRC, false);
        vm.stopPrank();

        vm.startPrank(charlie);
        mockCircles.redemptionOperator().redeemWithFoundCollateral(cmGroup, 200 * CRC, false);
        vm.stopPrank();

        // Second round of mints
        vm.startPrank(els);
        mockCircles.mockHub().safeTransferFrom(
            els, ICoreMembersGroup(cmGroup).mintHandler(), uint256(uint160(els)), 250 * CRC, ""
        );
        vm.stopPrank();

        vm.startPrank(david);
        mockCircles.mockHub().safeTransferFrom(
            david, ICoreMembersGroup(cmGroup).mintHandler(), uint256(uint160(david)), 350 * CRC, ""
        );
        vm.stopPrank();

        // Second round of redemptions
        vm.startPrank(bob);
        mockCircles.redemptionOperator().redeemWithFoundCollateral(cmGroup, 200 * CRC, false);
        vm.stopPrank();

        vm.startPrank(david);
        mockCircles.redemptionOperator().redeemWithFoundCollateral(cmGroup, 150 * CRC, false);
        vm.stopPrank();

        // Final check of redemption handler state
        address redemptionHandler = ICoreMembersGroup(cmGroup).redemptionHandler();
        (uint256[] memory collateralIds, uint256[] memory balances, uint256 totalLength) =
            ICMGRedemptionHandler(redemptionHandler).getActiveCollateral();

        // Should have 5 active collateral sources
        assertEq(totalLength, 5);
        assertEq(collateralIds.length, 5);
        assertEq(balances.length, 5);

        // Verify each collateral ID and balance
        assertEq(collateralIds[0], uint256(uint160(alice)));
        assertEq(balances[0], 50 * CRC); // 200 - 150 deposited

        assertEq(collateralIds[1], uint256(uint160(bob)));
        assertEq(balances[1], 100 * CRC); // 300 - 200 deposited

        assertEq(collateralIds[2], uint256(uint160(charlie)));
        assertEq(balances[2], 200 * CRC); // 400 - 200 deposited

        assertEq(collateralIds[3], uint256(uint160(els)));
        assertEq(balances[3], 100 * CRC); // 250 deposited - 150 withdrawn by David

        assertEq(collateralIds[4], uint256(uint160(david)));
        assertEq(balances[4], 350 * CRC); // 350 CRC left untouched

        // Get total remaining collateral
        uint256 totalCollateral = 0;
        for (uint256 i = 0; i < balances.length; i++) {
            totalCollateral += balances[i];
        }

        // Total collateral should be initial deposits minus all redemptions
        uint256 expectedTotal = (200 + 300 + 400 + 250 + 350) * CRC - (150 + 200 + 200 + 150) * CRC;
        assertEq(totalCollateral, expectedTotal);
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
