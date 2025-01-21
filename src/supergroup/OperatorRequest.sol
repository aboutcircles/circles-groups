// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "src/errors/Errors.sol";
import "src/policies/PolicyTypes.sol";

abstract contract OperatorRequest is ISupergroupRequestErrors {
    // Internal functions

    /// @dev Validate request subtracts from the counter stored under the request hash
    ///      and returns false if no such request is available (anymore).
    function _validateRequest(bytes32 _requestHash) internal returns (bool) {
        uint256 slot = _getTransientStorageSlot(_requestHash);
        bool isValid;
        assembly {
            let counter := tload(slot)
            // Check if counter is greater than zero
            isValid := gt(counter, 0)
            // if valid, decrement the counter
            if isValid { tstore(slot, sub(counter, 1)) }
        }
        return isValid;
    }

    /// @dev Submit request updates a counter under the request hash in the transient storage
    ///      of the supergroup. This allows an operator to preregister within the same transaction
    ///      in the mint policy a request for minting during a path transfer.
    function _submitRequest(address minter, address group, uint256[] calldata collateral, uint256[] calldata amounts)
        internal
    {
        bytes32 requestHash = PolicyTypes.hashRequest(minter, group, collateral, amounts);
        assembly {
            let currentCounter := tload(requestHash)
            let newCounter := add(currentCounter, 1)
            tstore(requestHash, newCounter)
        }
    }

    /// @dev Simply use the request hash as
    function _getTransientStorageSlot(bytes32 _requestHash) internal pure returns (uint256) {
        return uint256(_requestHash);
    }
}
