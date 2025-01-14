// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

interface ISupergroupErrors {
    /// @notice Supergroup proxy is already initialised
    error SupergroupProxyAlreadyInitialised();
    /// @notice Only Hub can call
    error SupergroupOnlyHub();
    /// @notice Supergroup must have been registered
    error SupergroupMustBeRegistered();
    /// @notice Sanity check error on calling parameters
    error SupergroupInvalidCallingParameters();
}
