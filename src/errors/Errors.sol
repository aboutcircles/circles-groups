// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

interface ISupergroupErrors {
    /// @notice Supergroup proxy is already initialised
    error SupergroupProxyAlreadyInitialised();
    /// @notice Only Hub can call
    error SupergroupOnlyHub();
    /// @notice Only owner can call
    error SupergroupOnlyOwner();
    /// @notice Only owner or service can call
    error SupergroupOnlyOwnerOrService();
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
    error SupergroupBlockNormalERC1155Transfers();
    /// @notice Group should always block acceptance call for its own id
    ///         or that of untrusted avatars
    error SupergroupAlwaysBlockUntrustedIds();
    /// @notice Reserved addresses cannot be set as operator
    error SupergroupInvalidOperator(address operator);
    /// @notice when operators are required, at least one operator must be activated
    error SupergroupMustHaveOperatorsActivated();
    /// @notice logic assertion
    error SupergroupLogicAssertion();
}

interface ISupergroupRequestErrors {
    /// @notice Operator request is already in progress
    error SupergroupOperatorRequestInProgress();
}

interface ISupergroupPolicyFingerprintsErrors {
    /// @notice Throws when during acceptance call more is
    error SupergroupFingerprintUnderflow();
}

interface ISupergroupOperatorErrors {
    error SupergroupOperatorUnservicedGroup(address group);
    /// @notice the action requires that an authorized operator performs it,
    ///         and this operator is currently not authorized for this supergroup.
    error SupergroupOperatorNotAuthorizedAndAuthorizationRequired(address group);
    /// @notice error to indicate this operator does not implement this (yet).
    error SupergroupOperatorDoesNotImplement();
}

interface ISupergroupOperatorCompletionErrors {
    /// @notice An expectation for a completion call is already set
    error ExpectationAlreadySet(bytes32 expectation);
    /// @notice No expectation was set when checking completion call
    error NoExpectationSet();
    /// @notice The actual completion call parameters did not match the expected ones
    error ExpectationMismatch(bytes32 expected, bytes32 actual);
    /// @notice only expect supergroup id on single receive
    error ExpectationSingleReceiveOnlySupergroupId(uint256 id);
}

interface ICMGroupErrors {
    /// @notice CoreMembers group proxy is already initialised
    error CMGroupProxyAlreadyInitialised();
    /// @notice Only Hub can call
    error CMGroupOnlyHub();
    /// @notice Only owner can call
    error CMGroupOnlyOwner();
    /// @notice Only owner or service can call
    error CMGroupOnlyOwnerOrService();
    /// @notice to interact with the group it must be above a set minimum
    error CMGroupInteractionAmountIsBelowMinimum(uint256 id, uint256 receivedAmount, uint256 minimalAmount);
    /// @notice Sanity check error on calling parameters
    error CMGroupInvalidCallingParameters();
}

interface ICMGHandlerErrors {
    /// @notice only Hub can call
    error CMGHandlerOnlyHub();
    /// @notice only CM Group can call
    error CMGHandlerOnlyCMGroup();
    /// @notice only owner can call
    error CMGHandlerOnlyOwner();
    /// @notice AcceptanceCallUnhandled
    error CMGHandlerAcceptanceCallUnhandled();
    /// @notice As operator handler does not act on requested group
    error CGMHandlerOperatorUnservicedGroup(address group);
    /// @notice Avoid attempting to collateralize self-referential group Circles
    error CMGHandlerRefuseGroupCircles();
    /// @notice Only a single conversion can be ongoing at one time
    error CMGHandlerConversionOngoing(uint256 amount);
    /// @notice Revert on receiving zero amount
    error CMGHandlerReceivedZeroAmount();
    /// @notice Redemption of collateral is expected to originate from the vault
    error CGMHandlerRedemptionExpectedFromVault(address from);
    /// @notice No vault contract exists for the given group address
    error CMGHandlerVaultNotFound(address group);
    /// @notice Thrown when a redemption request cannot be satisfied
    ///         with available collateral and cutoff on search
    error CMGHandlerCouldNotFillRedemptionRequest();
    /// @notice Thrown early to prevent wasted gas when requested collateral is not present in vault
    error CMGHandlerEarlyRevertCollateralNotPresent();
    /// @notice Handler can only transfer handler's CRC
    error CMGHandlerOnlyTransferOwnCircles();
    /// @notice Sanity check error on calling parameters
    error CMGHandlerInvalidCallingParameters();
    /// @notice logic assertion
    error CMGHandlerLogicAssertion();
}
