// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

interface IGroupNotifications {
    /// @notice Called when a human unsubscribes from this group as their affiliate group
    /// @param human The address of the human who unsubscribed
    function onHumanUnsubscribedAsAffiliateGroup(address human) external;

    /// @notice Called when a human subscribes to this group as their affiliate group
    /// @param human The address of the human who subscribed
    function onHumanSubscribedAsAffiliateGroup(address human) external;
}
