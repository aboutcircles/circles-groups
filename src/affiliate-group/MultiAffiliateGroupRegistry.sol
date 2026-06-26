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

    /// @notice Account that deployed the registry and is allowed to seed it via {initialize}.
    address public deployer;

    /// @notice Whether seeding has been permanently locked. Once true, {initialize} reverts forever.
    bool public isInitialized;

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

    /// @notice Address is not recognized as a human by the Hub.
    error OnlyHuman();

    /// @notice Caller is not the {deployer}.
    error SenderNotDeployer();

    /// @notice The `avatars` and `affiliateGroup` arrays passed to {initialize} have different lengths.
    error ArrayLengthMismatch();

    /// @notice Seeding has already been locked via {lockInitialization}; {initialize} can no longer be called.
    error AlreadyInitialized();

    /// @dev Restricts a function to the {deployer}.
    modifier onlyDeployer() {
        if (msg.sender != deployer) revert SenderNotDeployer();
        _;
    }

    /// @dev Records the deploying account as the {deployer}, the only account permitted to seed the registry.
    constructor() {
        deployer = msg.sender;
    }

    /// @notice Seeds the registry with initial avatar/affiliate-group pairs, in batches.
    /// @dev Callable only by the {deployer} and only while seeding is unlocked (`isInitialized == false`).
    ///      May be called repeatedly to seed across multiple transactions; each `avatars[i]` is set to a
    ///      single-element list `[affiliateGroup[i]]`, overwriting any existing list for that avatar.
    ///      Intended for one-time bulk seeding at deployment; call {lockInitialization} when done.
    /// @param avatars The human avatars to seed; must be the same length as `affiliateGroup`.
    /// @param affiliateGroup The affiliate group to assign to the avatar at the same index.
    function initialize(address[] memory avatars, address[] memory affiliateGroup) external onlyDeployer {
        if (avatars.length != affiliateGroup.length) revert ArrayLengthMismatch();
        if (isInitialized) revert AlreadyInitialized();

        for (uint256 i = 0; i < avatars.length; i++) {
            affiliateGroupList[avatars[i]][SENTINEL] = affiliateGroup[i];
            affiliateGroupList[avatars[i]][affiliateGroup[i]] = SENTINEL;
            emit AffiliateGroupAdded(affiliateGroup[i], avatars[i]);
        }
    }

    /// @notice Permanently disables {initialize}, ending the seeding phase.
    /// @dev Callable only by the {deployer}. Irreversible: there is no function that unsets `isInitialized`.
    function lockInitialization() external onlyDeployer {
        isInitialized = true;
    }

    /// @notice Adds `affiliateGroupToAdd` to the caller's affiliate group list.
    /// @dev Caller must be a registered human avatar and `affiliateGroupToAdd` must be a registered group on the Hub.
    ///      The group is prepended as the new head. Adding a group already present is a no-op (no state change, no event).
    /// @param affiliateGroupToAdd The Circles group to affiliate with the caller.
    function addAffiliateGroup(address affiliateGroupToAdd) external {
        if (!hub.isHuman(msg.sender)) revert OnlyHuman();
        if (!hub.isGroup(affiliateGroupToAdd)) revert AffiliateGroupNotExist(affiliateGroupToAdd);
        if (affiliateGroupList[msg.sender][affiliateGroupToAdd] != address(0)) return; // group already exist
        if (affiliateGroupList[msg.sender][affiliateGroupToAdd] == address(0)) {
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
