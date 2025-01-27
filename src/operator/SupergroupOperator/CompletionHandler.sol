// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "openzeppelin-contracts/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "src/errors/Errors.sol";

contract CompletionHandler is ERC1155Holder, ISupergroupOperatorCompletionErrors {
    // Constants

    /// @dev single transient slot where to store expected acceptance call
    bytes32 internal constant EXPECTATION_SLOT = keccak256("EXPECTATION_SLOT");
    /// @dev transient slot to store planned final receiver of funds
    bytes32 internal constant FINAL_RECEIVER_SLOT = keccak256("FINAL_RECEIVER_SLOT");
    /// @dev transient slot where to store expected fee
    bytes32 internal constant FEE_SLOT = keccak256("FEE_SLOT");
    /// @dev transient slot to store fee collection address
    bytes32 internal constant FEE_COLLECTION_ADDRESS_SLOT = keccak256("FEE_COLLECTION_ADDRESS_SLOT");

    /// @dev Domain separator for expecting a single transfer acceptance call
    bytes32 internal constant DOMAIN_SEPARATOR_SINGLE_ACCEPTANCE =
        keccak256("onERC1155ReceivedExpecteduint256 id,uint256 value,bytes data)");
    /// @dev Domain separator for expecting a batch transfer acceptance call
    bytes32 internal constant DOMAIN_SEPARATOR_BATCH_ACCEPTANCE =
        keccak256("onERC1155BatchReceived(uint256[] ids,uint256[] values,bytes data)");

    // Internal functions

    /// @notice Sets expectation for a single acceptance call if no other expectation is active
    /// @param _finalReceiver The address of the final receiver
    /// @param _id The token id being transferred
    /// @param _value The amount being transferred
    /// @param _data Additional data passed with transfer
    /// @param _fee The fee to be charged
    /// @param _feeCollection The address to collect the fee
    function _setExpectationSingleAcceptanceCall(
        address _finalReceiver,
        uint256 _id,
        uint256 _value,
        bytes memory _data,
        uint256 _fee,
        address _feeCollection
    ) internal {
        // Check if slot is empty
        bytes32 currentExpectation;
        // assembly does not like the constants
        bytes32 expectationSlot = EXPECTATION_SLOT;
        bytes32 receiverSlot = FINAL_RECEIVER_SLOT;
        bytes32 feeSlot = FEE_SLOT;
        bytes32 feeCollectionSlot = FEE_COLLECTION_ADDRESS_SLOT;
        assembly {
            currentExpectation := tload(expectationSlot)
        }
        if (currentExpectation != bytes32(0)) {
            revert ExpectationAlreadySet(currentExpectation);
        }

        // Generate and store the acceptance hash
        bytes32 acceptanceHash = _hashSingleAcceptanceCall(_id, _value, _data);

        assembly {
            tstore(expectationSlot, acceptanceHash)
            tstore(receiverSlot, _finalReceiver)
            tstore(feeSlot, _fee)
            tstore(feeCollectionSlot, _feeCollection)
        }
    }

    /// @notice Sets expectation for a batch acceptance call if no other expectation is active
    /// @param _finalReceiver The address of the final receiver
    /// @param _ids Array of token ids being transferred
    /// @param _values Array of amounts being transferred
    /// @param _data Additional data passed with transfer
    /// @param _fee The fee to be charged
    /// @param _feeCollection The address to collect the fee
    function _setExpectationBatchAcceptanceCall(
        address _finalReceiver,
        uint256[] memory _ids,
        uint256[] memory _values,
        bytes memory _data,
        uint256 _fee,
        address _feeCollection
    ) internal {
        // Check if slot is empty
        bytes32 currentExpectation;
        // assembly does not like the constants
        bytes32 slot = EXPECTATION_SLOT;
        bytes32 receiverSlot = FINAL_RECEIVER_SLOT;
        bytes32 feeSlot = FEE_SLOT;
        bytes32 feeCollectionSlot = FEE_COLLECTION_ADDRESS_SLOT;
        assembly {
            currentExpectation := tload(slot)
        }
        if (currentExpectation != bytes32(0)) {
            revert ExpectationAlreadySet(currentExpectation);
        }

        // Generate and store the acceptance hash
        bytes32 acceptanceHash = _hashBatchAcceptanceCall(_ids, _values, _data);

        assembly {
            tstore(slot, acceptanceHash)
            tstore(receiverSlot, _finalReceiver)
            tstore(feeSlot, _fee)
            tstore(feeCollectionSlot, _feeCollection)
        }
    }

    /// @notice Checks if a single acceptance call matches the stored expectation and returns receiver info
    /// @dev Clears stored expectations after successful check
    /// @param _id The token id being transferred
    /// @param _value The amount being transferred
    /// @param _data Additional data passed with transfer
    /// @return address The final receiver address
    /// @return uint256 The fee amount
    /// @return address The fee collection address
    function _checkExpectationSingleAcceptanceCall(uint256 _id, uint256 _value, bytes memory _data)
        internal
        returns (address, uint256, address)
    {
        // Check if expectation exists
        bytes32 currentExpectation;
        address finalReceiver;
        uint256 fee;
        address feeCollection;
        bytes32 expectationSlot = EXPECTATION_SLOT;
        bytes32 receiverSlot = FINAL_RECEIVER_SLOT;
        bytes32 feeSlot = FEE_SLOT;
        bytes32 feeCollectionSlot = FEE_COLLECTION_ADDRESS_SLOT;

        assembly {
            currentExpectation := tload(expectationSlot)
            finalReceiver := tload(receiverSlot)
            fee := tload(feeSlot)
            feeCollection := tload(feeCollectionSlot)
        }

        if (currentExpectation == bytes32(0)) {
            revert NoExpectationSet();
        }

        // Generate hash from actual parameters
        bytes32 acceptanceHash = _hashSingleAcceptanceCall(_id, _value, _data);

        // Verify hash matches expectation
        if (acceptanceHash != currentExpectation) {
            revert ExpectationMismatch(currentExpectation, acceptanceHash);
        }

        // Clear expectation after successful check
        assembly {
            tstore(expectationSlot, 0)
            tstore(receiverSlot, 0)
            tstore(feeSlot, 0)
            tstore(feeCollectionSlot, 0)
        }

        return (finalReceiver, fee, feeCollection);
    }

    /// @notice Checks if a batch acceptance call matches the stored expectation and returns receiver info
    /// @dev Clears stored expectations after successful check
    /// @param _ids Array of token ids being transferred
    /// @param _values Array of amounts being transferred
    /// @param _data Additional data passed with transfer
    /// @return address The final receiver address
    /// @return uint256 The fee amount
    /// @return address The fee collection address
    function _checkExpectationBatchAcceptanceCall(uint256[] memory _ids, uint256[] memory _values, bytes memory _data)
        internal
        returns (address, uint256, address)
    {
        // Check if expectation exists
        bytes32 currentExpectation;
        address finalReceiver;
        uint256 fee;
        address feeCollection;
        bytes32 expectationSlot = EXPECTATION_SLOT;
        bytes32 receiverSlot = FINAL_RECEIVER_SLOT;
        bytes32 feeSlot = FEE_SLOT;
        bytes32 feeCollectionSlot = FEE_COLLECTION_ADDRESS_SLOT;

        assembly {
            currentExpectation := tload(expectationSlot)
            finalReceiver := tload(receiverSlot)
            fee := tload(feeSlot)
            feeCollection := tload(feeCollectionSlot)
        }

        if (currentExpectation == bytes32(0)) {
            revert NoExpectationSet();
        }

        // Generate hash from actual parameters
        bytes32 acceptanceHash = _hashBatchAcceptanceCall(_ids, _values, _data);

        // Verify hash matches expectation
        if (acceptanceHash != currentExpectation) {
            revert ExpectationMismatch(currentExpectation, acceptanceHash);
        }

        // Clear expectation after successful check
        assembly {
            tstore(expectationSlot, 0)
            tstore(receiverSlot, 0)
            tstore(feeSlot, 0)
            tstore(feeCollectionSlot, 0)
        }

        return (finalReceiver, fee, feeCollection);
    }

    /// @notice Hashes parameters for a single token acceptance call
    /// @param _id The token id being transferred
    /// @param _value The amount being transferred
    /// @param _data Additional data passed with transfer
    function _hashSingleAcceptanceCall(uint256 _id, uint256 _value, bytes memory _data)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(DOMAIN_SEPARATOR_SINGLE_ACCEPTANCE, _id, _value, keccak256(_data)));
    }

    /// @notice Hashes parameters for a batch token acceptance call
    /// @param _ids Array of token ids being transferred
    /// @param _values Array of amounts being transferred
    /// @param _data Additional data passed with transfer
    function _hashBatchAcceptanceCall(uint256[] memory _ids, uint256[] memory _values, bytes memory _data)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(DOMAIN_SEPARATOR_BATCH_ACCEPTANCE, _ids, _values, keccak256(_data)));
    }
}
