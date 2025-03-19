// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

contract CoreMembersGroupStorage {
    // Constants

    // keccak256(abi.encode(uint256(keccak256("circles.storage.CoreMembersGroup")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant STATE_STORAGE_SLOT = 0x91697a2af80a11a747c8f7c8c9fdbc08adbc198c96a843765cad94d605b7e400;

    // added for patch01, only needs to be applied to groups
    // from deployer 0x55785b41703728f1F1F05E77e22B13c3FCc9ce65
    // keccak256(abi.encode(uint256(keccak256("circles.storage.patch01.StandardTreasury")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant STATE_STANDARD_TREASURY_SLOT = 0xc60535c764e7d17044cd1c5b500e587695b3c546f49a308c765a7ee2b9180e00;

    // State

    /// @custom:storage-location erc7201:circles.storage.CoreMembersGroup
    struct State {
        address owner;
        address mintHandler;
        address redemptionHandler;
        address service;
        uint256 minimalDeposit;
        address feeCollection;
        address[] membershipConditions;
    }

    /// @custom:storage-location erc7201:circles.storage.patch01.StandardTreasury
    struct Patch01State {
        address standardTreasury;
    }

    function _state() internal pure returns (State storage state) {
        bytes32 stateSlot = STATE_STORAGE_SLOT;
        assembly {
            state.slot := stateSlot
        }
    }


    /// @notice allocate a new namespace for storage to store standard treasury address for groups
    /// deployed with v1 deployer (0x55785b41703728f1F1F05E77e22B13c3FCc9ce65)
    /// to not conflict with @custom:storage-location erc7201:circles.storage.CoreMembersGroup
    /// @dev the storage layout of v1 deployer contracts with implementation
    /// 0x1e960c859D6e0b7184f2bc66491539b3D128863b at storage slot STATE_STORAGE_SLOT is (see tag v0.0.1)
    /// struct State {
    ///     address owner;
    ///     address mintHandler;
    ///     address redemptionHandler;
    ///     address service;
    ///     uint256 minimalDeposit;
    ///     address feeCollection;
    ///     address[] membershipConditions;
    /// }
    function _patch01StandardTreasury() internal pure returns  (Patch01State storage state) {
        bytes32 stateSlot = STATE_STANDARD_TREASURY_SLOT;
        assembly {
            state.slot := stateSlot
        }
    }
}
