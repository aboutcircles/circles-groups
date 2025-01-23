// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "openzeppelin-contracts/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "src/errors/Errors.sol";

contract CompletionHandler is ERC1155Holder, ISupergroupOperatorCompletionErrors {
    // Constants

    /// @dev single transient slot where to store expected acceptance call
    bytes32 internal constant EXPECTATION_SLOT = keccak256("EXPECTATION_SLOT");
    /// @dev transient slot to store planned receiver of funds
    bytes32 internal constant PLANNED_RECEIVER = keccak256("PLANNED_RECEIVER_SLOT");

    /// @dev Domain separator for expecting a single transfer acceptance call
    bytes32 internal constant DOMAIN_SEPARATOR_SINGLE_ACCEPTANCE =
        keccak256("onERC1155ReceivedExpected(address operator,address from,uint256 id,uint256 value,bytes data)");
    /// @dev Domain separator for expecting a batch transfer acceptance call
    bytes32 internal constant DOMAIN_SEPARATOR_BATCH_ACCEPTANCE =
        keccak256("onERC1155BatchReceived(address operator,address from,uint256[] ids,uint256[] values,bytes data)");

    // Internal functions

    /// @notice Sets expectation for a single acceptance call if no other expectation is active
    /// @param operator The address performing the transfer
    /// @param from The address tokens are being transferred from
    /// @param id The token id being transferred
    /// @param value The amount being transferred
    /// @param data Additional data passed with transfer
    function _setExpectationSingleAcceptanceCall(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) internal {
        // Check if slot is empty
        bytes32 currentExpectation;
        // assembly does not like the constants
        bytes32 slot = EXPECTATION_SLOT;
        assembly {
            currentExpectation := tload(slot)
        }
        if (currentExpectation != bytes32(0)) {
            revert ExpectationAlreadySet(currentExpectation);
        }

        // Generate and store the acceptance hash
        bytes32 acceptanceHash = _hashSingleAcceptanceCall(operator, from, id, value, data);

        assembly {
            tstore(slot, acceptanceHash)
        }
    }

    /// @notice Sets expectation for a batch acceptance call if no other expectation is active
    /// @param operator The address performing the transfer
    /// @param from The address tokens are being transferred from
    /// @param ids Array of token ids being transferred
    /// @param values Array of amounts being transferred
    /// @param data Additional data passed with transfer
    function _setExpectationBatchAcceptanceCall(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) internal {
        // Check if slot is empty
        bytes32 currentExpectation;
        // assembly does not like the constants
        bytes32 slot = EXPECTATION_SLOT;
        assembly {
            currentExpectation := tload(slot)
        }
        if (currentExpectation != bytes32(0)) {
            revert ExpectationAlreadySet(currentExpectation);
        }

        // Generate and store the acceptance hash
        bytes32 acceptanceHash = _hashBatchAcceptanceCall(operator, from, ids, values, data);

        assembly {
            tstore(slot, acceptanceHash)
        }
    }

    /// @notice Hashes parameters for a single token acceptance call
    /// @param operator The address performing the transfer
    /// @param from The address tokens are being transferred from
    /// @param id The token id being transferred
    /// @param value The amount being transferred
    /// @param data Additional data passed with transfer
    function _hashSingleAcceptanceCall(address operator, address from, uint256 id, uint256 value, bytes calldata data)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(DOMAIN_SEPARATOR_SINGLE_ACCEPTANCE, operator, from, id, value, keccak256(data)));
    }

    /// @notice Hashes parameters for a batch token acceptance call
    /// @param operator The address performing the transfer
    /// @param from The address tokens are being transferred from
    /// @param ids Array of token ids being transferred
    /// @param values Array of amounts being transferred
    /// @param data Additional data passed with transfer
    function _hashBatchAcceptanceCall(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_SEPARATOR_BATCH_ACCEPTANCE, operator, from, ids, values, keccak256(data)));
    }
}
