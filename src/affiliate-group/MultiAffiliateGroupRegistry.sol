// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "src/circles/IHub.sol";

/**
 * @title MultiAffiliateGroupRegistry
 * @notice Lets each human avatar maintain its own list of affiliate groups.
 * @dev Per-avatar affiliations are stored as a singly-linked list keyed by the avatar address.
 *      The list is prepend-ordered (most recently added first) and circular through {SENTINEL}:
 *      - `affiliateGroupList[avatar][SENTINEL]` points to the head (most recently added group);
 *      - `affiliateGroupList[avatar][group]` points to the next group in the list;
 *      - the tail group points back to {SENTINEL};
 *      - an empty list is represented by `affiliateGroupList[avatar][SENTINEL] == address(0)`.
 */
contract MultiAffiliateGroupRegistry {
    // State

    /// @notice Circles Hub v2.
    IHub public constant hub = IHub(0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8);

    /// @notice Sentinel node used as the head/tail boundary of each avatar's linked list.
    address constant SENTINEL = address(0x01);

    /// @notice Per-avatar linked list of affiliate groups.
    /// @dev `affiliateGroupList[avatar][node]` returns the node that follows `node` in `avatar`'s list.
    ///      Read `affiliateGroupList[avatar][SENTINEL]` to get the head and walk until {SENTINEL} is reached.
    mapping(address => mapping(address => address)) public affiliateGroupList;

    /// @notice Emitted when `avatar` adds `affiliateGroup` to its list.
    /// @param affiliateGroup The group that was added.
    /// @param avatar The human avatar that owns the list.
    event AffiliateGroupAdded(address affiliateGroup, address avatar);

    /// @notice Emitted when `avatar` removes `affiliateGroup` from its list.
    /// @param affiliateGroup The group that was removed.
    /// @param avatar The human avatar that owns the list.
    event AffiliateGroupRemoved(address affiliateGroup, address avatar);

    /// @notice Thrown when an affiliate group is not a registered Circles group, or is absent from the caller's list.
    /// @param affiliateGroup The offending group address.
    error AffiliateGroupNotExist(address affiliateGroup);

    /// @notice Thrown when the caller is not a registered human avatar on the Hub.
    /// @param caller The address that attempted the call.
    error IsNotHuman(address caller);

    /// @notice Adds `affiliateGroupToAdd` to the caller's affiliate group list.
    /// @dev Caller must be a registered human avatar and `affiliateGroupToAdd` must be a registered group on the Hub.
    ///      The group is prepended as the new head. Adding a group already present is a no-op (an event is still emitted).
    /// @param affiliateGroupToAdd The Circles group to affiliate with the caller.
    function addAffiliateGroup(address affiliateGroupToAdd) external {
        if (!hub.isHuman(msg.sender)) revert IsNotHuman(msg.sender);
        if (!hub.isGroup(affiliateGroupToAdd)) revert AffiliateGroupNotExist(affiliateGroupToAdd);

        if (affiliateGroupList[msg.sender][affiliateGroupToAdd] == address(0)) {
            // if it is empty

            if (affiliateGroupList[msg.sender][SENTINEL] == address(0)) {
                // empty list
                affiliateGroupList[msg.sender][SENTINEL] = affiliateGroupToAdd;
                affiliateGroupList[msg.sender][affiliateGroupToAdd] = SENTINEL;
            } else {
                address lastInsertedGroup = affiliateGroupList[msg.sender][SENTINEL];
                affiliateGroupList[msg.sender][SENTINEL] = affiliateGroupToAdd;
                affiliateGroupList[msg.sender][affiliateGroupToAdd] = lastInsertedGroup;
            }
        }

        emit AffiliateGroupAdded(affiliateGroupToAdd, msg.sender);
    }

    /// @notice Removes `affiliateGroupToRemove` from the caller's affiliate group list.
    /// @dev Unlinks the node by pointing its predecessor at its successor. When the removed group is the
    ///      only element, the list is reset to the empty-list invariant (`affiliateGroupList[caller][SENTINEL] == 0`).
    ///      Reverts with {AffiliateGroupNotExist} if the group is not present in the caller's list.
    /// @param affiliateGroupToRemove The Circles group to remove from the caller's list.
    function removeAffiliateGroup(address affiliateGroupToRemove) external {
        if (
            affiliateGroupToRemove == SENTINEL || affiliateGroupToRemove == address(0)
                || affiliateGroupList[msg.sender][affiliateGroupToRemove] == address(0)
        ) revert AffiliateGroupNotExist(affiliateGroupToRemove);

        address prev = SENTINEL;
        while (affiliateGroupList[msg.sender][prev] != affiliateGroupToRemove) {
            prev = affiliateGroupList[msg.sender][prev];
        }
        address next = affiliateGroupList[msg.sender][affiliateGroupToRemove];
        // last element: collapse back to the empty-list invariant (list[SENTINEL] == 0)
        affiliateGroupList[msg.sender][prev] = (prev == SENTINEL && next == SENTINEL) ? address(0) : next;
        affiliateGroupList[msg.sender][affiliateGroupToRemove] = address(0);

        emit AffiliateGroupRemoved(affiliateGroupToRemove, msg.sender);
    }
}
