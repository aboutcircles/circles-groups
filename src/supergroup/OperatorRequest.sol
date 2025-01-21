// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "src/errors/Errors.sol";
import "src/policies/PolicyTypes.sol";

abstract contract OperatorRequest is ISupergroupRequestErrors {
    // Internal functions

    /// @notice Validate request hash returns true if the request was registered and not yet consumed.
    function _validateRequest(bytes32 _requestHash) internal returns (bool) {
        uint256 slot = _getTransientStorageSlot(_requestHash);
        bool isValid;
        assembly {
            let storedHash := tload(slot)
            // Check if hashes match
            isValid := eq(storedHash, _requestHash)
            // Verify and consume the request
            if isValid { tstore(slot, 0) } // Clear the slot if consumed to prevent double consumption
        }
        return isValid;
    }

    /// @dev Submit request stores the hash of the request in the transient storage of the supergroup. This will allow
    ///      within the same transaction a path transfer to pass the mint policy check once for each unique request.
    function _submitRequest(address minter, address group, uint256[] calldata collateral, uint256[] calldata amounts)
        internal
    {
        bytes32 requestHash = PolicyTypes.hashRequest(minter, group, collateral, amounts);
        uint256 slot = _getTransientStorageSlot(requestHash);

        assembly {
            let currentValue := tload(slot)
            if currentValue {
                // If slot is not empty (non-zero)
                revert(0, 0)
            }
            tstore(slot, requestHash)
        }
    }

    /// @dev Simply use the request hash as
    function _getTransientStorageSlot(bytes32 _requestHash) internal pure returns (uint256) {
        return uint256(_requestHash);
    }
}
