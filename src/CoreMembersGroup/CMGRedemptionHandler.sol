// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "openzeppelin-contracts/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "src/circles/Core.sol";
import "src/circles/Types.sol";
import "src/errors/Errors.sol";
import "src/CoreMembersGroup/CMGHandler.sol";
import "src/CoreMembersGroup/ICMGRedemptionHandler.sol";

/// @notice
contract CMGRedemptionHandler is CMGHandler, ICMGRedemptionHandler, CirclesTypes {
    // Constants

    /// @notice Indefinite future, or approximated with uint96.max
    uint96 internal constant INDEFINITE_FUTURE = type(uint96).max;

    // Storage
    uint256[] public activeCollateralIds;
    mapping(uint256 => uint256) public indexInActiveIds;
    uint256 public cursor;

    // Constructor

    constructor(address _cmGroup, address _owner, string memory _name) CMGHandler(_cmGroup, _owner) {
        // append "-redeemer" to group's name to register organization
        string memory orgName = string.concat(_name, "-redeemer");
        // register handler as organization in hub
        hub.registerOrganization(orgName, bytes32(0));
        // the redemption handler only trusts the CM Group so that over paths
        // it only accepts group Circles
        hub.trust(_cmGroup, INDEFINITE_FUTURE);
    }

    // External functions

    /// @notice Registers collateral amounts that are being deposited
    /// @param collateralIds Identifiers of collaterals being deposited
    function registerDeposit(uint256[] memory collateralIds) external onlyCMGroup {
        for (uint256 i = 0; i < collateralIds.length; i++) {
            uint256 id = collateralIds[i];
            // if the id was registered as zero-collateral, add it now
            if (indexInActiveIds[id] == 0) {
                // if amount was zero, add this id to our tracker
                indexInActiveIds[id] = activeCollateralIds.length;
                activeCollateralIds.push(id);
            }
        }
    }

    /// @notice Registers collateral amounts that are being redeemed
    /// @param collateralIds Identifiers of collaterals being redeemed
    /// @param amounts Amounts of each collateral being redeemed
    function registerRedemption(uint256[] memory collateralIds, uint256[] memory amounts) external onlyCMGroup {
        // CM group always registers with standard treasury
        address vault = standardTreasury.vaults(cmGroup);
        if (vault == address(0)) {
            // if vault has not been deployed, then it should be impossible to get this callback
            revert CMGHandlerLogicAssertion();
        }

        // to do a batched balance call of vault for each, we need to expand the address
        address[] memory accounts = new address[](collateralIds.length);
        for (uint256 i = 0; i < collateralIds.length; i++) {
            accounts[i] = vault;
        }

        uint256[] memory balances = hub.balanceOfBatch(accounts, collateralIds);

        for (uint256 i = 0; i < collateralIds.length; i++) {
            uint256 id = collateralIds[i];
            uint256 remainingBalance = balances[i] - amounts[i];

            if (remainingBalance == 0) {
                uint256 idx = indexInActiveIds[id];
                uint256 lastIdx = activeCollateralIds.length - 1;

                if (idx != lastIdx) {
                    uint256 lastId = activeCollateralIds[lastIdx];
                    activeCollateralIds[idx] = lastId;
                    indexInActiveIds[lastId] = idx;
                }

                activeCollateralIds.pop();
                delete indexInActiveIds[id];

                if (cursor > idx) {
                    cursor--;
                }
            }
        }
    }

    // Public functions

    /// @notice Redeem is a helper function to construct the data for redeeming
    ///         the collateral from the CM Group. The caller must have authorized
    ///         this contract as an ERC1155 operator.
    function redeem(address _group, uint256[] memory _redemptionIds, uint256[] memory _redemptionValues)
        public
        nonReentrant
    {
        // sanity check as the operator for groups might get mixed up
        // once many groups and their operators are authorized.
        if (_group != address(cmGroup)) {
            revert CGMHandlerOperatorUnservicedGroup(_group);
        }
        uint256 length = _redemptionIds.length;
        if (length != _redemptionValues.length || length == 0) {
            revert CMGHandlerInvalidCallingParameters();
        }
        // sum the total of collateral to claim back, as this amount
        // of group Circles must be sent to treasury to redeem
        uint256 value = 0;
        for (uint256 i = 0; i < length; i++) {
            value += _redemptionValues[i];
        }

        bytes memory userData = abi.encode(BaseRedemptionPolicy(_redemptionIds, _redemptionValues));
        bytes memory data = abi.encode(Metadata(METADATATYPE_GROUPREDEEM, "", userData));

        // note: for redemption there is no need to set expectation handler yet, because standardVault can directly
        // return the collateral to msg.sender.

        // to redeem the group Circles must be sent to StandardTreasury with the correct data formatted.
        hub.safeTransferFrom(msg.sender, address(standardTreasury), cmGroupId, value, data);

        // the vault will directly transfer to msg.sender, so no need for acceptance handler
    }

    /// @notice Find available collateral IDs and amounts for redeeming a certain amount
    function findCollateral(address _group, uint256 _amount)
        public
        view
        returns (uint256[] memory ids, uint256[] memory amounts)
    {
        // sanity check as the operator for groups might get mixed up
        // once many groups and their operators are authorized.
        if (_group != address(cmGroup)) {
            revert CGMHandlerOperatorUnservicedGroup(_group);
        }
        // get target group's vault from treasury's mapping
        // as CMG it is always created with standard treasury
        address vault = standardTreasury.vaults(cmGroup);
        if (vault == address(0)) {
            // if no gCRC has been minted, vault is not yet deployed
            revert CMGHandlerVaultNotFound(_group);
        }

        uint256 numActive = activeCollateralIds.length;
        if (numActive == 0) return (new uint256[](0), new uint256[](0));

        ids = new uint256[](numActive);
        amounts = new uint256[](numActive);

        // Get all balances in one call
        address[] memory accounts = new address[](numActive);
        for (uint256 i = 0; i < numActive; i++) {
            accounts[i] = vault;
        }
        uint256[] memory balances = hub.balanceOfBatch(accounts, activeCollateralIds);

        uint256 remaining = _amount;
        uint256 outputIdx = 0;
        uint256 localCursor = cursor % numActive;

        while (remaining > 0 && outputIdx < numActive) {
            uint256 id = activeCollateralIds[localCursor];
            uint256 balance = balances[localCursor];

            if (balance > 0) {
                uint256 toRedeem = remaining < balance ? remaining : balance;
                ids[outputIdx] = id;
                amounts[outputIdx] = toRedeem;
                remaining -= toRedeem;
                outputIdx++;
            }

            localCursor = (localCursor + 1) % numActive;
            if (localCursor == cursor % numActive) break;
        }

        // Trim arrays if needed
        if (outputIdx < numActive) {
            assembly {
                mstore(ids, outputIdx)
                mstore(amounts, outputIdx)
            }
        }
    }

    // ERC1155 acceptance call handlers

    /// @notice Handler for receiving single ERC1155 token transfers. Upon receiving
    ///         CMgroup Circles, it will attempt to redeem and return the collateral
    ///         to the caller.
    /// @dev Only callable by the Circles Hub.
    /// @param _from Address that initiated the transfer
    /// @param _id Token ID being transferred
    /// @param _value Amount of tokens being transferred
    /// @param _data Additional data passed with transfer
    /// @return bytes4 Function selector to confirm transfer acceptance
    function onERC1155Received(address, /*_operator*/ address _from, uint256 _id, uint256 _value, bytes memory _data)
        public
        override
        onlyHub
        returns (bytes4)
    {
        // check transient storage to see if we are expecting a return
        (uint256 ongoingConversion,) = _expectingConversionReturn();
        // starting branch: receive groupId to intiate redemption
        if (ongoingConversion == 0 && _id == cmGroupId) {
            (uint256[] memory ids, uint256[] memory amounts) = findCollateral(address(cmGroup), _value);
            if (ids.length > 0) {
                // redeem(cmGroup, ids, amounts);
                // todo: we can't use the same redeem function because now we already hold the gCRC!
            }
        }
        return this.onERC1155Received.selector;
    }
}
