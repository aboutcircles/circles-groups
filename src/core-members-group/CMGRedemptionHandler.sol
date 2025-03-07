// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "src/circles/Core.sol";
import "src/circles/Types.sol";
import "src/errors/Errors.sol";
import "src/core-members-group/CMGHandler.sol";
import "src/core-members-group/ICMGRedemptionHandler.sol";
import "src/core-members-group/ICoreMembersGroup.sol";

/// @title CMGRedemptionHandler
/// @notice Redemption handler contract for Core Members Groups (CMG) in the Circles protocol
/// @dev Manages redemption of group Circles (gCRC) for collateral tokens held in the group's vault
///      Tracks active collateral IDs and their balances to efficiently find redemption opportunities
///      Works in conjunction with CMGroup and StandardTreasury contracts
contract CMGRedemptionHandler is CMGHandler, ICMGRedemptionHandler, CirclesTypes {
    // Constants

    /// @notice Indefinite future, or approximated with uint96.max
    uint96 internal constant INDEFINITE_FUTURE = type(uint96).max;

    /// @notice Limits the maximum number of collateral IDs that can be processed in a single redemption request to 100
    /// @dev This cap balances between providing sufficient diversification in redemptions while preventing
    ///      excessive gas consumption
    uint256 public constant MAX_NUMBER_REDEMPTION_IDS = 100;

    /// @notice Caps individual redemption amounts to 500 Circles (500 * 10^18) per collateral ID
    /// @dev This limit serves multiple purposes:
    ///      1. Prevents redemptions from being overly concentrated in a single collateral id
    ///      2. Promotes spread-out distribution of redemptions across multiple collateral sources
    uint256 public constant MAX_REDEEM_PER_ID = 500 * 10 ** 18;

    /// @notice Maximum allowed minimal tracking amount, 10 CRC
    uint256 public constant MAX_MINIMAL_TRACKING_AMOUNT = 10 ** 19;

    // Storage

    /// @notice Array of all currently tracked collateral token IDs that have sufficient balance
    uint256[] public activeCollateralIds;

    /// @notice Maps collateral token ID to its index position in activeCollateralIds array for O(1) lookups. Index starts from one to reserve zero for 'not active'
    mapping(uint256 => uint256) public indexInActiveIds;

    /// @notice Cursor tracking current position in activeCollateralIds when searching for available collateral
    uint256 public cursor;

    /// @notice Minimal balance required to track collateral
    uint256 public minimalTrackingAmount;

    // Events

    event MinimalTrackingAmountUpdated(uint256 amount);

    // Constructor

    constructor(address _cmGroup, address _owner, CirclesCore memory _circlesCore)
        CMGHandler(_cmGroup, _owner, _circlesCore)
    {
        // Set default minimal tracking amount
        minimalTrackingAmount = 10 ** 15;
    }

    // External functions

    /// @notice Set the minimal tracking amount (owner only)
    function setMinimalTrackingAmount(uint256 _amount) external onlyOwner {
        if (_amount > MAX_MINIMAL_TRACKING_AMOUNT) {
            revert CMGHandlerInvalidCallingParameters();
        }
        minimalTrackingAmount = _amount;
        emit MinimalTrackingAmountUpdated(_amount);
    }

    /// @notice Registers collateral amounts that are being deposited
    /// @param collateralIds Identifiers of collaterals being deposited
    /// @param amounts Amounts being deposited for each collateral ID
    function registerDeposit(uint256[] memory collateralIds, uint256[] memory amounts) external onlyCMGroup {
        if (collateralIds.length != amounts.length) {
            revert CMGHandlerInvalidCallingParameters();
        }
        for (uint256 i = 0; i < collateralIds.length; i++) {
            uint256 id = collateralIds[i];
            if (amounts[i] > minimalTrackingAmount) {
                // no-op if already tracked
                _addActiveId(id);
            }
        }
    }

    /// @notice Registers collateral amounts that are being redeemed, and whether
    ///         to keep tracking the id as active collateral
    /// @param _collateralIds Identifiers of collaterals being redeemed
    /// @param _amounts Amounts of each collateral being redeemed
    function registerRedemption(uint256[] memory _collateralIds, uint256[] memory _amounts) external onlyCMGroup {
        // CM group always registers with standard treasury
        address vault = _getGroupVault();

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
            if (remainingBalance <= minimalTrackingAmount) {
                // no-op if id not tracked -- should not occur
                _removeActiveId(id);
            }
        }

        // move cursor forward upon registering redemption
        // note: that cursor can also have been pulled back when removing active ids,
        // but the aim here is to simply cycle the cursor so that next call to find collateral
        // starts at a scrambled index.
        if (activeCollateralIds.length > 0) {
            cursor = (cursor + _collateralIds.length) % activeCollateralIds.length;
        } else {
            cursor = 0;
        }
    }

    /// @notice Sync status of provided collateral IDs, updating tracked status based on vault balances
    /// @param _collateralIds Array of collateral IDs to check and sync
    function syncValidCollateral(uint256[] memory _collateralIds) external {
        address vault = _getGroupVault();

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
            if (balance > minimalTrackingAmount) {
                // no-op if already tracked
                _addActiveId(id);
            }
            // remove from active tracking if has balance below minimal amount but is tracked
            else if (balance <= minimalTrackingAmount) {
                // no-op if id not tracked - should not occur
                _removeActiveId(id);
            }
        }
    }

    // Public functions

    /// @notice View function to return active collateral with balances starting from offset
    /// @return ids Array of active collateral IDs
    /// @return balances Array of vault balances for each ID
    /// @return numActive Total length of active collateral array
    function getActiveCollateral() public view returns (uint256[] memory, uint256[] memory, uint256) {
        // todo: if ever necessary consider making this a range request
        address vault = _getGroupVault();

        uint256 numActive = activeCollateralIds.length;

        if (numActive == 0) {
            return (new uint256[](0), new uint256[](0), numActive);
        }

        // Build arrays of IDs and addresses for batch balance check
        uint256[] memory ids = new uint256[](numActive);
        uint256[] memory balances = new uint256[](numActive);
        address[] memory accounts = new address[](numActive);
        for (uint256 i = 0; i < numActive; i++) {
            ids[i] = activeCollateralIds[i];
            accounts[i] = vault;
        }

        // Get all balances in single call
        balances = circlesCore.hub.balanceOfBatch(accounts, ids);

        return (ids, balances, numActive);
    }

    /// @notice Find available collateral IDs and amounts for redeeming a target amount of gCRC tokens
    /// @dev Uses stored cursor to determine starting position when scanning for collateral
    /// @param _group Address of the group to find collateral for (must match registered cmGroup)
    /// @param _amount Target amount of gCRC tokens to find collateral for
    /// @param _partialFillable If true, returns partial amounts when full amount cannot be filled
    /// @return ids Array of collateral token IDs available for redemption
    /// @return amounts Array of corresponding amounts available to redeem for each ID
    function findCollateral(address _group, uint256 _amount, bool _partialFillable)
        public
        view
        returns (uint256[] memory, uint256[] memory)
    {
        // use stored cursor by default
        return findCollateralWithCursor(_group, _amount, _partialFillable, cursor);
    }

    /// @notice Find available collateral IDs and amounts for redeeming a target amount of gCRC tokens
    /// @dev Uses provided cursor to determine starting position when scanning for collateral
    /// @param _group Address of the group to find collateral for (must match registered cmGroup)
    /// @param _amount Target amount of gCRC tokens to find collateral for
    /// @param _partialFillable If true, returns partial amounts when full amount cannot be filled
    /// @param _cursor Starting position index to begin search for available collateral
    /// @return ids Array of collateral token IDs available for redemption
    /// @return amounts Array of corresponding amounts available to redeem for each ID
    function findCollateralWithCursor(address _group, uint256 _amount, bool _partialFillable, uint256 _cursor)
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
        uint256 localCursor = _cursor % numActive;

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
            localCursor = numActive == 0 ? 0 : (localCursor + 1) % numActive;
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
