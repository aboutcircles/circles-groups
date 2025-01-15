// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

/// @notice Operator interface for (super)group to call back to authorized
///         operator to validate request.
interface IOperator {
    /// @notice Validate request returns true if the operator initiated this request.
    function validateRequest(bytes32 requestHash) external returns (bool);
}
