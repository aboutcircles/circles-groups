// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

contract HubStorageWrites is Test {
    // Hub storage slots
    uint256 internal constant DISCOUNTED_BALANCES_SLOT = 17;
    uint256 internal constant OPERATOR_APPROVAL_SLOT = 19;
    uint256 internal constant MINT_TIMES_SLOT = 21;
    uint256 internal constant AVATARS_SLOT = 26;
    uint256 internal constant TRUST_MARKERS_SLOT = 29;

    // Hub address
    /// @dev use constant, but in case of updates refactor into immutable
    address internal constant HUB = 0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8;

    // The address used as the first element of the linked list of avatars.
    uint256 private constant SENTINEL = uint256(1);
    bytes32 private constant MAX_EXPIRY = bytes32(uint256(type(uint96).max) << 160);
    bytes32 private constant TRUE = bytes32(uint256(1));

    /// @dev Sets Hub ERC1155 balance of id for account.
    function _setCRCBalance(uint256 id, address account, uint64 lastUpdatedDay, uint192 balance) internal {
        bytes32 idSlot = keccak256(abi.encodePacked(id, DISCOUNTED_BALANCES_SLOT));
        bytes32 accountSlot = keccak256(abi.encodePacked(uint256(uint160(account)), idSlot));
        uint256 discountedBalance = (uint256(lastUpdatedDay) << 192) + balance;
        vm.store(HUB, accountSlot, bytes32(discountedBalance));
    }

    /// @dev Sets max expiry trust.
    function _setTrust(address truster, address trusted) internal {
        bytes32 trusterSlot = keccak256(abi.encodePacked(uint256(uint160(truster)), TRUST_MARKERS_SLOT));
        bytes32 trustedSlot = keccak256(abi.encodePacked(uint256(uint160(trusted)), trusterSlot));
        vm.store(HUB, trustedSlot, MAX_EXPIRY);
    }

    /// @dev Simulates human registration.
    function _registerHuman(address account) internal {
        _insertAvatar(account);
        _setMintTime(account);
    }

    function _setOperatorApproval(address account, address operator) internal {
        bytes32 accountSlot = keccak256(abi.encodePacked(uint256(uint160(account)), OPERATOR_APPROVAL_SLOT));
        bytes32 operatorSlot = keccak256(abi.encodePacked(uint256(uint160(operator)), accountSlot));
        vm.store(HUB, operatorSlot, TRUE);
    }

    /// @dev Sets Hub mint times for avatar.
    function _insertAvatar(address avatar) internal {
        // last and avatar slots
        bytes32 lastAvatarSlot = keccak256(abi.encodePacked(SENTINEL, AVATARS_SLOT));
        bytes32 newAvatarSlot = keccak256(abi.encodePacked(uint256(uint160(avatar)), AVATARS_SLOT));
        // read last value
        bytes32 lastAvatarValue = vm.load(HUB, lastAvatarSlot);
        // write new value to last slot
        vm.store(HUB, lastAvatarSlot, bytes32(uint256(uint160(avatar))));
        // write last value to new slot
        vm.store(HUB, newAvatarSlot, lastAvatarValue);
    }

    /// @dev Sets Hub mint times for avatar.
    function _setMintTime(address avatar) internal {
        bytes32 avatarSlot = keccak256(abi.encodePacked(uint256(uint160(avatar)), MINT_TIMES_SLOT));
        uint256 mintTime = block.timestamp << 160;
        vm.store(HUB, avatarSlot, bytes32(mintTime));
    }
}
