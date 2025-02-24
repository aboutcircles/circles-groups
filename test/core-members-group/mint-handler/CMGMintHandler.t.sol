// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import {Test} from "forge-std/Test.sol";
import "test/mock-circles/MockCirclesDeployment.sol";

contract CMGMintHandlerTest is Test {
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

        mockCircles = new MockCirclesDeployment();

        // Register users as people
        mockCircles.mockHub().registerHuman(alice, 1000 * CRC);
        mockCircles.mockHub().registerHuman(bob, 1000 * CRC);
        mockCircles.mockHub().registerHuman(charlie, 1000 * CRC);
        mockCircles.mockHub().registerHuman(david, 1000 * CRC);
    }

    function testCreateCoreMembersGroupWithoutInitialConditions() public {
        address[] memory noInitialConditions = new address[](0);

        vm.startPrank(owner);
        cmGroup = mockCircles.createCMGroup(service, noInitialConditions, "NoConditionsCMG", "CMG", bytes32(0));

        // Verify owner is set correctly
        assertEq(ICoreMembersGroup(cmGroup).owner(), owner);

        // Verify mint handler was set
        address mintHandler = ICoreMembersGroup(cmGroup).mintHandler();
        assertTrue(mintHandler != address(0));
    }

    function testTrustMirroringBetweenGroupAndHandler() public {
        testCreateCoreMembersGroupWithoutInitialConditions();

        // Trust Alice from group
        vm.startPrank(owner);
        ICoreMembersGroup(cmGroup).trust(alice, type(uint96).max);
        vm.stopPrank();

        // Verify trust was mirrored to handler
        address mintHandler = ICoreMembersGroup(cmGroup).mintHandler();
        assertTrue(mockCircles.mockHub().isTrusted(mintHandler, alice));
    }

    function testSyncTrustFromGroup() public {
        testCreateCoreMembersGroupWithoutInitialConditions();

        // Get mint handler from earlier deployment
        address mintHandler = ICoreMembersGroup(cmGroup).mintHandler();
        ICMGMintHandler handler = ICMGMintHandler(mintHandler);

        // Set mint handler to zero address so trust isn't auto-mirrored
        vm.startPrank(owner);
        ICoreMembersGroup(cmGroup).setMintHandler(address(0));

        // Trust multiple users in group (without auto-mirroring)
        ICoreMembersGroup(cmGroup).trust(alice, type(uint96).max);
        ICoreMembersGroup(cmGroup).trust(bob, type(uint96).max);
        ICoreMembersGroup(cmGroup).trust(charlie, type(uint96).max);
        vm.stopPrank();
        // Create array of addresses to sync including untrusted David
        address[] memory addressesToSync = new address[](4);
        addressesToSync[0] = alice;
        addressesToSync[1] = bob;
        addressesToSync[2] = charlie;
        addressesToSync[3] = david;

        // // Sync trust from group
        handler.syncTrust(addressesToSync);

        // Verify trusted addresses were synced
        assertTrue(mockCircles.mockHub().isTrusted(mintHandler, alice));
        assertTrue(mockCircles.mockHub().isTrusted(mintHandler, bob));
        assertTrue(mockCircles.mockHub().isTrusted(mintHandler, charlie));

        // Verify untrusted David was not synced
        assertFalse(mockCircles.mockHub().isTrusted(mintHandler, david));
    }

    function testMintHandlerReceivesAndConvertsCircles() public {
        testTrustMirroringBetweenGroupAndHandler();

        // Have Alice send 100 of her CRC to mint handler
        vm.startPrank(alice);
        mockCircles.mockHub().safeTransferFrom(alice, ICoreMembersGroup(cmGroup).mintHandler(), aliceId, 100 * CRC, "");
        vm.stopPrank();

        // Verify Alice's CRC was received and converted to group CRC
        assertEq(mockCircles.mockHub().balanceOf(alice, aliceId), 900 * CRC);
        assertEq(mockCircles.mockHub().balanceOf(alice, uint256(uint160(cmGroup))), 100 * CRC);
    }

    function testMintHandlerRevertOnUntrustedSender() public {
        testCreateCoreMembersGroupWithoutInitialConditions();

        address mintHandler = ICoreMembersGroup(cmGroup).mintHandler();
        MockHub hub = mockCircles.mockHub();

        // Attempt transfer from untrusted Bob should revert
        vm.startPrank(bob);
        vm.expectRevert(); // Add expect revert before transfer
        hub.safeTransferFrom(bob, mintHandler, bobId, 100 * CRC, "");
        vm.stopPrank();

        // Verify balances unchanged after failed transfer
        assertEq(hub.balanceOf(bob, bobId), 1000 * CRC);
        assertEq(hub.balanceOf(mintHandler, bobId), 0);
        assertEq(hub.balanceOf(bob, uint256(uint160(cmGroup))), 0);
    }

    function testMintHandlerReceiveMultipleDeposits() public {
        testTrustMirroringBetweenGroupAndHandler();

        // Trust Bob as well
        vm.startPrank(owner);
        ICoreMembersGroup(cmGroup).trust(bob, type(uint96).max);
        vm.stopPrank();

        // Have Alice and Bob both send CRC
        vm.startPrank(alice);
        mockCircles.mockHub().safeTransferFrom(alice, ICoreMembersGroup(cmGroup).mintHandler(), aliceId, 100 * CRC, "");
        vm.stopPrank();

        vm.startPrank(bob);
        mockCircles.mockHub().safeTransferFrom(bob, ICoreMembersGroup(cmGroup).mintHandler(), bobId, 200 * CRC, "");
        vm.stopPrank();

        // Verify both balances were updated correctly
        assertEq(mockCircles.mockHub().balanceOf(alice, aliceId), 900 * CRC);
        assertEq(mockCircles.mockHub().balanceOf(alice, uint256(uint160(cmGroup))), 100 * CRC);
        assertEq(mockCircles.mockHub().balanceOf(bob, bobId), 800 * CRC);
        assertEq(mockCircles.mockHub().balanceOf(bob, uint256(uint160(cmGroup))), 200 * CRC);
    }

    function testMintHandlerReceivesBatchTransfer() public {
        testTrustMirroringBetweenGroupAndHandler();

        address mintHandler = ICoreMembersGroup(cmGroup).mintHandler();

        // Create batch transfer parameters
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        ids[0] = aliceId;
        ids[1] = aliceId;
        amounts[0] = 100 * CRC;
        amounts[1] = 200 * CRC;

        // Send batch transfer from Alice
        vm.startPrank(alice);
        mockCircles.mockHub().safeBatchTransferFrom(alice, mintHandler, ids, amounts, "");
        vm.stopPrank();

        // Verify Alice's balances were updated
        assertEq(mockCircles.mockHub().balanceOf(alice, aliceId), 700 * CRC);
        assertEq(mockCircles.mockHub().balanceOf(alice, uint256(uint160(cmGroup))), 300 * CRC);
    }
}
