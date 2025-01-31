// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

interface ICMGRedemptionHandler {
    /// @notice Registers collateral amounts that are being deposited
    /// @param collateralIds Identifiers of collaterals being deposited
    function registerDeposit(uint256[] memory collateralIds) external;
    /// @notice Registers collateral amounts that are being redeemed
    /// @param minimalTrackingAmount if collateral amount falls
    ///        below this amount stop tracking it in redemption handler
    /// @param collateralIds Identifiers of collaterals being redeemed
    /// @param amounts Amounts of each collateral being redeemed
    function registerRedemption(uint256 minimalTrackingAmount, uint256[] memory collateralIds, uint256[] memory amounts) external;
}
