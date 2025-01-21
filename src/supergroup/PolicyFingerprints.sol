// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "src/errors/Errors.sol";
import "src/policies/PolicyTypes.sol";

abstract contract PolicyFingerprints is ISupergroupPolicyFingerprintsErrors {
    // Internal functions

    function _subtractFromFingerprint(address _group, uint256 _collateral, uint256 _amount) internal {
        bytes32 fingerprintHash = PolicyTypes.hashFingerprint(_group, _collateral);
        assembly {
            let currentAmount := tload(fingerprintHash) // load current amount from transient storage

            // check if subtraction would underflow
            if lt(currentAmount, _amount) {
                // Revert with error FingerprintUnderflow()
                mstore(0x00, 0x03f3903a)
                revert(0x00, 0x04)
            }

            let newAmount := sub(currentAmount, _amount)
            tstore(fingerprintHash, newAmount)
        }
    }

    /// @notice Store fingerprint adds the amount under the collateral in transient storage
    ///         so that during acceptance calls we can deduct from this fingerprint
    ///         before returning minted group circles to the sender
    function _addToFingerprint(address _group, uint256 _collateral, uint256 _amount) internal {
        bytes32 fingerprintHash = PolicyTypes.hashFingerprint(_group, _collateral);
        assembly {
            let currentAmount := tload(fingerprintHash) // load current amount from transient storage slot
            let newAmount := add(currentAmount, _amount) // Add new amount to current amount
            tstore(fingerprintHash, newAmount)
        }
    }
}
