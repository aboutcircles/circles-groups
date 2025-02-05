// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "src/errors/Errors.sol";
import "src/policies/PolicyTypes.sol";

abstract contract PolicyFingerprints is ISupergroupPolicyFingerprintsErrors {
    // Internal functions

    /// @notice Subtract from fingerprint subtracts the amount from the fingerprint stored
    ///         in transient storage to ensure that no group Circles are sent out during
    ///         acceptance call handlers that were not minted in the same transaction.
    function _subtractFromFingerprint(address _group, uint256 _collateral, uint256 _amount) internal {
        bytes32 fingerprintHash = PolicyTypes.hashFingerprint(_group, _collateral);
        uint256 currentAmount;

        assembly {
            currentAmount := tload(fingerprintHash) // load current amount from transient storage
        }
        // do this outside of assembly to avoid errors on error identifiers
        if (currentAmount < _amount) {
            revert SupergroupFingerprintUnderflow();
        }
        assembly {
            let newAmount := sub(currentAmount, _amount)
            tstore(fingerprintHash, newAmount)
        }
    }

    /// @notice add to fingerprint adds the amount under the collateral in transient storage
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
