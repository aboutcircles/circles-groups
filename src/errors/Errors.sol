// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

interface ICMGroupErrors {
    /// @notice CoreMembers group proxy is already initialised
    error CMGroupProxyAlreadyInitialised();
    /// @notice Only Hub can call
    error CMGroupOnlyHub();
    /// @notice Only Hub Or Treasury can call
    error CMGroupOnlyHubOrTreasury();
    /// @notice Only owner can call
    error CMGroupOnlyOwner();
    /// @notice Membership check failed for avatar on condition
    error CMGroupMembershipCheckFailed(address avatar, address failedCondition);
    /// @notice Maximum number of conditions reached already
    error CMGroupMaxConditionsActive(uint256 conditionsActive);
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
    /// @notice Expect a conversion to be ongoing
    error CMGHandlerNoConversionExpected();
    /// @notice Revert on receiving zero amount
    error CMGHandlerReceivedZeroAmount();
    /// @notice Redemption of collateral is expected to originate from the vault
    error CGMHandlerRedemptionExpectedFromVault(address from);
    /// @notice The data hash does not match the expected hash for completing conversion
    error CGMHandlerDataHashMismatchUponReceiving(bytes32 expectedDataHash, bytes receivedData);
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

interface ICMGAffiliateGroupRegistryErrors {
    /// @notice to register affiliate group caller must be registered human and group must be group
    error CMGAffiliateGroupMustBeHumanAndGroupToRegisterAffiliateGroup(address human, address group);
}

interface ICMGRedemptionOperatorErrors {
    /// @notice group must be registered
    error CMGRedemptionOperatorGroupMustBeRegistered(address group);
    /// @notice redemption handler of group is zero address
    error CMGRedemptionOperatorHandlerOfGroupZeroAddress();
    /// @notice only support non-custom groups with standard treasury
    error CMGRedemptionOperatorOnlySupportStandardTreasuryGroups(address treasury);
    /// @notice Prevent redeeming more than requested
    error CMGRedemptionOperatorFoundCollateralExceedsAmountRequested(uint256 requestedAmount, uint256 foundAmount);
    /// @notice if not partially fillable, found amount must be exactly requested amount
    error CMGRedemptionOperatorFailedToFindSufficientCollateral(uint256 requestedAmount, uint256 foundAmount);
    /// @notice invalid calling parameters
    error CMGRedemptionOperatorInvalidCallingParameters();
}

interface IGroupLiquidityProviderErrors {
    /// @notice Group address cannot be zero
    error GroupLiquidityProviderGroupCannotBeZeroAddress();
    /// @notice Owner address cannot be zero
    error GroupLiquidityProviderOwnerCannotBeZeroAddress();
    /// @notice Only allow transfers of own tokens
    error GroupLiquidityProviderCanOnlyTransferOwnTokens();
    /// @notice Only accept transfers from Hub
    error GroupLiquidityProviderOnlyAcceptTransfersFromHub();
    /// @notice Only accept transfers from owner
    error GroupLiquidityProviderOnlyAcceptTransfersFromOwnerOrVault();
}
