// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

interface IMembershipCondition {
    /// @notice Evaluates if an address passes a membership condition
    /// @dev This function should be implemented by any contract serving as a membership check
    /// @param avatar The address to evaluate for membership
    /// @return bool indicating if the address passes the membership condition
    function passesMembershipCondition(address avatar) external returns (bool);
}
