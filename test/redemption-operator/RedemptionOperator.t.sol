// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import {Test} from "forge-std/Test.sol";
import "test/mock-circles/MockCirclesFactoryDeployment.sol";

contract RedemptionOperatorTest is Test {
    // Constants
    uint256 public constant CRC = 1e18;

    // State
    MockCirclesFactoryDeployment public mockCircles;

    // Test addresses
    address public cmGroup;
    address public owner;
    address public service;
    address public alice;
    address public bob;
    address public charlie;
    address public david;

    // Token IDs
    uint256 public aliceId;
    uint256 public bobId;
    uint256 public charlieId;
    uint256 public davidId;

    function setUp() public {
        // Create test addresses
        owner = makeAddr("owner");
        service = makeAddr("service");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");
        david = makeAddr("david");

        // Store token IDs
        aliceId = uint256(uint160(alice));
        bobId = uint256(uint160(bob));
        charlieId = uint256(uint160(charlie));
        davidId = uint256(uint160(david));

        mockCircles = new MockCirclesFactoryDeployment();

        // Register users as people
        mockCircles.mockHub().registerHuman(alice, 1000 * CRC);
        mockCircles.mockHub().registerHuman(bob, 1000 * CRC);
        mockCircles.mockHub().registerHuman(charlie, 1000 * CRC);
        mockCircles.mockHub().registerHuman(david, 1000 * CRC);

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
    }

    function testCreateCMGroupForRedemptions() public {
        address[] memory noInitialConditions = new address[](0);

        vm.startPrank(owner);
        (cmGroup,,) =
            mockCircles.createCMGroup(owner, service, noInitialConditions, "NoConditionsCMG", "CMG", bytes32(0));
        vm.stopPrank();

        // Verify group was created
        assertTrue(mockCircles.mockHub().isGroup(cmGroup));
    }

    function testRedemptionOperatorDirectRedeem() public {
        testCreateCMGroupForRedemptions();

        // Trust Alice and have her deposit collateral
        vm.startPrank(owner);
        ICoreMembersGroup(cmGroup).trust(alice, type(uint96).max);
        vm.stopPrank();

        vm.startPrank(alice);
        address[] memory collateralAvatars = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        collateralAvatars[0] = alice;
        amounts[0] = 300 * CRC;
        mockCircles.mockHub().groupMint(cmGroup, collateralAvatars, amounts, "");
        vm.stopPrank();

        // Have Alice redeem 100 CRC directly
        vm.startPrank(alice);
        uint256[] memory redemptionIds = new uint256[](1);
        uint256[] memory redemptionValues = new uint256[](1);
        redemptionIds[0] = aliceId;
        redemptionValues[0] = 100 * CRC;

        mockCircles.redemptionOperator().redeem(cmGroup, redemptionIds, redemptionValues);
        vm.stopPrank();

        // Verify balances after redemption
        assertEq(mockCircles.mockHub().balanceOf(alice, aliceId), 800 * CRC); // 1000 - 300 + 100
        assertEq(mockCircles.mockHub().balanceOf(alice, uint256(uint160(cmGroup))), 200 * CRC); // 300 - 100
    }

    function testRedemptionOperatorRedeemWithFoundCollateral() public {
        testCreateCMGroupForRedemptions();

        // Trust multiple users and have them deposit collateral
        vm.startPrank(owner);
        ICoreMembersGroup(cmGroup).trust(alice, type(uint96).max);
        ICoreMembersGroup(cmGroup).trust(bob, type(uint96).max);
        ICoreMembersGroup(cmGroup).trust(charlie, type(uint96).max);
        vm.stopPrank();

        // Have users deposit varying amounts
        vm.startPrank(alice);
        address[] memory collateralAvatars = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        collateralAvatars[0] = alice;
        amounts[0] = 200 * CRC;
        mockCircles.mockHub().groupMint(cmGroup, collateralAvatars, amounts, "");
        vm.stopPrank();

        vm.startPrank(bob);
        collateralAvatars[0] = bob;
        amounts[0] = 300 * CRC;
        mockCircles.mockHub().groupMint(cmGroup, collateralAvatars, amounts, "");
        vm.stopPrank();

        vm.startPrank(charlie);
        collateralAvatars[0] = charlie;
        amounts[0] = 400 * CRC;
        mockCircles.mockHub().groupMint(cmGroup, collateralAvatars, amounts, "");
        vm.stopPrank();

        // Transfer all gCRC to David for redemption
        vm.startPrank(alice);
        mockCircles.mockHub().safeTransferFrom(alice, david, uint256(uint160(cmGroup)), 200 * CRC, "");
        vm.stopPrank();

        vm.startPrank(bob);
        mockCircles.mockHub().safeTransferFrom(bob, david, uint256(uint160(cmGroup)), 300 * CRC, "");
        vm.stopPrank();

        vm.startPrank(charlie);
        mockCircles.mockHub().safeTransferFrom(charlie, david, uint256(uint160(cmGroup)), 400 * CRC, "");
        vm.stopPrank();

        // David redeems 500 CRC using found collateral
        vm.startPrank(david);
        mockCircles.redemptionOperator().redeemWithFoundCollateral(cmGroup, 500 * CRC, false);
        vm.stopPrank();

        // Verify David's balances
        assertEq(mockCircles.mockHub().balanceOf(david, uint256(uint160(cmGroup))), 400 * CRC); // 900 - 500
        uint256 davidTotalCollateral = mockCircles.mockHub().balanceOf(david, aliceId)
            + mockCircles.mockHub().balanceOf(david, bobId) + mockCircles.mockHub().balanceOf(david, charlieId);
        assertEq(davidTotalCollateral, 500 * CRC);
    }

    function testRedemptionOperatorPartialFillRedemption() public {
        testCreateCMGroupForRedemptions();

        // Trust Alice and have her deposit limited collateral
        vm.startPrank(owner);
        ICoreMembersGroup(cmGroup).trust(alice, type(uint96).max);
        vm.stopPrank();

        vm.startPrank(alice);
        address[] memory collateralAvatars = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        collateralAvatars[0] = alice;
        amounts[0] = 100 * CRC;
        mockCircles.mockHub().groupMint(cmGroup, collateralAvatars, amounts, "");
        vm.stopPrank();

        // Try to redeem more than available but allow partial fills
        vm.startPrank(alice);
        mockCircles.redemptionOperator().redeemWithFoundCollateral(cmGroup, 200 * CRC, true);
        vm.stopPrank();

        // Verify partial redemption occurred
        assertEq(mockCircles.mockHub().balanceOf(alice, aliceId), 1000 * CRC); // Original - minted + redeemed
        assertEq(mockCircles.mockHub().balanceOf(alice, uint256(uint160(cmGroup))), 0); // All redeemed
    }

    function testRedemptionOperatorRevertOnInsufficientCollateral() public {
        testCreateCMGroupForRedemptions();

        // Trust Alice and have her deposit limited collateral
        vm.startPrank(owner);
        ICoreMembersGroup(cmGroup).trust(alice, type(uint96).max);
        vm.stopPrank();

        vm.startPrank(alice);
        address[] memory collateralAvatars = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        collateralAvatars[0] = alice;
        amounts[0] = 100 * CRC;
        mockCircles.mockHub().groupMint(cmGroup, collateralAvatars, amounts, "");
        vm.stopPrank();

        // Try to redeem more than available and don't allow partial fills
        vm.startPrank(alice);
        CMGRedemptionOperator operator = mockCircles.redemptionOperator();
        vm.expectRevert();
        operator.redeemWithFoundCollateral(cmGroup, 200 * CRC, false);
        vm.stopPrank();

        // Verify no redemption occurred
        assertEq(mockCircles.mockHub().balanceOf(alice, aliceId), 900 * CRC); // Only minted amount withdrawn
        assertEq(mockCircles.mockHub().balanceOf(alice, uint256(uint160(cmGroup))), 100 * CRC); // No redemption
    }

    function testRedemptionOperatorRevertOnUnregisteredGroup() public {
        // Try to redeem from non-existent group
        address fakeGroup = makeAddr("fakeGroup");

        vm.startPrank(alice);
        uint256[] memory redemptionIds = new uint256[](1);
        uint256[] memory redemptionValues = new uint256[](1);
        redemptionIds[0] = aliceId;
        redemptionValues[0] = 100 * CRC;
        CMGRedemptionOperator operator = mockCircles.redemptionOperator();
        vm.expectRevert();
        operator.redeem(fakeGroup, redemptionIds, redemptionValues);
        vm.stopPrank();
    }

    function testRedemptionOperatorHandlesMultipleCollateralTypes() public {
        testCreateCMGroupForRedemptions();

        // Trust multiple users
        vm.startPrank(owner);
        ICoreMembersGroup(cmGroup).trust(alice, type(uint96).max);
        ICoreMembersGroup(cmGroup).trust(bob, type(uint96).max);
        vm.stopPrank();

        // Have Alice and Bob deposit collateral
        vm.startPrank(alice);
        address[] memory collateralAvatars = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        collateralAvatars[0] = alice;
        amounts[0] = 300 * CRC;
        mockCircles.mockHub().groupMint(cmGroup, collateralAvatars, amounts, "");
        vm.stopPrank();

        vm.startPrank(bob);
        collateralAvatars[0] = bob;
        amounts[0] = 400 * CRC;
        mockCircles.mockHub().groupMint(cmGroup, collateralAvatars, amounts, "");
        vm.stopPrank();

        // Transfer all gCRC to Charlie for redemption
        vm.startPrank(alice);
        mockCircles.mockHub().safeTransferFrom(alice, charlie, uint256(uint160(cmGroup)), 300 * CRC, "");
        vm.stopPrank();

        vm.startPrank(bob);
        mockCircles.mockHub().safeTransferFrom(bob, charlie, uint256(uint160(cmGroup)), 400 * CRC, "");
        vm.stopPrank();

        // Charlie redeems using found collateral
        vm.startPrank(charlie);
        mockCircles.redemptionOperator().redeemWithFoundCollateral(cmGroup, 600 * CRC, false);
        vm.stopPrank();

        // Verify Charlie received mix of collateral types
        uint256 charlieAliceCircles = mockCircles.mockHub().balanceOf(charlie, aliceId);
        uint256 charlieBobCircles = mockCircles.mockHub().balanceOf(charlie, bobId);
        assertTrue(charlieAliceCircles > 0 && charlieBobCircles > 0);
        assertEq(charlieAliceCircles + charlieBobCircles, 600 * CRC);
    }
}
