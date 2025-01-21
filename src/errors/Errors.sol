// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

interface ISupergroupErrors {
    /// @notice Supergroup proxy is already initialised
    error SupergroupProxyAlreadyInitialised();
    /// @notice Only Hub can call
    error SupergroupOnlyHub();
    /// @notice Only authorized operator can call
    error SupergroupOnlyAuthorizedOperator();
    /// @notice Supergroup must have been registered
    error SupergroupMustBeRegistered();
    /// @notice For security reasons we enforce explicitly that a supergroup registers with the standard treasury only.
    error SupergroupMustUseStandardTreasury();
    /// @notice Sanity check error on calling parameters
    error SupergroupInvalidCallingParameters();
    /// @notice Group only accepts ERC1155 acceptance call if it was for
    ///         minting group circles and returning the resulting gCRC.
    error SupergroupInvalidERC1155AcceptanceConditions();
}

interface ISupergroupRequestErrors {
    /// @notice Operator request is already in progress
    error SupergroupOperatorRequestInProgress();
}
