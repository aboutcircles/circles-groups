// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import {Test} from "forge-std/Test.sol";
import "test/mock-circles/MockCirclesFactoryDeployment.sol";
import "src/membership-conditions/IsHumanCondition.sol";

contract CoreMembersGroupTest is Test {
    // Constants
    uint256 public constant CRC = 1e18;

    // State
    MockCirclesFactoryDeployment public mockCircles;
    IsHumanCondition public isHumanCondition;

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
        isHumanCondition = new IsHumanCondition(address(mockCircles.mockHub()));

        // Register users as people
        mockCircles.mockHub().registerHuman(alice, 1000 * CRC);
        mockCircles.mockHub().registerHuman(bob, 1000 * CRC);
        mockCircles.mockHub().registerHuman(charlie, 1000 * CRC);
        mockCircles.mockHub().registerHuman(david, 1000 * CRC);
    }

    function testDeployAndInitialize() public {
        address[] memory initialConditions = new address[](1);
        initialConditions[0] = address(isHumanCondition);

        vm.startPrank(owner);
        (cmGroup,,) = mockCircles.createCMGroup(owner, service, initialConditions, "TestCMG", "CMG", bytes32(0));
        vm.stopPrank();

        // Verify owner is set correctly
        assertEq(ICoreMembersGroup(cmGroup).owner(), owner);

        // Verify service is set correctly
        assertEq(ICoreMembersGroup(cmGroup).service(), service);

        // Verify handlers were set
        address mintHandler = ICoreMembersGroup(cmGroup).mintHandler();
        address redemptionHandler = ICoreMembersGroup(cmGroup).redemptionHandler();
        assertTrue(mintHandler != address(0));
        assertTrue(redemptionHandler != address(0));

        // Verify minimal deposit was set to zero
        assertEq(ICoreMembersGroup(cmGroup).minimalDeposit(), 0);
    }

    function testChangeOwner() public {
        testDeployAndInitialize();

        vm.startPrank(owner);
        ICoreMembersGroup(cmGroup).setOwner(alice);
        vm.stopPrank();

        assertEq(ICoreMembersGroup(cmGroup).owner(), alice);

        // Old owner can no longer call owner functions
        vm.startPrank(owner);
        vm.expectRevert();
        ICoreMembersGroup(cmGroup).setOwner(bob);
        vm.stopPrank();

        // New owner can call owner functions
        vm.startPrank(alice);
        ICoreMembersGroup(cmGroup).setOwner(bob);
        vm.stopPrank();

        assertEq(ICoreMembersGroup(cmGroup).owner(), bob);
    }

    function testChangeService() public {
        testDeployAndInitialize();

        vm.startPrank(owner);
        ICoreMembersGroup(cmGroup).setService(alice);
        vm.stopPrank();

        assertEq(ICoreMembersGroup(cmGroup).service(), alice);

        // Old service can no longer call service functions
        vm.startPrank(service);
        vm.expectRevert();
        ICoreMembersGroup(cmGroup).trustBatchWithConditions(new address[](0), 0);
        vm.stopPrank();

        // New service can call service functions
        vm.startPrank(alice);
        address[] memory members = new address[](1);
        members[0] = bob;
        ICoreMembersGroup(cmGroup).trustBatchWithConditions(members, type(uint96).max);
        vm.stopPrank();

        assertTrue(mockCircles.mockHub().isTrusted(cmGroup, bob));
    }

    function testChangeMinimalDeposit() public {
        testDeployAndInitialize();

        vm.startPrank(owner);
        ICoreMembersGroup(cmGroup).setMinimalDeposit(10 ** 14);
        vm.stopPrank();

        assertEq(ICoreMembersGroup(cmGroup).minimalDeposit(), 10 ** 14);

        // Can set to zero
        vm.startPrank(owner);
        ICoreMembersGroup(cmGroup).setMinimalDeposit(0);
        vm.stopPrank();

        assertEq(ICoreMembersGroup(cmGroup).minimalDeposit(), 0);

        // Cannot set above max allowed
        vm.startPrank(owner);
        vm.expectRevert();
        ICoreMembersGroup(cmGroup).setMinimalDeposit(10 ** 16);
        vm.stopPrank();
    }

    function testChangeMembershipConditions() public {
        testDeployAndInitialize();

        // Verify initial conditions
        address[] memory initialConditions = ICoreMembersGroup(cmGroup).getMembershipConditions();
        assertEq(initialConditions.length, 1);
        assertEq(initialConditions[0], address(isHumanCondition));

        // Can disable condition
        vm.startPrank(owner);
        ICoreMembersGroup(cmGroup).setMembershipCondition(address(isHumanCondition), false);
        vm.stopPrank();

        // Verify condition was removed
        address[] memory afterDisableConditions = ICoreMembersGroup(cmGroup).getMembershipConditions();
        assertEq(afterDisableConditions.length, 0);

        // Can re-enable condition
        vm.startPrank(owner);
        ICoreMembersGroup(cmGroup).setMembershipCondition(address(isHumanCondition), true);
        vm.stopPrank();

        // Verify condition was re-added
        address[] memory afterEnableConditions = ICoreMembersGroup(cmGroup).getMembershipConditions();
        assertEq(afterEnableConditions.length, 1);
        assertEq(afterEnableConditions[0], address(isHumanCondition));

        // adding same condition twice only counts once
        vm.startPrank(owner);
        ICoreMembersGroup(cmGroup).setMembershipCondition(address(isHumanCondition), true);
        vm.stopPrank();

        // Verify only one condition exists
        address[] memory afterDoubleAddConditions = ICoreMembersGroup(cmGroup).getMembershipConditions();
        assertEq(afterDoubleAddConditions.length, 1);
        assertEq(afterDoubleAddConditions[0], address(isHumanCondition));

        // Try adding 9 more conditions (already have 1)
        vm.startPrank(owner);
        address[] memory newConditions = new address[](9);
        for (uint256 i = 0; i < 9; i++) {
            address condition = makeAddr(string.concat("condition", vm.toString(i)));
            newConditions[i] = condition;
            ICoreMembersGroup(cmGroup).setMembershipCondition(condition, true);
        }

        // Verify all 10 conditions were added
        address[] memory allConditions = ICoreMembersGroup(cmGroup).getMembershipConditions();
        assertEq(allConditions.length, 10);
        assertEq(allConditions[0], address(isHumanCondition));
        for (uint256 i = 0; i < 9; i++) {
            assertEq(allConditions[i + 1], newConditions[i]);
        }

        // Try to add 11th condition - should fail since already at max of 10
        vm.expectRevert();
        ICoreMembersGroup(cmGroup).setMembershipCondition(makeAddr("failCondition"), true);
        vm.stopPrank();

        // Verify conditions remain unchanged after failed addition
        address[] memory finalConditions = ICoreMembersGroup(cmGroup).getMembershipConditions();
        assertEq(finalConditions.length, 10);
        assertEq(finalConditions[0], address(isHumanCondition));
        for (uint256 i = 0; i < 9; i++) {
            assertEq(finalConditions[i + 1], newConditions[i]);
        }
    }

    function testTrustByOwner() public {
        testDeployAndInitialize();

        vm.startPrank(owner);
        ICoreMembersGroup(cmGroup).trust(alice, type(uint96).max);
        vm.stopPrank();

        assertTrue(mockCircles.mockHub().isTrusted(cmGroup, alice));

        // Trust is mirrored to mint handler
        address mintHandler = ICoreMembersGroup(cmGroup).mintHandler();
        assertTrue(mockCircles.mockHub().isTrusted(mintHandler, alice));
    }

    function testTrustBatchByService() public {
        testDeployAndInitialize();

        address[] memory members = new address[](3);
        members[0] = alice;
        members[1] = bob;
        members[2] = charlie;

        vm.startPrank(service);
        ICoreMembersGroup(cmGroup).trustBatchWithConditions(members, type(uint96).max);
        vm.stopPrank();

        assertTrue(mockCircles.mockHub().isTrusted(cmGroup, alice));
        assertTrue(mockCircles.mockHub().isTrusted(cmGroup, bob));
        assertTrue(mockCircles.mockHub().isTrusted(cmGroup, charlie));

        // Trust is mirrored to mint handler for all
        address mintHandler = ICoreMembersGroup(cmGroup).mintHandler();
        assertTrue(mockCircles.mockHub().isTrusted(mintHandler, alice));
        assertTrue(mockCircles.mockHub().isTrusted(mintHandler, bob));
        assertTrue(mockCircles.mockHub().isTrusted(mintHandler, charlie));
    }

    function testUntrustBatchByService() public {
        testTrustBatchByService();

        address[] memory members = new address[](3);
        members[0] = alice;
        members[1] = bob;
        members[2] = charlie;

        vm.startPrank(service);
        // Set expiry to past timestamp to untrust
        ICoreMembersGroup(cmGroup).trustBatchWithConditions(members, uint96(block.timestamp));
        vm.stopPrank();

        // move the timestamp ahead to let untrust take effect
        vm.warp(block.timestamp + 1);

        assertFalse(mockCircles.mockHub().isTrusted(cmGroup, alice));
        assertFalse(mockCircles.mockHub().isTrusted(cmGroup, bob));
        assertFalse(mockCircles.mockHub().isTrusted(cmGroup, charlie));

        // Untrust is mirrored to mint handler
        address mintHandler = ICoreMembersGroup(cmGroup).mintHandler();
        assertFalse(mockCircles.mockHub().isTrusted(mintHandler, alice));
        assertFalse(mockCircles.mockHub().isTrusted(mintHandler, bob));
        assertFalse(mockCircles.mockHub().isTrusted(mintHandler, charlie));
    }

    function testMintPolicy() public {
        testDeployAndInitialize();

        vm.startPrank(owner);
        ICoreMembersGroup(cmGroup).trust(alice, type(uint96).max);
        vm.stopPrank();

        // Prepare mint params
        address[] memory collateralAvatars = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        collateralAvatars[0] = alice;
        amounts[0] = 100 * CRC;

        vm.startPrank(alice);
        mockCircles.mockHub().groupMint(cmGroup, collateralAvatars, amounts, "");
        vm.stopPrank();

        // Verify Alice's balances
        assertEq(mockCircles.mockHub().balanceOf(alice, aliceId), 900 * CRC);
        assertEq(mockCircles.mockHub().balanceOf(alice, uint256(uint160(cmGroup))), 100 * CRC);
    }

    function testMintPolicyRejectsUntrusted() public {
        testDeployAndInitialize();

        // Try mint without trust
        address[] memory collateralAvatars = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        collateralAvatars[0] = alice;
        amounts[0] = 100 * CRC;

        vm.startPrank(alice);
        MockHub hub = mockCircles.mockHub();
        vm.expectRevert();
        hub.groupMint(cmGroup, collateralAvatars, amounts, "");
        vm.stopPrank();
    }

    function testMintPolicyRejectsLowAmount() public {
        testDeployAndInitialize();

        vm.startPrank(owner);
        ICoreMembersGroup(cmGroup).setMinimalDeposit(10 ** 15);
        ICoreMembersGroup(cmGroup).trust(alice, type(uint96).max);
        vm.stopPrank();

        // Try mint below minimal deposit
        address[] memory collateralAvatars = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        collateralAvatars[0] = alice;
        amounts[0] = 10 ** 14; // Below 10**15 minimum

        vm.startPrank(alice);
        MockHub hub = mockCircles.mockHub();
        vm.expectRevert();
        hub.groupMint(cmGroup, collateralAvatars, amounts, "");
        vm.stopPrank();
    }
}
