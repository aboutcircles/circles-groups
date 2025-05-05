// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "src/membership-conditions/IMembershipCondition.sol";
import "src/membership-conditions/ICirclesBackingFactory.sol";

/// @title CirclesBackingCondition
/// @notice A membership condition that checks if the given avatar has an active LBP circles backing.
contract CirclesBackingCondition is IMembershipCondition {
    /// @notice CirclesBackingFactory enables human avatars to back their personal CRC in an LBP pool.
    ICirclesBackingFactory public circlesBackingFactory =
        ICirclesBackingFactory(address(0xecEd91232C609A42F6016860E8223B8aEcaA7bd0));

    /// @notice Checks whether the avatar is human (implied by check of LBP factory) and
    ///         whether LBP factory has an active LBP for this avatar.
    function passesMembershipCondition(address avatar) external view returns (bool) {
        return circlesBackingFactory.isActiveLBP(avatar);
    }
}
