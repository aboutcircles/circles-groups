// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

contract CoreMembersGroupStorage {
    // Constants

    // keccak256(abi.encode(uint256(keccak256("circles.storage.CoreMembersGroup")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant STATE_STORAGE_SLOT = 0x91697a2af80a11a747c8f7c8c9fdbc08adbc198c96a843765cad94d605b7e400;

    // State

    /// @custom:storage-location erc7201:circles.storage.CoreMembersGroup
    struct State {
        address owner;
        address mintHandler;
        address redemptionHandler;
        address service;
        address feeCollection;
        address[] membershipConditions;
    }

    function _state() internal pure returns (State storage state) {
        bytes32 stateSlot = STATE_STORAGE_SLOT;
        assembly {
            state.slot := stateSlot
        }
    }
}
