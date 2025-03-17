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
    address public charlie;
    address public david;
    address public els;

    // Token IDs
    uint256 public aliceId;
    uint256 public bobId;
    uint256 public charlieId;
    uint256 public davidId;
    uint256 public elsId;

    function setUp() public {
        // Create test addresses
        owner = makeAddr("owner");
        service = makeAddr("service");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");
        david = makeAddr("david");
        els = makeAddr("els");

        // Store token IDs
        aliceId = uint256(uint160(alice));
        bobId = uint256(uint160(bob));
        charlieId = uint256(uint160(charlie));
        davidId = uint256(uint160(david));
        elsId = uint256(uint160(els));

        mockCircles = new MockCirclesDeployment();

        // Register users as people and mint initial CRC
        mockCircles.mockHub().registerHuman(alice, 1000 * CRC);
        mockCircles.mockHub().registerHuman(bob, 1000 * CRC);
        mockCircles.mockHub().registerHuman(charlie, 1000 * CRC);
        mockCircles.mockHub().registerHuman(david, 1000 * CRC);
        mockCircles.mockHub().registerHuman(els, 1000 * CRC);

        // Have users authorize the redemption operator
        vm.startPrank(alice);
        mockCircles.mockHub().setApprovalForAll(address(mockCircles.redemptionOperator()), true);
        vm.stopPrank();

        vm.startPrank(bob);
        mockCircles.mockHub().setApprovalForAll(address(mockCircles.redemptionOperator()), true);
        vm.stopPrank();

        vm.startPrank(charlie);
        mockCircles.mockHub().setApprovalForAll(address(mockCircles.redemptionOperator()), true);
        vm.stopPrank();

        vm.startPrank(david);
        mockCircles.mockHub().setApprovalForAll(address(mockCircles.redemptionOperator()), true);
        vm.stopPrank();

        vm.startPrank(els);
        mockCircles.mockHub().setApprovalForAll(address(mockCircles.redemptionOperator()), true);
        vm.stopPrank();
    }

    // Test group deployment
    function testCreateCoreMembersGroupWithoutInitialConditions() public {
        address[] memory noInitialConditions = new address[](0);

        vm.startPrank(owner);
        (cmGroup,,,) = mockCircles.createCMGroup(service, noInitialConditions, "NoConditionsCMG", "CMG", bytes32(0));

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
        assertEq(mockCircles.mockHub().balanceOf(alice, aliceId), 899 * CRC);
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
        assertEq(collateralIds[0], aliceId);
        assertEq(balances[0], 101 * CRC);
    }

    function testGroupMintCollateralWithSafeTransfer() public {
        testTrustAliceAndBob();

        // Have Bob send 230 of his CRC directly to mint handler via safeTransfer
        vm.startPrank(bob);
        mockCircles.mockHub().safeTransferFrom(bob, ICoreMembersGroup(cmGroup).mintHandler(), bobId, 230 * CRC, "");
        vm.stopPrank();

        // Verify Bob's CRC was received and converted to group CRC
        assertEq(mockCircles.mockHub().balanceOf(bob, bobId), 770 * CRC);
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
        assertEq(collateralIds[0], bobId);
        assertEq(balances[0], 230 * CRC);
    }

    function testSettingMinimalTrackingAmountAndCheckTrackingDependingOnAmount() public {
        testCreateCoreMembersGroupWithoutInitialConditions();

        // Trust Alice and Bob to set up test
        vm.startPrank(owner);
        ICoreMembersGroup(cmGroup).trust(alice, type(uint96).max);
        ICoreMembersGroup(cmGroup).trust(bob, type(uint96).max);

        // Set minimal tracking amount to 5 CRC on redemption handler
        address redemptionHandler = ICoreMembersGroup(cmGroup).redemptionHandler();
        ICMGRedemptionHandler(redemptionHandler).setMinimalTrackingAmount(5 * CRC);
        vm.stopPrank();

        // Have Alice mint 10 CRC - above tracking amount
        vm.startPrank(alice);
        address[] memory aliceCollateralAvatars = new address[](1);
        uint256[] memory aliceAmounts = new uint256[](1);
        aliceCollateralAvatars[0] = alice;
        aliceAmounts[0] = 10 * CRC;
        mockCircles.mockHub().groupMint(cmGroup, aliceCollateralAvatars, aliceAmounts, "");
        vm.stopPrank();

        // Verify Alice's collateral is tracked
        (uint256[] memory collateralIdsAfterAlice, uint256[] memory balancesAfterAlice, uint256 totalLengthAfterAlice) =
            ICMGRedemptionHandler(redemptionHandler).getActiveCollateral();

        assertEq(collateralIdsAfterAlice.length, 1);
        assertEq(balancesAfterAlice.length, 1);
        assertEq(totalLengthAfterAlice, 1);
        assertEq(collateralIdsAfterAlice[0], aliceId);
        assertEq(balancesAfterAlice[0], 10 * CRC);

        // Have Bob mint 3 CRC - below tracking amount
        vm.startPrank(bob);
        address[] memory bobCollateralAvatars = new address[](1);
        uint256[] memory bobAmounts = new uint256[](1);
        bobCollateralAvatars[0] = bob;
        bobAmounts[0] = 3 * CRC;
        mockCircles.mockHub().groupMint(cmGroup, bobCollateralAvatars, bobAmounts, "");
        vm.stopPrank();

        // Get redemption handler and check active collateral - should be unchanged from after Alice
        (uint256[] memory collateralIds, uint256[] memory balances, uint256 totalLength) =
            ICMGRedemptionHandler(redemptionHandler).getActiveCollateral();

        // Verify still only Alice's larger deposit is tracked
        assertEq(collateralIds.length, 1);
        assertEq(balances.length, 1);
        assertEq(totalLength, 1);
        assertEq(collateralIds[0], aliceId);
        assertEq(balances[0], 10 * CRC);

        // Verify both Alice and Bob have their gCRC despite tracking
        assertEq(mockCircles.mockHub().balanceOf(alice, uint256(uint160(cmGroup))), 10 * CRC);
        assertEq(mockCircles.mockHub().balanceOf(bob, uint256(uint160(cmGroup))), 3 * CRC);
    }

    function testTrackingAmountThresholdInRedemption() public {
        testCreateCoreMembersGroupWithoutInitialConditions();

        // Trust Alice and Bob
        vm.startPrank(owner);
        ICoreMembersGroup(cmGroup).trust(alice, type(uint96).max);
        ICoreMembersGroup(cmGroup).trust(bob, type(uint96).max);

        // Set minimal tracking amount to 5 CRC on redemption handler
        address redemptionHandler = ICoreMembersGroup(cmGroup).redemptionHandler();
        ICMGRedemptionHandler(redemptionHandler).setMinimalTrackingAmount(5 * CRC);
        vm.stopPrank();

        // Have Alice mint 10 CRC - above tracking amount
        vm.startPrank(alice);
        address[] memory aliceCollateralAvatars = new address[](1);
        uint256[] memory aliceAmounts = new uint256[](1);
        aliceCollateralAvatars[0] = alice;
        aliceAmounts[0] = 10 * CRC;
        mockCircles.mockHub().groupMint(cmGroup, aliceCollateralAvatars, aliceAmounts, "");
        vm.stopPrank();

        // Have Bob mint 10 CRC - above tracking amount
        vm.startPrank(bob);
        address[] memory bobCollateralAvatars = new address[](1);
        uint256[] memory bobAmounts = new uint256[](1);
        bobCollateralAvatars[0] = bob;
        bobAmounts[0] = 10 * CRC;
        mockCircles.mockHub().groupMint(cmGroup, bobCollateralAvatars, bobAmounts, "");
        vm.stopPrank();

        // Both collateral amounts should be tracked
        (uint256[] memory collateralIdsAfterMints, uint256[] memory balancesAfterMints, uint256 totalLengthAfterMints) =
            ICMGRedemptionHandler(redemptionHandler).getActiveCollateral();

        assertEq(collateralIdsAfterMints.length, 2);
        assertEq(balancesAfterMints.length, 2);
        assertEq(totalLengthAfterMints, 2);

        // Have Bob redeem 7 CRC, taking Alice's CRC below tracking threshold
        vm.startPrank(bob);
        mockCircles.redemptionOperator().redeemWithFoundCollateral(cmGroup, 7 * CRC, false);
        vm.stopPrank();

        // Check collateral tracking - should only show Bob's collateral now
        (
            uint256[] memory collateralIdsAfterRedeem,
            uint256[] memory balancesAfterRedeem,
            uint256 totalLengthAfterRedeem
        ) = ICMGRedemptionHandler(redemptionHandler).getActiveCollateral();

        assertEq(collateralIdsAfterRedeem.length, 1);
        assertEq(balancesAfterRedeem.length, 1);
        assertEq(totalLengthAfterRedeem, 1);
        assertEq(collateralIdsAfterRedeem[0], bobId);
        assertEq(balancesAfterRedeem[0], 10 * CRC);
    }

    function testGroupMintCollateralWithMultipleSafeTransfers() public {
        testTrustAliceAndBob();

        // Have Alice send 340 CRC via safeTransfer
        vm.startPrank(alice);
        mockCircles.mockHub().safeTransferFrom(alice, ICoreMembersGroup(cmGroup).mintHandler(), aliceId, 340 * CRC, "");
        vm.stopPrank();

        // Have Bob send 410 CRC via safeTransfer
        vm.startPrank(bob);
        mockCircles.mockHub().safeTransferFrom(bob, ICoreMembersGroup(cmGroup).mintHandler(), bobId, 410 * CRC, "");
        vm.stopPrank();

        // Verify Alice's CRC was received and converted to group CRC
        assertEq(mockCircles.mockHub().balanceOf(alice, aliceId), 660 * CRC);
        assertEq(mockCircles.mockHub().balanceOf(alice, uint256(uint160(cmGroup))), 340 * CRC);

        // Verify Bob's CRC was received and converted to group CRC
        assertEq(mockCircles.mockHub().balanceOf(bob, bobId), 590 * CRC);
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
        assertEq(collateralIds[0], aliceId);
        assertEq(balances[0], 340 * CRC);
        assertEq(collateralIds[1], bobId);
        assertEq(balances[1], 410 * CRC);
    }

    function testDirectRedemptionViaCMGRedemptionOperator() public {
        testGroupMintCollateralWithGroupMint();

        // Have Alice redeem 75 of her CRC circles (collateral) from the group
        vm.startPrank(alice);
        uint256[] memory redemptionIds = new uint256[](1);
        uint256[] memory redemptionValues = new uint256[](1);
        redemptionIds[0] = aliceId; // Alice's own CRC id
        redemptionValues[0] = 75 * CRC;

        mockCircles.redemptionOperator().redeem(cmGroup, redemptionIds, redemptionValues);
        vm.stopPrank();

        // Verify Alice's balances after redemption
        // She minted 101 CRC into gCRC, then redeemed 75 CRC back
        assertEq(mockCircles.mockHub().balanceOf(alice, aliceId), 974 * CRC); // Original - minted + redeemed
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
        assertEq(collateralIds[0], aliceId);
        assertEq(collateralIds[1], bobId);

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
        assertEq(foundIds[0], aliceId);
        assertEq(foundAmounts[0], 340 * CRC);
        assertEq(foundIds[1], bobId);
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
        assertEq(preCollateralIds[0], aliceId);
        assertEq(preBalances[0], 340 * CRC);
        assertEq(preCollateralIds[1], bobId);
        assertEq(preBalances[1], 410 * CRC);

        // Have Alice redeem 370 CRC worth of collateral from the group automatically
        vm.startPrank(alice);
        mockCircles.redemptionOperator().redeemWithFoundCollateral(cmGroup, 370 * CRC, false);
        vm.stopPrank();

        // Verify Alice's summed balances after redemption
        uint256 aliceAliceCirclesBalance = mockCircles.mockHub().balanceOf(alice, aliceId);
        uint256 aliceBobCirclesBalance = mockCircles.mockHub().balanceOf(alice, bobId);

        // Started with 1000 CRC, minted 340 gCRC, received 410 gCRC from Bob, redeemed 370 gCRC worth
        // Initial gCRC balance: 340 + 410 = 750
        // Final gCRC balance: 750 - 370 = 380
        assertEq(mockCircles.mockHub().balanceOf(alice, uint256(uint160(cmGroup))), 380 * CRC);
        // Total collateral balance of personal Circles should be: 1000 aCRC - 340 aCRC + 370gCRC(redeemed) = 1030
        assertEq(aliceAliceCirclesBalance + aliceBobCirclesBalance, 1030 * CRC);

        // Verify Bob's balances - only his original CRC mint transaction should be reflected
        assertEq(mockCircles.mockHub().balanceOf(bob, bobId), 590 * CRC); // Original - minted
        assertEq(mockCircles.mockHub().balanceOf(bob, uint256(uint160(cmGroup))), 0); // Transferred all gCRC to Alice

        // Get redemption handler and check active collateral after redemption
        (uint256[] memory postCollateralIds, uint256[] memory postBalances, uint256 postTotalLength) =
            ICMGRedemptionHandler(redemptionHandler).getActiveCollateral();

        // Verify total tracked redemption IDs and balances after redemption
        assertEq(postCollateralIds.length, 1);
        assertEq(postBalances.length, 1);
        assertEq(postTotalLength, 1);

        // Verify collateral ID matches Bob's token ID (Alice's fully redeemed)
        assertEq(postCollateralIds[0], bobId);

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
        uint256 bobTotalPersonalCircles =
            mockCircles.mockHub().balanceOf(bob, bobId) + mockCircles.mockHub().balanceOf(bob, aliceId);
        assertEq(bobTotalPersonalCircles, 790 * CRC); // Original - minted + redeemed

        // Alice redeems all her remaining 550 gCRC
        vm.startPrank(alice);
        mockCircles.redemptionOperator().redeemWithFoundCollateral(cmGroup, 550 * CRC, false);
        vm.stopPrank();

        // Verify Alice's redemption
        assertEq(mockCircles.mockHub().balanceOf(alice, uint256(uint160(cmGroup))), 0); // All gCRC redeemed
        // Check Alice's total personal circles (original - minted + all redeemed)
        uint256 aliceTotalPersonalCircles =
            mockCircles.mockHub().balanceOf(alice, aliceId) + mockCircles.mockHub().balanceOf(alice, bobId);
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

        // Trust new users
        vm.startPrank(owner);
        ICoreMembersGroup(cmGroup).trust(charlie, type(uint96).max);
        ICoreMembersGroup(cmGroup).trust(david, type(uint96).max);
        ICoreMembersGroup(cmGroup).trust(els, type(uint96).max);
        vm.stopPrank();

        // Initial mints via safe transfers
        vm.startPrank(alice);
        mockCircles.mockHub().safeTransferFrom(alice, ICoreMembersGroup(cmGroup).mintHandler(), aliceId, 200 * CRC, "");
        vm.stopPrank();

        vm.startPrank(bob);
        mockCircles.mockHub().safeTransferFrom(bob, ICoreMembersGroup(cmGroup).mintHandler(), bobId, 300 * CRC, "");
        vm.stopPrank();

        vm.startPrank(charlie);
        mockCircles.mockHub().safeTransferFrom(
            charlie, ICoreMembersGroup(cmGroup).mintHandler(), charlieId, 400 * CRC, ""
        );
        vm.stopPrank();

        // First round of redemptions - Alice redeems 150 CRC
        // Get redemption handler and check cursor position
        address redemptionHandler = ICoreMembersGroup(cmGroup).redemptionHandler();
        uint256 cursorBefore = ICMGRedemptionHandler(redemptionHandler).cursor();

        (uint256[] memory foundIds1,) =
            ICMGRedemptionHandler(redemptionHandler).findCollateral(cmGroup, 150 * CRC, false);
        assertEq(foundIds1.length, 1); // Should find one collateral source

        vm.startPrank(alice);
        mockCircles.redemptionOperator().redeemWithFoundCollateral(cmGroup, 150 * CRC, false);
        vm.stopPrank();

        uint256 cursorAfterAlice = ICMGRedemptionHandler(redemptionHandler).cursor();
        assertEq(cursorAfterAlice, (cursorBefore + 1) % 3); // 3 active collateral sources

        // Charlie redeems 200 CRC, cursor should move past Alice's remaining position
        (uint256[] memory foundIds2,) =
            ICMGRedemptionHandler(redemptionHandler).findCollateral(cmGroup, 200 * CRC, false);
        assertEq(foundIds2.length, 1); // Should find one collateral source

        vm.startPrank(charlie);
        mockCircles.redemptionOperator().redeemWithFoundCollateral(cmGroup, 200 * CRC, false);
        vm.stopPrank();

        uint256 cursorAfterCharlie = ICMGRedemptionHandler(redemptionHandler).cursor();
        assertEq(cursorAfterCharlie, (cursorAfterAlice + 1) % 3);

        // Second round of mints
        vm.startPrank(els);
        mockCircles.mockHub().safeTransferFrom(els, ICoreMembersGroup(cmGroup).mintHandler(), elsId, 250 * CRC, "");
        vm.stopPrank();

        vm.startPrank(david);
        mockCircles.mockHub().safeTransferFrom(david, ICoreMembersGroup(cmGroup).mintHandler(), davidId, 350 * CRC, "");
        vm.stopPrank();

        // Bob redeems 200 CRC - cursor should move through previous positions
        uint256 cursorBeforeBob = ICMGRedemptionHandler(redemptionHandler).cursor();

        (uint256[] memory foundIds3,) =
            ICMGRedemptionHandler(redemptionHandler).findCollateral(cmGroup, 200 * CRC, false);
        assertEq(foundIds3.length, 1); // Should find one collateral source

        vm.startPrank(bob);
        mockCircles.redemptionOperator().redeemWithFoundCollateral(cmGroup, 200 * CRC, false);
        vm.stopPrank();

        uint256 cursorAfterBob = ICMGRedemptionHandler(redemptionHandler).cursor();
        assertEq(cursorAfterBob, (cursorBeforeBob + 1) % 5); // Now 5 active collateral sources

        // David redeems 150 CRC - cursor cycles further
        uint256 cursorBeforeDavid = ICMGRedemptionHandler(redemptionHandler).cursor();

        (uint256[] memory foundIds4,) =
            ICMGRedemptionHandler(redemptionHandler).findCollateral(cmGroup, 150 * CRC, false);
        assertEq(foundIds4.length, 1); // Should find one collateral source

        vm.startPrank(david);
        mockCircles.redemptionOperator().redeemWithFoundCollateral(cmGroup, 150 * CRC, false);
        vm.stopPrank();

        uint256 cursorAfterDavid = ICMGRedemptionHandler(redemptionHandler).cursor();
        assertEq(cursorAfterDavid, (cursorBeforeDavid + 1) % 5);

        // Final check of redemption handler state
        (uint256[] memory collateralIds, uint256[] memory balances, uint256 totalLength) =
            ICMGRedemptionHandler(redemptionHandler).getActiveCollateral();

        // Should have 5 active collateral sources
        assertEq(totalLength, 5);
        assertEq(collateralIds.length, 5);
        assertEq(balances.length, 5);

        // alice, bob and charlie are trivial

        assertEq(collateralIds[3], elsId);
        assertEq(balances[3], 100 * CRC); // 250 deposited - 150 withdrawn by David

        assertEq(collateralIds[4], davidId);
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

    function testCursorWrappingAroundWithRedemptions() public {
        testTrustAliceAndBob();

        // Trust Charlie
        vm.startPrank(owner);
        ICoreMembersGroup(cmGroup).trust(charlie, type(uint96).max);
        vm.stopPrank();

        // Give Alice, Bob and Charlie extra 2000 CRC each
        address[] memory users = new address[](3);
        users[0] = alice;
        users[1] = bob;
        users[2] = charlie;
        mockCircles.mockHub().personalMint(users, 2000 * CRC);

        // Each mints 2000 CRC into group
        vm.startPrank(alice);
        address[] memory collateralAvatars = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        collateralAvatars[0] = alice;
        amounts[0] = 2000 * CRC;
        mockCircles.mockHub().groupMint(cmGroup, collateralAvatars, amounts, "");
        vm.stopPrank();

        vm.startPrank(bob);
        collateralAvatars[0] = bob;
        mockCircles.mockHub().groupMint(cmGroup, collateralAvatars, amounts, "");
        vm.stopPrank();

        vm.startPrank(charlie);
        collateralAvatars[0] = charlie;
        mockCircles.mockHub().groupMint(cmGroup, collateralAvatars, amounts, "");
        vm.stopPrank();

        // Transfer all gCRC to David (6000 total)
        vm.startPrank(alice);
        mockCircles.mockHub().safeTransferFrom(alice, david, uint256(uint160(cmGroup)), 2000 * CRC, "");
        vm.stopPrank();

        vm.startPrank(bob);
        mockCircles.mockHub().safeTransferFrom(bob, david, uint256(uint160(cmGroup)), 2000 * CRC, "");
        vm.stopPrank();

        vm.startPrank(charlie);
        mockCircles.mockHub().safeTransferFrom(charlie, david, uint256(uint160(cmGroup)), 2000 * CRC, "");
        vm.stopPrank();

        // David redeems first 6000 gCRC partially fillable, but max 3x 500 gCRC will be found
        vm.startPrank(david);
        mockCircles.redemptionOperator().redeemWithFoundCollateral(cmGroup, 6000 * CRC, true);

        // Get redemption handler
        address redemptionHandler = ICoreMembersGroup(cmGroup).redemptionHandler();

        // Check cursor position after first redemption
        uint256 cursorAfterFirst = ICMGRedemptionHandler(redemptionHandler).cursor();
        assertEq(cursorAfterFirst, 0); // Should be back at start

        // David redeems 400 more gCRC - should get from Alice since cursor wrapped to start
        (uint256[] memory foundIds,) =
            ICMGRedemptionHandler(redemptionHandler).findCollateral(cmGroup, 400 * CRC, false);
        assertEq(foundIds.length, 1);
        assertEq(foundIds[0], aliceId);

        mockCircles.redemptionOperator().redeemWithFoundCollateral(cmGroup, 400 * CRC, false);
        vm.stopPrank();

        // Verify final state
        (uint256[] memory collateralIds, uint256[] memory balances,) =
            ICMGRedemptionHandler(redemptionHandler).getActiveCollateral();

        // All three collateral sources should still be active
        assertEq(collateralIds.length, 3);

        // Check balances match expected
        assertEq(balances[0], 1100 * CRC); // Alice: 2000 - 500 - 400 = 1100
        assertEq(balances[1], 1500 * CRC); // Bob: 2000 - 500 = 1500
        assertEq(balances[2], 1500 * CRC); // Charlie: 2000 - 500 = 1500
    }

    function testFindCollateralWithCursorWrappingOnRedemptionOperator() public {
        testTrustAliceAndBob();

        // Trust remaining users
        vm.startPrank(owner);
        ICoreMembersGroup(cmGroup).trust(charlie, type(uint96).max);
        ICoreMembersGroup(cmGroup).trust(david, type(uint96).max);
        ICoreMembersGroup(cmGroup).trust(els, type(uint96).max);
        vm.stopPrank();

        // Mint additional 1000 CRC for each user
        address[] memory users = new address[](5);
        users[0] = alice;
        users[1] = bob;
        users[2] = charlie;
        users[3] = david;
        users[4] = els;
        mockCircles.mockHub().personalMint(users, 1000 * CRC);

        // Each user mints 1000 CRC into group
        address[] memory collateralAvatars = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 2000 * CRC;

        vm.startPrank(alice);
        collateralAvatars[0] = alice;
        mockCircles.mockHub().groupMint(cmGroup, collateralAvatars, amounts, "");
        vm.stopPrank();

        vm.startPrank(bob);
        collateralAvatars[0] = bob;
        mockCircles.mockHub().groupMint(cmGroup, collateralAvatars, amounts, "");
        vm.stopPrank();

        vm.startPrank(charlie);
        collateralAvatars[0] = charlie;
        mockCircles.mockHub().groupMint(cmGroup, collateralAvatars, amounts, "");
        vm.stopPrank();

        vm.startPrank(david);
        collateralAvatars[0] = david;
        mockCircles.mockHub().groupMint(cmGroup, collateralAvatars, amounts, "");
        vm.stopPrank();

        vm.startPrank(els);
        collateralAvatars[0] = els;
        mockCircles.mockHub().groupMint(cmGroup, collateralAvatars, amounts, "");
        vm.stopPrank();

        // Get redemption handler address
        address redemptionHandler = ICoreMembersGroup(cmGroup).redemptionHandler();

        // Check cursor position and active collateral before redemption
        uint256 initialCursor = ICMGRedemptionHandler(redemptionHandler).cursor();

        // Check active collateral array to see the order
        (,, uint256 initialLength) = ICMGRedemptionHandler(redemptionHandler).getActiveCollateral();

        // Verify all 5 users' collateral is tracked
        assertEq(initialLength, 5);

        // Transfer CRC to enable redemptions
        // Bob transfers 1500 gCRC to David
        vm.startPrank(bob);
        mockCircles.mockHub().safeTransferFrom(bob, david, uint256(uint160(cmGroup)), 1500 * CRC, "");
        vm.stopPrank();

        // Charlie transfers 2000 gCRC to Els
        vm.startPrank(charlie);
        mockCircles.mockHub().safeTransferFrom(charlie, els, uint256(uint160(cmGroup)), 2000 * CRC, "");
        vm.stopPrank();

        // David redeems 1500 gCRC (should move cursor forward 3 positions due to MAX_REDEEM_PER_ID of 500)
        vm.startPrank(david);
        mockCircles.redemptionOperator().redeemWithFoundCollateral(cmGroup, 1500 * CRC, false);
        vm.stopPrank();

        // Check cursor position after David's redemption
        uint256 cursorAfterDavid = ICMGRedemptionHandler(redemptionHandler).cursor();

        // Expected cursor after David's redemption: (initialCursor + 3) % 5
        uint256 expectedCursorAfterDavid = (initialCursor + 3) % 5;
        assertEq(cursorAfterDavid, expectedCursorAfterDavid);

        // Els redeems 2000 gCRC (should move cursor forward 4 positions, wrapping around to the first position)
        vm.startPrank(els);
        mockCircles.redemptionOperator().redeemWithFoundCollateral(cmGroup, 2000 * CRC, false);
        vm.stopPrank();

        // Check cursor position after Els's redemption
        uint256 cursorAfterEls = ICMGRedemptionHandler(redemptionHandler).cursor();

        // Expected cursor after Els's redemption: (cursorAfterDavid + 4) % 5, which should equal initialCursor
        uint256 expectedCursorAfterEls = (cursorAfterDavid + 4) % 5;

        // The cursor has wrapped around
        assertEq(cursorAfterEls, expectedCursorAfterEls);

        // Verify the collateral is partially depleted from redemptions
        (, uint256[] memory finalBalances, uint256 finalLength) =
            ICMGRedemptionHandler(redemptionHandler).getActiveCollateral();

        // Should still have all 5 collateral sources
        assertEq(finalLength, 5);

        // Find total remaining collateral
        uint256 totalRemainingCollateral = 0;
        for (uint256 i = 0; i < finalLength; i++) {
            totalRemainingCollateral += finalBalances[i];
        }

        // Expected total: 5*2000 CRC initial - 3500 CRC redeemed = 6500 CRC
        assertEq(totalRemainingCollateral, 6500 * CRC);
    }
}
