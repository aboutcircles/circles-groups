// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import {MultiAffiliateGroupRegistry} from "../../src/affiliate-group/MultiAffiliateGroupRegistry.sol";
import {Test, console} from "forge-std/Test.sol";
import {IHub} from "../../src/circles/IHub.sol";

// Run this in a fork test forge test --rpc-url https://rpc.gnosischain.com --match-contract MultiAffiliateGroupRegistryTest

contract MultiAffiliateGroupRegistryTest is Test {
    event AffiliateGroupAdded(address affiliateGroup, address avatar);
    event AffiliateGroupRemoved(address affiliateGroup, address avatar);

    error AffiliateGroupNotExist(address affiliateGroup);
    error OnlyHuman();
    address constant SENTINEL = address(0x01);

    IHub hub = IHub(0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8);

    MultiAffiliateGroupRegistry registry;

    address backerGrp = 0x1ACA75e38263c79d9D4F10dF0635cc6FCfe6F026;
    address oicGrp = 0x4E2564e5df6C1Fb10C1A018538de36E4D5844DE5;
    address fullNodeGrp = 0xEb614eF61367687704CD4628a68A02F3B10ce68C;
    address avatar = 0x42cEDde51198D1773590311E2A340DC06B24cB37;
    address fakeAvatar = makeAddr("fakeAvatar");
    address fakeGrp = makeAddr("fakeGrp");

    function setUp() public {
        // sanity check
        require(hub.isHuman(avatar), "avatar is not human");
        require(hub.isGroup(backerGrp), "backerGrp is not a group");
        require(hub.isGroup(oicGrp), "oicGrp is not a group");
        require(hub.isGroup(fullNodeGrp), "fullNodeGrp is not a group");
        require(!hub.isHuman(fakeAvatar) && !hub.isGroup(fakeGrp), "invalid setup");

        registry = new MultiAffiliateGroupRegistry();
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Walk `user`'s linked list and assert it equals `expected` (head-first) and is correctly terminated.
    function _assertList(address user, address[] memory expected) internal view {
        address node = registry.affiliateGroupList(user, SENTINEL);
        for (uint256 i = 0; i < expected.length; i++) {
            assertEq(node, expected[i], "list order mismatch");
            node = registry.affiliateGroupList(user, node);
        }
        // Non-empty list terminates by pointing back to SENTINEL; empty list has a zeroed head.
        assertEq(node, expected.length == 0 ? address(0) : SENTINEL, "list terminator mismatch");
    }

    /// @dev Seed `avatar`'s list with [fullNodeGrp, oicGrp, backerGrp] (head -> tail).
    function _seedThree() internal {
        vm.startPrank(avatar);
        registry.addAffiliateGroup(backerGrp);
        registry.addAffiliateGroup(oicGrp);
        registry.addAffiliateGroup(fullNodeGrp);
        vm.stopPrank();

        address[] memory expected = new address[](3);
        expected[0] = fullNodeGrp;
        expected[1] = oicGrp;
        expected[2] = backerGrp;
        _assertList(avatar, expected);
    }

    /*//////////////////////////////////////////////////////////////
                                  ADD
    //////////////////////////////////////////////////////////////*/

    function testRevert_AddWhenNotHuman() public {
        vm.prank(fakeAvatar);
        vm.expectRevert(OnlyHuman.selector);
        registry.addAffiliateGroup(backerGrp);
    }

    function testRevert_AddWhenNotGroup() public {
        vm.prank(avatar);
        vm.expectRevert(abi.encodeWithSelector(AffiliateGroupNotExist.selector, fakeGrp));
        registry.addAffiliateGroup(fakeGrp);
    }

    function testAddAffiliateGroup() public {
        // add backer -> [backer]
        vm.expectEmit(false, false, false, true, address(registry));
        emit AffiliateGroupAdded(backerGrp, avatar);
        vm.prank(avatar);
        registry.addAffiliateGroup(backerGrp);

        address[] memory afterBacker = new address[](1);
        afterBacker[0] = backerGrp;
        _assertList(avatar, afterBacker);

        // add oic -> prepended -> [oic, backer]
        vm.expectEmit(false, false, false, true, address(registry));
        emit AffiliateGroupAdded(oicGrp, avatar);
        vm.prank(avatar);
        registry.addAffiliateGroup(oicGrp);

        // add fullNode -> prepended -> [fullNode, oic, backer]
        vm.expectEmit(false, false, false, true, address(registry));
        emit AffiliateGroupAdded(fullNodeGrp, avatar);
        vm.prank(avatar);
        registry.addAffiliateGroup(fullNodeGrp);

        address[] memory expected = new address[](3);
        expected[0] = fullNodeGrp;
        expected[1] = oicGrp;
        expected[2] = backerGrp;
        _assertList(avatar, expected);

        // explicit pointer checks for the linked-list layout
        assertEq(registry.affiliateGroupList(avatar, SENTINEL), fullNodeGrp, "head");
        assertEq(registry.affiliateGroupList(avatar, fullNodeGrp), oicGrp, "fullNode -> oic");
        assertEq(registry.affiliateGroupList(avatar, oicGrp), backerGrp, "oic -> backer");
        assertEq(registry.affiliateGroupList(avatar, backerGrp), SENTINEL, "backer -> tail");
    }

    function testAddDuplicateIsNoOp() public {
        _seedThree();

        // Re-adding an existing group early-returns: no state change and no event.
        vm.recordLogs();
        vm.prank(avatar);
        registry.addAffiliateGroup(backerGrp);
        assertEq(vm.getRecordedLogs().length, 0, "duplicate add must not emit");

        address[] memory expected = new address[](3);
        expected[0] = fullNodeGrp;
        expected[1] = oicGrp;
        expected[2] = backerGrp;
        _assertList(avatar, expected);
    }

    /*//////////////////////////////////////////////////////////////
                                REMOVE
    //////////////////////////////////////////////////////////////*/

    function testRevert_RemoveSentinel() public {
        _seedThree();
        vm.prank(avatar);
        vm.expectRevert(abi.encodeWithSelector(AffiliateGroupNotExist.selector, SENTINEL));
        registry.removeAffiliateGroup(SENTINEL);
    }

    function testRevert_RemoveZeroAddress() public {
        _seedThree();
        vm.prank(avatar);
        vm.expectRevert(abi.encodeWithSelector(AffiliateGroupNotExist.selector, address(0)));
        registry.removeAffiliateGroup(address(0));
    }

    function testRevert_RemoveNotInList() public {
        _seedThree();
        // A valid group that was never added.
        vm.prank(avatar);
        vm.expectRevert(abi.encodeWithSelector(AffiliateGroupNotExist.selector, fakeGrp));
        registry.removeAffiliateGroup(fakeGrp);
    }

    function testRevert_RemoveFromEmptyList() public {
        vm.prank(avatar);
        vm.expectRevert(abi.encodeWithSelector(AffiliateGroupNotExist.selector, backerGrp));
        registry.removeAffiliateGroup(backerGrp);
    }

    /// @dev Remove the head (prev == SENTINEL, next != SENTINEL).
    function testRemoveHead() public {
        _seedThree();

        vm.expectEmit(false, false, false, true, address(registry));
        emit AffiliateGroupRemoved(fullNodeGrp, avatar);
        vm.prank(avatar);
        registry.removeAffiliateGroup(fullNodeGrp);

        address[] memory expected = new address[](2);
        expected[0] = oicGrp;
        expected[1] = backerGrp;
        _assertList(avatar, expected);
        assertEq(registry.affiliateGroupList(avatar, fullNodeGrp), address(0), "removed node cleared");
    }

    /// @dev Remove a middle node (prev != SENTINEL, next != SENTINEL).
    function testRemoveMiddle() public {
        _seedThree();

        vm.expectEmit(false, false, false, true, address(registry));
        emit AffiliateGroupRemoved(oicGrp, avatar);
        vm.prank(avatar);
        registry.removeAffiliateGroup(oicGrp);

        address[] memory expected = new address[](2);
        expected[0] = fullNodeGrp;
        expected[1] = backerGrp;
        _assertList(avatar, expected);
        assertEq(registry.affiliateGroupList(avatar, fullNodeGrp), backerGrp, "predecessor relinked");
        assertEq(registry.affiliateGroupList(avatar, oicGrp), address(0), "removed node cleared");
    }

    /// @dev Remove the tail (prev != SENTINEL, next == SENTINEL).
    function testRemoveTail() public {
        _seedThree();

        vm.expectEmit(false, false, false, true, address(registry));
        emit AffiliateGroupRemoved(backerGrp, avatar);
        vm.prank(avatar);
        registry.removeAffiliateGroup(backerGrp);

        address[] memory expected = new address[](2);
        expected[0] = fullNodeGrp;
        expected[1] = oicGrp;
        _assertList(avatar, expected);
        assertEq(registry.affiliateGroupList(avatar, oicGrp), SENTINEL, "new tail points to sentinel");
        assertEq(registry.affiliateGroupList(avatar, backerGrp), address(0), "removed node cleared");
    }

    /// @dev Remove the only element (prev == SENTINEL, next == SENTINEL) -> collapse to empty invariant.
    function testRemoveSoleElement() public {
        vm.prank(avatar);
        registry.addAffiliateGroup(backerGrp);

        vm.expectEmit(false, false, false, true, address(registry));
        emit AffiliateGroupRemoved(backerGrp, avatar);
        vm.prank(avatar);
        registry.removeAffiliateGroup(backerGrp);

        // The empty-list invariant must hold: head pointer is zeroed (not left as SENTINEL).
        assertEq(registry.affiliateGroupList(avatar, SENTINEL), address(0), "head reset to zero");
        assertEq(registry.affiliateGroupList(avatar, backerGrp), address(0), "removed node cleared");
        address[] memory empty = new address[](0);
        _assertList(avatar, empty);
    }

    /// @dev After emptying the list, adding again must rebuild a clean single-element list.
    function testAddAfterEmptyingRebuildsList() public {
        vm.startPrank(avatar);
        registry.addAffiliateGroup(backerGrp);
        registry.removeAffiliateGroup(backerGrp);
        registry.addAffiliateGroup(oicGrp);
        vm.stopPrank();

        address[] memory expected = new address[](1);
        expected[0] = oicGrp;
        _assertList(avatar, expected);
    }

    /// @dev Removing then re-adding the head yields the same membership set (order may differ).
    function testRemoveThenReaddHead() public {
        _seedThree();

        vm.startPrank(avatar);
        registry.removeAffiliateGroup(backerGrp);
        registry.addAffiliateGroup(backerGrp); // prepended again
        vm.stopPrank();

        address[] memory expected = new address[](3);
        expected[1] = fullNodeGrp;
        expected[2] = oicGrp;
        expected[0] = backerGrp;
        _assertList(avatar, expected);
    }

    /*//////////////////////////////////////////////////////////////
                            SEED / INITIALIZE
    //////////////////////////////////////////////////////////////*/

    /// @dev Exercises the full seed/lock lifecycle: deployer seeds in multiple batches,
    ///      non-deployer is rejected, and seeding is permanently disabled after lockInitialization().
    function test_seedAndSetInitialized() public {
        // --- batch 1 (deployer == address(this)) ---
        address[] memory a1 = new address[](1);
        address[] memory g1 = new address[](1);
        a1[0] = avatar;
        g1[0] = backerGrp;
        registry.initialize(a1, g1);

        address[] memory exp1 = new address[](1);
        exp1[0] = backerGrp;
        _assertList(avatar, exp1); // seeded as a one-element list

        // --- batch 2 must still succeed before locking ---
        address[] memory a2 = new address[](1);
        address[] memory g2 = new address[](1);
        a2[0] = fakeAvatar;
        g2[0] = oicGrp;
        registry.initialize(a2, g2);

        address[] memory exp2 = new address[](1);
        exp2[0] = oicGrp;
        _assertList(fakeAvatar, exp2);

        // --- non-deployer cannot seed or lock (onlyDeployer) ---
        vm.startPrank(fakeAvatar);
        vm.expectRevert(MultiAffiliateGroupRegistry.SenderNotDeployer.selector);
        registry.initialize(a1, g1);
        vm.expectRevert(MultiAffiliateGroupRegistry.SenderNotDeployer.selector);
        registry.lockInitialization();
        vm.stopPrank();

        // --- length-mismatch guard ---
        address[] memory bad = new address[](2);
        vm.expectRevert(MultiAffiliateGroupRegistry.ArrayLengthMismatch.selector);
        registry.initialize(bad, g1);

        // --- lock seeding (deployer) ---
        registry.lockInitialization();

        // --- seeding is now permanently disabled ---
        vm.expectRevert(MultiAffiliateGroupRegistry.AlreadyInitialized.selector);
        registry.initialize(a1, g1);

        // previously seeded state is untouched by the failed call
        _assertList(avatar, exp1);
    }
}
