// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "openzeppelin-contracts/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "src/circles/Core.sol";
import "src/circles/Types.sol";
import "src/errors/Errors.sol";
import "src/core-members-group/CMGHandler.sol";
import "src/core-members-group/ICMGRedemptionHandler.sol";
import "src/core-members-group/ICoreMembersGroup.sol";

/// @notice
contract CMGRedemptionHandler is CMGHandler, ICMGRedemptionHandler, CirclesTypes {
    // Constants

    /// @notice Indefinite future, or approximated with uint96.max
    uint96 internal constant INDEFINITE_FUTURE = type(uint96).max;

    /// @notice Some reasonable cut off on the number of redemption ids to search for
    uint256 public constant MAX_NUMBER_REDEMPTION_IDS = 100;

    /// @notice Maximum amount that auto-redemption will collect
    /// per collateral ID at a time. Prevents getting a redemption that is too
    /// strongly leveraged on a single id.
    uint256 public constant MAX_REDEEM_PER_ID = 500 * 10 ** 18;

    // Storage

    /// @notice Array of all currently tracked collateral token IDs that have sufficient balance
    uint256[] public activeCollateralIds;

    /// @notice Maps collateral token ID to its index position in activeCollateralIds array for O(1) lookups. Index starts from one to reserve zero for 'not active'
    mapping(uint256 => uint256) public indexInActiveIds;

    /// @notice Cursor tracking current position in activeCollateralIds when searching for available collateral
    uint256 public cursor;

    // Events

    /// @notice Clarification event to report handler returned redeemed collateral Circles to beneficiary
    ///         for total amount redeemed.
    event ReturnedRedeemedCollateral(address indexed group, address indexed beneficiary, uint256 totalAmount);

    // Constructor

    constructor(address _cmGroup, address _owner, string memory _name, CirclesCore memory _circlesCore)
        CMGHandler(_cmGroup, _owner, _circlesCore)
    {
        // append "-redeemer" to group's name to register organization
        string memory orgName = string.concat(_name, "-redeemer");
        // register handler as organization in hub
        circlesCore.hub.registerOrganization(orgName, bytes32(0));
    }

    // External functions

    /// @notice Registers collateral amounts that are being deposited
    /// @param collateralIds Identifiers of collaterals being deposited
    function registerDeposit(uint256[] memory collateralIds) external onlyCMGroup {
        for (uint256 i = 0; i < collateralIds.length; i++) {
            uint256 id = collateralIds[i];
            // no-op if already tracked
            _addActiveId(id);
        }
    }

    /// @notice Registers collateral amounts that are being redeemed, and whether
    ///         to keep tracking the id as active collateral
    /// @param _minimalTrackingAmount Stop tracking amounts below this amount
    /// @param _collateralIds Identifiers of collaterals being redeemed
    /// @param _amounts Amounts of each collateral being redeemed
    function registerRedemption(
        uint256 _minimalTrackingAmount,
        uint256[] memory _collateralIds,
        uint256[] memory _amounts
    ) external onlyCMGroup {
        // CM group always registers with standard treasury
        address vault = circlesCore.standardTreasury.vaults(cmGroup);
        if (vault == address(0)) {
            // if vault has not been deployed, then it should be impossible to get this callback
            revert CMGHandlerLogicAssertion();
        }

        // to do a batched balance call of vault for each,
        // we need to expand the address - it's a trade-off
        address[] memory accounts = new address[](_collateralIds.length);
        for (uint256 i = 0; i < _collateralIds.length; i++) {
            accounts[i] = vault;
        }

        uint256[] memory balances = circlesCore.hub.balanceOfBatch(accounts, _collateralIds);

        for (uint256 i = 0; i < _collateralIds.length; i++) {
            uint256 id = _collateralIds[i];
            if (balances[i] < _amounts[i]) {
                revert CMGHandlerEarlyRevertCollateralNotPresent();
            }
            uint256 remainingBalance;
            unchecked {
                // explicitly checked above, and this handler can't effect
                // the actual redemption flow by hub,
                // nor is this remaining balance stored
                remainingBalance = balances[i] - _amounts[i];
            }

            // When a collateral's balance falls below minimal tracking amount
            // we remove it from our active tracking lists
            if (remainingBalance <= _minimalTrackingAmount) {
                // no-op if id not tracked -- should not occur
                _removeActiveId(id);
            }
        }
    }

    /// @notice Sync status of provided collateral IDs, updating tracked status based on vault balances
    /// @param _collateralIds Array of collateral IDs to check and sync
    function syncValidCollateral(uint256[] memory _collateralIds) external {
        address vault = _getGroupVault();
        uint256 minimalAmount = ICoreMembersGroup(cmGroup).minimalDeposit();

        // expand addresses array for batch balance check
        address[] memory accounts = new address[](_collateralIds.length);
        for (uint256 i = 0; i < _collateralIds.length; i++) {
            accounts[i] = vault;
        }

        // get balances for all IDs in single call
        uint256[] memory balances = circlesCore.hub.balanceOfBatch(accounts, _collateralIds);

        // update tracking for each ID based on balance
        for (uint256 i = 0; i < _collateralIds.length; i++) {
            uint256 id = _collateralIds[i];
            uint256 balance = balances[i];

            // add to active tracking if has balance above minimal amount but not tracked
            if (balance > minimalAmount) {
                // no-op if already tracked
                _addActiveId(id);
            }
            // remove from active tracking if has balance below minimal amount but is tracked
            else if (balance <= minimalAmount) {
                // no-op if id not tracked - should not occur
                _removeActiveId(id);
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
        circlesCore.hub.safeTransferFrom(msg.sender, address(circlesCore.standardTreasury), cmGroupId, value, data);

        // the vault will directly transfer to msg.sender, so no need for acceptance handler

        // emit clarification event of returned collateral
        emit ReturnedRedeemedCollateral(cmGroup, msg.sender, value);
    }

    /// @notice View function to return active collateral with balances starting from offset
    /// @param offset Starting position in active collateral array
    /// @return ids Array of active collateral IDs
    /// @return balances Array of vault balances for each ID
    /// @return totalArrayLength Total length of active collateral array
    function getActiveCollateral(uint256 offset)
        public
        view
        returns (uint256[] memory ids, uint256[] memory balances, uint256 totalArrayLength)
    {
        address vault = _getGroupVault();
        uint256 numActive = activeCollateralIds.length;
        totalArrayLength = numActive;

        if (numActive == 0 || offset >= numActive) {
            return (new uint256[](0), new uint256[](0), numActive);
        }

        uint256 length = numActive - offset;
        if (length > MAX_NUMBER_REDEMPTION_IDS) {
            length = MAX_NUMBER_REDEMPTION_IDS;
        }

        ids = new uint256[](length);
        balances = new uint256[](length);

        // Build arrays of IDs and addresses for batch balance check
        address[] memory accounts = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            ids[i] = activeCollateralIds[offset + i];
            accounts[i] = vault;
        }

        // Get all balances in single call
        balances = circlesCore.hub.balanceOfBatch(accounts, ids);

        return (ids, balances, numActive);
    }

    /// @notice Find available collateral IDs and amounts for redeeming a certain amount
    function findCollateral(address _group, uint256 _amount, bool _partialFillable)
        public
        view
        returns (uint256[] memory, uint256[] memory)
    {
        // sanity check as the operator for groups might get mixed up
        // once many groups and their operators are authorized.
        if (_group != address(cmGroup)) {
            revert CGMHandlerOperatorUnservicedGroup(_group);
        }

        address vault = _getGroupVault();

        uint256 numActive = activeCollateralIds.length;
        if (numActive == 0) return (new uint256[](0), new uint256[](0));

        // temporally "allocate" lengthy arrays
        uint256[] memory ids = new uint256[](MAX_NUMBER_REDEMPTION_IDS);
        uint256[] memory amounts = new uint256[](MAX_NUMBER_REDEMPTION_IDS);

        uint256 remaining = _amount;
        uint256 outputIdx = 0;
        uint256 localCursor = cursor % numActive;

        // Keep looking for collateral while we still need more and haven't hit array bounds
        while (remaining > 0 && outputIdx < MAX_NUMBER_REDEMPTION_IDS && outputIdx < numActive) {
            // Get the next collateral ID based on our cursor position
            uint256 id = activeCollateralIds[localCursor];

            // Check how much collateral is available in the vault for this ID
            uint256 balance = circlesCore.hub.balanceOf(vault, id);

            // Only process IDs that have a non-zero balance
            if (balance > 0) {
                // Calculate redemption amount - take either remaining amount needed
                // or full balance, whichever is smaller
                uint256 toRedeem = remaining < balance ? remaining : balance;

                // Cap individual redemption amounts to prevent over-concentration
                if (toRedeem > MAX_REDEEM_PER_ID) {
                    toRedeem = MAX_REDEEM_PER_ID;
                }

                // Record this ID and amount in our output arrays
                ids[outputIdx] = id;
                amounts[outputIdx] = toRedeem;

                // Update remaining amount needed and advance output index
                remaining -= toRedeem;
                outputIdx++;
            }
            // Note: We purposely don't remove zero balance IDs here to maintain view function status

            // Advance cursor with wraparound, using modulo to cycle back to start
            localCursor = (localCursor + 1) % numActive;
        }

        // If not partial fillable and we couldn't find enough collateral, revert
        if (!_partialFillable && remaining > 0) {
            revert CMGHandlerCouldNotFillRedemptionRequest();
        }

        // Trim arrays if needed
        if (outputIdx < MAX_NUMBER_REDEMPTION_IDS) {
            assembly {
                mstore(ids, outputIdx)
                mstore(amounts, outputIdx)
            }
        }

        return (ids, amounts);
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
        (uint256 ongoingConversion, address beneficiary) = _expectingConversionReturn();
        // starting branch: receive groupId to initiate redemption
        if (ongoingConversion == 0 && _id == cmGroupId) {
            (uint256[] memory ids, uint256[] memory amounts) = findCollateral(address(cmGroup), _value, false);
            // move the cursor forward to cycle through other collateral next time
            cursor = (cursor + ids.length) % activeCollateralIds.length;

            if (ids.length > 0) {
                // todo: tstore _data so we can recover it on completion
                _initiateConversion(_from, _value);
                // note: we can't use the same redeem function because now we already hold the gCRC!
                _redeemUponReceivedGroupCircles(_value, ids, amounts);
            }
        } else if (ongoingConversion == _value && _id != cmGroupId) {
            // continuation branch: receive a single collateral id

            // expect this to be sent by the vault
            if (_getGroupVault() != _from) {
                revert CGMHandlerRedemptionExpectedFromVault(_from);
            }

            _clearConversion();
            // return the collateral with the redemption data (sent back via vault to us)
            // todo: consider mirroring back the original data when stored in tstorage - now we send the "redemption structured data" which is redundant for receiver
            circlesCore.hub.safeTransferFrom(address(this), beneficiary, _id, _value, _data);

            // emit clarification event of returned collateral
            emit ReturnedRedeemedCollateral(cmGroup, beneficiary, _value);
        } else {
            // if the amount does not match
            // or id is groupid, unexpected
            revert CMGHandlerConversionOngoing(ongoingConversion);
        }
        return this.onERC1155Received.selector;
    }

    /// @notice Handler for receiving batch ERC1155 token transfers
    /// @param _from Address that initiated the transfer
    /// @param _ids Array of token IDs being transferred
    /// @param _values Array of amounts being transferred for each token ID
    /// @param _data Additional data passed with transfer
    /// @return bytes4 Function selector to confirm transfer acceptance
    function onERC1155BatchReceived(
        address, /*_operator*/
        address _from,
        uint256[] memory _ids,
        uint256[] memory _values,
        bytes memory _data
    ) public override onlyHub returns (bytes4) {
        // check for expected conversion
        (uint256 ongoingConversion, address beneficiary) = _expectingConversionReturn();

        // verify we are expecting a conversion
        if (ongoingConversion == 0) {
            revert CMGHandlerNoConversionExpected();
        }

        // sum the _values
        uint256 length = _values.length;
        uint256 totalValue = 0;
        for (uint256 i = 0; i < length; i++) {
            totalValue += _values[i];
        }
        if (totalValue == uint256(0)) {
            revert CMGHandlerReceivedZeroAmount();
        }
        if (ongoingConversion != totalValue) {
            revert CMGHandlerConversionOngoing(ongoingConversion);
        }

        // verify sender is the group vault
        if (_from != _getGroupVault()) {
            revert CGMHandlerRedemptionExpectedFromVault(_from);
        }

        // clear conversion state
        _clearConversion();

        // forward tokens to beneficiary
        circlesCore.hub.safeBatchTransferFrom(address(this), beneficiary, _ids, _values, _data);

        // emit clarification event of returned collateral
        emit ReturnedRedeemedCollateral(cmGroup, beneficiary, totalValue);

        return this.onERC1155BatchReceived.selector;
    }

    // Public view functions

    function structureRedemptionData(uint256[] memory _redemptionIds, uint256[] memory _redemptionValues)
        public
        pure
        returns (bytes memory)
    {
        bytes memory userData = abi.encode(BaseRedemptionPolicy(_redemptionIds, _redemptionValues));
        bytes memory data = abi.encode(Metadata(METADATATYPE_GROUPREDEEM, "", userData));
        return data;
    }

    // Internal helpers

    function _redeemUponReceivedGroupCircles(
        uint256 _value,
        uint256[] memory _redemptionIds,
        uint256[] memory _redemptionValues
    ) internal {
        // formulate the data to send to standard treasury to redeem gCRC for collateral
        bytes memory redemptionData = structureRedemptionData(_redemptionIds, _redemptionValues);
        // send gCRC to standard treasury,
        // - standardTreasury will call beforeRedemption on group policy (is CMGroup)
        // - if this redemption handler is connected to the group then the group will register
        //   the redemption amounts in (this/the active) handler, to update active ids for next search
        // - vault will send the requested collateral back to original sender, ie this redemption handler,
        //   so expect to receive the redemption collateral back in this address
        circlesCore.hub.safeTransferFrom(
            address(this), address(circlesCore.standardTreasury), cmGroupId, _value, redemptionData
        );
    }

    /// @dev Add an ID to the 'activeIds' array and set indexInActiveIds for quick removal.
    function _addActiveId(uint256 id) internal {
        if (indexInActiveIds[id] != uint256(0)) {
            // already tracked, don't add duplicates
            return;
        }
        // Store index mapping for quick lookup/removal later
        // Index is current length before adding new element plus one to avoid zero
        indexInActiveIds[id] = activeCollateralIds.length + 1;

        // Add the new ID to end of active IDs array
        activeCollateralIds.push(id);
    }

    /// @dev Remove an ID from 'activeCollateralIds' array via swap-and-pop to keep it O(1).
    function _removeActiveId(uint256 id) internal {
        // Get index of id to remove and last index in array
        uint256 idx = indexInActiveIds[id];
        if (idx == uint256(0)) {
            // nothing to remove if index in active ids is zero.
            return;
        }
        // correct offset for index in array
        idx -= uint256(1);
        // get last index from array length
        uint256 lastIdx = activeCollateralIds.length - 1;

        // If id to remove isn't the last element, we need to swap with last element
        // to maintain array continuity when we pop
        if (idx != lastIdx) {
            // Get the last element's id
            uint256 lastId = activeCollateralIds[lastIdx];
            // Move last element into the slot we're removing
            activeCollateralIds[idx] = lastId;
            // Update the index mapping for the moved element (again offset from 1)
            indexInActiveIds[lastId] = idx + 1;
        }

        // Remove last element from array (either the element we wanted to remove
        // or the one we swapped into its place)
        activeCollateralIds.pop();
        // Clear the index mapping for removed id
        delete indexInActiveIds[id];

        // If cursor was past the removed index, decrement it
        // to maintain proper position in the now-shorter array
        if (cursor > idx) {
            cursor--;
        }
    }

    /// @dev Helper to get the vault for the core members group with standard error handling
    function _getGroupVault() internal view returns (address) {
        // get target group's vault from treasury's mapping
        // as CMG it is always created with standard treasury
        address vault = circlesCore.standardTreasury.vaults(cmGroup);
        if (vault == address(0)) {
            // if no gCRC has been minted, vault is not yet deployed
            revert CMGHandlerVaultNotFound(address(cmGroup));
        }
        return vault;
    }
}
