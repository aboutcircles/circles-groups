// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "src/errors/Errors.sol";
import "src/circles/Core.sol";
import "src/circles/Types.sol";
import "src/core-members-group/ICoreMembersGroup.sol";
import "src/core-members-group/ICMGRedemptionHandler.sol";

contract CMGRedemptionOperator is CirclesCoreAddresses, CirclesTypes, ICMGRedemptionOperatorErrors {
    // State

    /// @notice Circles core protocol addresses
    CirclesCore public circlesCore;

    // Events

    /// @notice total amount redeemed for caller (beneficiary)
    event OperatorRedeemedCollateral(address indexed group, address indexed beneficiary, uint256 totalAmount);

    /// @notice total amount redeemed for caller (beneficiary) given requested amount
    event OperatorRedeemedFoundCollateral(
        address indexed group, address indexed beneficiary, uint256 totalFoundAmount, uint256 requestedAmount
    );

    // Modifiers

    /// @notice Reentrancy guard for nonReentrant functions.
    /// see https://soliditylang.org/blog/2024/01/26/transient-storage/
    modifier nonReentrant() {
        assembly {
            if tload(0) { revert(0, 0) }
            tstore(0, 1)
        }
        _;
        assembly {
            tstore(0, 0)
        }
    }

    // Constructor

    constructor(CirclesCore memory _circlesCore) {
        // store Circles core protocol addresses
        circlesCore = _circlesCore;
    }

    // Public functions

    /// @notice Redeem collateral from a Core Members Group by sending group Circles to the StandardTreasury
    /// @dev The caller must have pre-approved this contract as an ERC1155 operator
    /// @dev The redemption data is structured by the group's redemption handler to ensure compatibility
    /// @dev Emits ReturnedRedeemedCollateral event with group, beneficiary (msg.sender) and total amount redeemed
    /// @dev The collateral tokens will be sent directly to msg.sender by the group's vault
    /// @param _group Address of the Core Members Group to redeem from
    /// @param _redemptionIds Array of collateral token IDs to redeem
    /// @param _redemptionValues Array of amounts to redeem for each collateral token ID
    function redeem(address _group, uint256[] memory _redemptionIds, uint256[] memory _redemptionValues)
        external
        nonReentrant
    {
        ICMGRedemptionHandler redemptionHandler = ICMGRedemptionHandler(_assertGroupAndRedemptionHandler(_group));

        uint256 length = _redemptionIds.length;
        if (length != _redemptionValues.length || length == 0) {
            revert CMGRedemptionOperatorInvalidCallingParameters();
        }
        // sum the total of collateral to claim back, as this amount
        // of group Circles must be sent to treasury to redeem
        uint256 value = 0;
        for (uint256 i = 0; i < length; i++) {
            value += _redemptionValues[i];
        }

        // rely on the redemption handler to structure the data in case other formats are adopted
        bytes memory data = redemptionHandler.structureRedemptionData(_redemptionIds, _redemptionValues);

        // to redeem the group Circles must be sent to StandardTreasury with the correct data formatted.
        circlesCore.hub.safeTransferFrom(
            msg.sender, address(circlesCore.standardTreasury), _toTokenId(_group), value, data
        );

        // the vault will directly transfer to msg.sender, so no need for acceptance handler

        // emit clarification event of returned collateral
        emit OperatorRedeemedCollateral(_group, msg.sender, value);
    }

    /// @notice Find collateral in a Core Members Group that matches a desired redemption value, then redeem
    /// @dev The caller must have pre-approved this contract as an ERC1155 operator
    /// @dev The redemption data is structured by the group's redemption handler to ensure compatibility
    /// @dev Emits OperatorRedeemedFoundCollateral event with group, beneficiary (msg.sender), total found amount and requested amount
    /// @dev The collateral tokens will be sent directly to msg.sender by the group's vault
    /// @param _group Address of the Core Members Group to redeem from
    /// @param _amountToRedeem Total amount of group Circles to redeem for collateral
    /// @param _partialFillable If true, will accept partial fills of _amountToRedeem, otherwise requires exact match
    function redeemWithFoundCollateral(address _group, uint256 _amountToRedeem, bool _partialFillable)
        external
        nonReentrant
    {
        ICMGRedemptionHandler redemptionHandler = ICMGRedemptionHandler(_assertGroupAndRedemptionHandler(_group));

        // find collateral using groups redemption handler
        (uint256[] memory collateralIds, uint256[] memory amounts) =
            redemptionHandler.findCollateral(_group, _amountToRedeem, _partialFillable);

        uint256 totalValueFound = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalValueFound += amounts[i];
        }

        if (totalValueFound > _amountToRedeem) {
            revert CMGRedemptionOperatorFoundCollateralExceedsAmountRequested(_amountToRedeem, totalValueFound);
        }

        if (!_partialFillable && totalValueFound != _amountToRedeem) {
            revert CMGRedemptionOperatorFailedToFindSufficientCollateral(_amountToRedeem, totalValueFound);
        }

        // rely on the redemption handler to structure the data in case other formats are adopted
        bytes memory data = redemptionHandler.structureRedemptionData(collateralIds, amounts);

        // to redeem the group Circles must be sent to StandardTreasury with the correct data formatted.
        circlesCore.hub.safeTransferFrom(
            msg.sender, address(circlesCore.standardTreasury), _toTokenId(_group), totalValueFound, data
        );

        // the vault will directly transfer to msg.sender, so no need for acceptance handler

        // emit clarification event of returned collateral
        emit OperatorRedeemedFoundCollateral(_group, msg.sender, totalValueFound, _amountToRedeem);
    }

    // Internal functions

    /// @dev Local helper to assert the group is viable for group redemption and get redemption handler
    /// @dev Makes sure group exists and has standard treasury
    /// @dev Does not allow custom treasury groups to redeem via this contract
    /// @param _group Address of group to validate and get redemption handler for
    /// @return Address of the group's redemption handler contract
    function _assertGroupAndRedemptionHandler(address _group) internal returns (address) {
        if (!circlesCore.hub.isGroup(_group)) {
            revert CMGRedemptionOperatorGroupMustBeRegistered(_group);
        }
        address redemptionHandler = ICoreMembersGroup(_group).redemptionHandler();
        if (redemptionHandler == address(0)) {
            revert CMGRedemptionOperatorHandlerOfGroupZeroAddress();
        }
        // require group is not a custom group and uses standard treasury
        address treasury = circlesCore.hub.treasuries(_group);
        if (treasury != address(circlesCore.standardTreasury)) {
            revert CMGRedemptionOperatorOnlySupportStandardTreasuryGroups(treasury);
        }

        return redemptionHandler;
    }

    function _toTokenId(address _avatar) internal pure returns (uint256) {
        return uint256(uint160(_avatar));
    }
}
