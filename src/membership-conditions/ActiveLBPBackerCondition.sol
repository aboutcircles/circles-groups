// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "src/circles/Core.sol";
import "src/membership-conditions/projects/ces/CESCoreAddresses.sol";
import "src/membership-conditions/IMembershipCondition.sol";

/// @title ActiveLBPBackerMembershipCondition
/// @notice A membership condition that checks if the given avatar has an active LBP
contract ActiveLBPBackerCondition is CirclesCoreAddresses, CESCoreAddresses, IMembershipCondition {
    // External functions

    /// @notice Checks whether the avatar is human (implied by check of LBP factory) and
    ///         whether LBP factory has an active LBP for this avatar.
    function passesMembershipCondition(address _avatar) external view returns (bool) {
        // check avatar is already checked to be human by LBP,
        // so skip it here as implied by check on LBF Factory

        return launchpad.isActiveLBP(_avatar);
    }
}
