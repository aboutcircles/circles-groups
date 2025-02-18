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
    function registerRedemption(uint256 minimalTrackingAmount, uint256[] memory collateralIds, uint256[] memory amounts)
        external;

    /// @notice Sync status of provided collateral IDs, updating tracked status based on vault balances
    /// @param collateralIds Array of collateral IDs to check and sync
    function syncValidCollateral(uint256[] memory collateralIds) external;

    /// @notice View function to return active collateral with balances starting from offset
    /// @param offset Starting position in active collateral array
    /// @return ids Array of active collateral IDs
    /// @return balances Array of vault balances for each ID
    /// @return totalArrayLength Total length of active collateral array
    function getActiveCollateral(uint256 offset)
        external
        view
        returns (uint256[] memory ids, uint256[] memory balances, uint256 totalArrayLength);

    /// @notice Find available collateral IDs and amounts for redeeming a certain amount
    /// @param group Group address to find collateral for
    /// @param amount Amount to find collateral for
    /// @param partialFillable Whether partial fills are acceptable
    /// @return ids Array of collateral IDs found
    /// @return amounts Array of amounts for each collateral ID
    function findCollateral(address group, uint256 amount, bool partialFillable)
        external
        view
        returns (uint256[] memory ids, uint256[] memory amounts);

    /// @notice Structure redemption data for use in transfers
    /// @param redemptionIds Array of redemption IDs
    /// @param redemptionValues Array of redemption values
    /// @return Encoded redemption data
    function structureRedemptionData(uint256[] memory redemptionIds, uint256[] memory redemptionValues)
        external
        pure
        returns (bytes memory);
}
