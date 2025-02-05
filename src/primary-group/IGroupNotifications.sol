// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

interface IGroupNotifications {
    /// @notice Called when a human unsubscribes from this group as their primary group
    /// @param human The address of the human who unsubscribed
    function onHumanUnsubscribedAsPrimaryGroup(address human) external;

    /// @notice Called when a human subscribes to this group as their primary group
    /// @param human The address of the human who subscribed
    function onHumanSubscribedAsPrimaryGroup(address human) external;
}
