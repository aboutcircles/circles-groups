// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import {Test, Vm} from "forge-std/Test.sol";
import "test/mock-circles/MockCirclesDeployment.sol";
import "src/liquidity-provider/helpers/GroupLiquidityProviderDeployer.sol";
import "src/liquidity-provider/helpers/GroupLiquidityProviderDeployer.sol";

contract GroupLiquidityProviderTest is Test {
    // Constants
    uint256 public constant CRC = 1e18;

    // State
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
    address public liquidityProvider;

    // Token IDs
    uint256 public aliceId;
    uint256 public bobId;
    uint256 public charlieId;
    uint256 public davidId;
    uint256 public elsId;
    uint256 public cmGroupId;

    function setUp() public {
        // Create test addresses
        owner = makeAddr("owner");
        service = makeAddr("service");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");
        david = makeAddr("david");
        els = makeAddr("els");

        mockCircles = new MockCirclesDeployment();

        // Register users as people
        mockCircles.mockHub().registerHuman(alice, 1000 * CRC);
        mockCircles.mockHub().registerHuman(bob, 1000 * CRC);
        mockCircles.mockHub().registerHuman(charlie, 1000 * CRC);
        mockCircles.mockHub().registerHuman(david, 1000 * CRC);
        mockCircles.mockHub().registerHuman(els, 1000 * CRC);

        // Store token IDs
        aliceId = uint256(uint160(alice));
        bobId = uint256(uint160(bob));
        charlieId = uint256(uint160(charlie));
        davidId = uint256(uint160(david));
        elsId = uint256(uint160(els));
    }

    function testCreateCoreMembersGroupWithLiquidityProvider() public {
        // Deploy core members group
        address[] memory noInitialConditions = new address[](0);

        vm.startPrank(owner);
        (cmGroup,,, liquidityProvider) =
            mockCircles.createCMGroup(service, noInitialConditions, "TestCMG", "CMG", bytes32(0));
        vm.stopPrank();

        cmGroupId = uint256(uint160(cmGroup));

        // Verify LP was created and setup correctly
        assertTrue(liquidityProvider != address(0));
        assertTrue(mockCircles.mockHub().isOrganization(liquidityProvider));
        assertTrue(mockCircles.mockHub().isTrusted(liquidityProvider, cmGroup));
    }

    function testProviderStartsWithoutGcrc() public {
        testCreateCoreMembersGroupWithLiquidityProvider();

        // Check initial gCRC balance is 0
        assertEq(mockCircles.mockHub().balanceOf(liquidityProvider, cmGroupId), 0);
    }

    function testSetupWithValidAddresses() public {
        vm.startPrank(owner);
        (cmGroup,,,) = mockCircles.createCMGroup(service, new address[](0), "TestCMG", "CMG", bytes32(0));
        liquidityProvider = mockCircles.lpDeployer().createLiquidityProvider(cmGroup, "LP", bytes32(0));
        vm.stopPrank();

        // Verify group and owner set correctly
        assertEq(GroupLiquidityProvider(liquidityProvider).group(), cmGroup);
        assertEq(GroupLiquidityProvider(liquidityProvider).owner(), owner);
    }

    function testOnlyOwnerCanSendCirclesToLP() public {
        testSetupWithValidAddresses();

        MockHub hub = mockCircles.mockHub();

        uint256 amount = 100 * CRC;

        // Alice tries to send CRC to LP directly (should fail)
        vm.startPrank(alice);
        vm.expectRevert();
        hub.safeTransferFrom(alice, liquidityProvider, aliceId, amount, "");
        vm.stopPrank();

        // First transfer CRC to owner
        vm.startPrank(alice);
        hub.safeTransferFrom(alice, owner, aliceId, amount, "");
        vm.stopPrank();

        // Owner can send to LP
        vm.startPrank(owner);
        hub.safeTransferFrom(owner, liquidityProvider, aliceId, amount, "");
        vm.stopPrank();

        // Verify balances
        assertEq(hub.balanceOf(alice, aliceId), 900 * CRC);
        assertEq(hub.balanceOf(owner, aliceId), 0);
        assertEq(hub.balanceOf(liquidityProvider, aliceId), amount);
    }

    function testOnlyOwnerCanBatchSendCirclesToLP() public {
        testSetupWithValidAddresses();

        MockHub hub = mockCircles.mockHub();

        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        ids[0] = aliceId;
        ids[1] = bobId;
        amounts[0] = 100 * CRC;
        amounts[1] = 200 * CRC;

        // Alice tries to send batch to LP directly (should fail)
        vm.startPrank(alice);
        vm.expectRevert();
        hub.safeBatchTransferFrom(alice, liquidityProvider, ids, amounts, "");
        vm.stopPrank();

        // First transfer CRC from Alice and Bob to owner
        vm.startPrank(alice);
        hub.safeTransferFrom(alice, owner, aliceId, 100 * CRC, "");
        vm.stopPrank();

        vm.startPrank(bob);
        hub.safeTransferFrom(bob, owner, bobId, 200 * CRC, "");
        vm.stopPrank();

        // Owner can batch send to LP
        vm.startPrank(owner);
        hub.safeBatchTransferFrom(owner, liquidityProvider, ids, amounts, "");
        vm.stopPrank();

        // Verify balances
        assertEq(hub.balanceOf(alice, aliceId), 900 * CRC);
        assertEq(hub.balanceOf(bob, bobId), 800 * CRC);
        assertEq(hub.balanceOf(owner, aliceId), 0);
        assertEq(hub.balanceOf(owner, bobId), 0);
        assertEq(hub.balanceOf(liquidityProvider, aliceId), 100 * CRC);
        assertEq(hub.balanceOf(liquidityProvider, bobId), 200 * CRC);
    }

    function testOnlyOwnerCanTransfer() public {
        testSetupWithValidAddresses();

        // First transfer some CRC to owner
        uint256 amount = 100 * CRC;
        vm.startPrank(alice);
        mockCircles.mockHub().safeTransferFrom(alice, owner, aliceId, amount, "");
        vm.stopPrank();

        // Owner sends to LP
        vm.startPrank(owner);
        mockCircles.mockHub().safeTransferFrom(owner, liquidityProvider, aliceId, amount, "");
        vm.stopPrank();

        // Non-owner tries to transfer LP's tokens (should fail)
        vm.startPrank(alice);
        vm.expectRevert();
        GroupLiquidityProvider(liquidityProvider).safeTransferFrom(liquidityProvider, bob, aliceId, amount, "");
        vm.stopPrank();

        // LP can only transfer its own tokens
        vm.startPrank(owner);
        vm.expectRevert();
        GroupLiquidityProvider(liquidityProvider).safeTransferFrom(alice, bob, aliceId, amount, "");
        vm.stopPrank();

        // Owner can transfer LP's tokens
        vm.startPrank(owner);
        GroupLiquidityProvider(liquidityProvider).safeTransferFrom(liquidityProvider, bob, aliceId, amount, "");
        vm.stopPrank();

        // Verify transfer
        assertEq(mockCircles.mockHub().balanceOf(liquidityProvider, aliceId), 0);
        assertEq(mockCircles.mockHub().balanceOf(bob, aliceId), amount);
    }

    // function testOnlyOwnerCanBatchTransfer() public {
    //     testSetupWithValidAddresses();

    //     // Trust both users
    //     vm.startPrank(owner);
    //     ICoreMembersGroup(cmGroup).trust(alice, type(uint96).max);
    //     ICoreMembersGroup(cmGroup).trust(bob, type(uint96).max);
    //     vm.stopPrank();

    //     // Mint and send tokens to LP
    //     address[] memory collateralAvatars = new address[](2);
    //     uint256[] memory amounts = new uint256[](2);
    //     collateralAvatars[0] = alice;
    //     collateralAvatars[1] = bob;
    //     amounts[0] = 100 * CRC;
    //     amounts[1] = 200 * CRC;

    //     // Mint from Alice
    //     vm.startPrank(alice);
    //     mockCircles.mockHub().groupMint(cmGroup, collateralAvatars, amounts, "");
    //     mockCircles.mockHub().safeTransferFrom(alice, liquidityProvider, cmGroupId, 100 * CRC, "");
    //     vm.stopPrank();

    //     // Mint from Bob
    //     vm.startPrank(bob);
    //     mockCircles.mockHub().safeTransferFrom(bob, liquidityProvider, cmGroupId, 100 * CRC, "");
    //     vm.stopPrank();

    //     // Non-owner tries batch transfer (should fail)
    //     uint256[] memory ids = new uint256[](2);
    //     ids[0] = cmGroupId;
    //     ids[1] = cmGroupId;
    //     uint256[] memory transferAmounts = new uint256[](2);
    //     transferAmounts[0] = 50 * CRC;
    //     transferAmounts[1] = 50 * CRC;

    //     vm.startPrank(alice);
    //     vm.expectRevert();
    //     GroupLiquidityProvider(liquidityProvider).safeBatchTransferFrom(
    //         liquidityProvider, bob, ids, transferAmounts, ""
    //     );
    //     vm.stopPrank();

    //     // Owner can batch transfer
    //     vm.startPrank(owner);
    //     GroupLiquidityProvider(liquidityProvider).safeBatchTransferFrom(
    //         liquidityProvider, bob, ids, transferAmounts, ""
    //     );
    //     vm.stopPrank();

    //     // Verify transfer
    //     assertEq(mockCircles.mockHub().balanceOf(liquidityProvider, cmGroupId), 100 * CRC);
    //     assertEq(mockCircles.mockHub().balanceOf(bob, cmGroupId), 100 * CRC + 100 * CRC);
    // }

    // function testCannotTransferOtherAccountsTokens() public {
    //     testSetupWithValidAddresses();

    //     vm.startPrank(owner);
    //     vm.expectRevert("GroupLiquidityProvider: can only transfer own tokens");
    //     GroupLiquidityProvider(liquidityProvider).safeTransferFrom(alice, bob, cmGroupId, 100 * CRC, "");
    //     vm.stopPrank();

    //     // Same for batch transfers
    //     uint256[] memory ids = new uint256[](1);
    //     uint256[] memory amounts = new uint256[](1);
    //     ids[0] = cmGroupId;
    //     amounts[0] = 100 * CRC;

    //     vm.startPrank(owner);
    //     vm.expectRevert("GroupLiquidityProvider: can only transfer own tokens");
    //     GroupLiquidityProvider(liquidityProvider).safeBatchTransferFrom(alice, bob, ids, amounts, "");
    //     vm.stopPrank();
    // }

    // function testProviderCanReceiveGcrc() public {
    //     testSetupWithValidAddresses();

    //     // Trust and mint first
    //     vm.startPrank(owner);
    //     ICoreMembersGroup(cmGroup).trust(alice, type(uint96).max);
    //     vm.stopPrank();

    //     address[] memory collateralAvatars = new address[](1);
    //     uint256[] memory amounts = new uint256[](1);
    //     collateralAvatars[0] = alice;
    //     amounts[0] = 100 * CRC;

    //     vm.startPrank(alice);
    //     mockCircles.mockHub().groupMint(cmGroup, collateralAvatars, amounts, "");
    //     mockCircles.mockHub().safeTransferFrom(alice, liquidityProvider, cmGroupId, 100 * CRC, "");
    //     vm.stopPrank();

    //     assertEq(mockCircles.mockHub().balanceOf(liquidityProvider, cmGroupId), 100 * CRC);
    // }

    // function testFirstRebalancingWithSingleCollateral() public {
    //     testProviderCanReceiveGcrc();

    //     // Check pre-rebalance gCRC balance
    //     uint256 preBalance = mockCircles.mockHub().balanceOf(liquidityProvider, cmGroupId);
    //     assertEq(preBalance, 100 * CRC);

    //     // Anyone can call rebalance
    //     vm.startPrank(alice);
    //     GroupLiquidityProvider(liquidityProvider).rebalance();
    //     vm.stopPrank();

    //     // Verify balance decreased
    //     uint256 postBalance = mockCircles.mockHub().balanceOf(liquidityProvider, cmGroupId);
    //     assertTrue(postBalance < preBalance);

    //     // Verify LP has collateral balance now
    //     uint256 collateralBalance = mockCircles.mockHub().balanceOf(liquidityProvider, aliceId);
    //     assertTrue(collateralBalance > 0);
    // }

    // function testRebalancingDoesNothingWithoutBalance() public {
    //     testSetupWithValidAddresses();

    //     // Try rebalancing with 0 balance
    //     vm.startPrank(alice);
    //     GroupLiquidityProvider(liquidityProvider).rebalance();
    //     vm.stopPrank();

    //     // Verify no changes
    //     assertEq(mockCircles.mockHub().balanceOf(liquidityProvider, cmGroupId), 0);
    // }
}
