// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "src/circles/Core.sol";
import "src/membership-conditions/IMembershipCondition.sol";

/// @title isHuman membership condition
/// @notice A membership condition that checks if the given avatar is registered as human in Circles hub
contract IsHuman is CirclesCoreAddresses, IMembershipCondition {
    // External functions

    /// @notice Checks whether the avatar is human on Circles hub.
    function passesMembershipCondition(address _avatar) external view returns (bool) {
        return hub.isHuman(_avatar);
    }
}
