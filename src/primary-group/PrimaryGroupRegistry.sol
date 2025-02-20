// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "src/circles/Core.sol";
import "src/circles/IHub.sol";
import "src/errors/Errors.sol";
import "src/primary-group/IGroupNotifications.sol";

/// @title PrimaryGroupRegistry
/// @author Martin Köppelmann, Benjamin Bollen
/// @notice A simple registry mapping Circles humans (msg.sender) to their chosen primary group.
/// When a human sets (or changes) their primary group, both the old group (if any) and the new group (if any)
/// are notified by calling onHumanRemoved and onHumanAdded respectively, with a 100k gas limit.
/// If the group contract does not implement these functions, the calls fail silently.
contract PrimaryGroupRegistry is CirclesCoreAddresses, ICMGPrimaryGroupRegistryErrors {
    // State

    /// @notice Core Circles protocol addresses
    CirclesCore public circlesCore;

    /// @notice Mapping from a human to their primary group.
    mapping(address => address) public primaryGroup;

    // Events

    /// @notice Emitted when a human changes their primary group.
    event PrimaryGroupChanged(address indexed human, address oldGroup, address newGroup);

    /// @notice Emitted when a notification to a group fails
    event NotificationFailed(address indexed group, address indexed human);

    /// @notice Emitted when a notification to a group succeeds
    event NotificationSuccessful(address indexed group, address indexed human);

    // Constructor

    constructor(CirclesCore memory _circlesCore) {
        circlesCore = _circlesCore;
    }

    // External functions

    /// @notice Sets or changes the primary group for the caller.
    /// @param newGroup The address of the new primary group. A zero address clears the primary group.
    function setPrimaryGroup(address newGroup) external {
        address oldGroup = primaryGroup[msg.sender];

        // If the new group is the same as the current group, do nothing.
        if (oldGroup == newGroup) {
            return;
        }

        if (!circlesCore.hub.isHuman(msg.sender) || !circlesCore.hub.isGroup(newGroup)) {
            revert CMGPrimaryGroupMustBeHumanAndGroupToRegisterPrimaryGroup(msg.sender, newGroup);
        }

        // Update the primary group registry.
        primaryGroup[msg.sender] = newGroup;

        // Notify the old group that the human was removed.
        if (oldGroup != address(0)) {
            try IGroupNotifications(oldGroup).onHumanUnsubscribedAsPrimaryGroup{gas: 100000}(msg.sender) {
                emit NotificationSuccessful(oldGroup, msg.sender);
            } catch {
                emit NotificationFailed(oldGroup, msg.sender);
            }
        }

        // Notify the new group that the human was added.
        if (newGroup != address(0)) {
            try IGroupNotifications(newGroup).onHumanSubscribedAsPrimaryGroup{gas: 100000}(msg.sender) {
                emit NotificationSuccessful(newGroup, msg.sender);
            } catch {
                emit NotificationFailed(newGroup, msg.sender);
            }
        }

        emit PrimaryGroupChanged(msg.sender, oldGroup, newGroup);
    }
}
