// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import {Test} from "forge-std/Test.sol";
import "src/core-members-group/patch01/CoreMembersGroupStoragePatch01.sol";

contract MockCMGStorage is CoreMembersGroupStorage {
    function getStateStorageSlot() external pure returns (bytes32) {
        return STATE_STORAGE_SLOT;
    }

    function getStandardTreasurySlot() external pure returns (bytes32) {
        return STATE_TREASURY_SLOT;
    }
}

contract ConstantCalculatorTest is Test {
    MockCMGStorage mock;

    function setUp() public {
        mock = new MockCMGStorage();
    }

    function testCalculateConstants() public view {
        // Calculate slot namespace
        bytes32 slotNamespace =
            keccak256(abi.encode(uint256(keccak256("circles.storage.CoreMembersGroup")) - 1)) & ~bytes32(uint256(0xff));

        // Compare with actual constant
        assertEq(slotNamespace, mock.getStateStorageSlot());

        // Ensure result matches expected format
        assert(uint256(slotNamespace) & 0xff == 0);
    }

    function testCalculateStandardTreasurySlot() public view {
        // Calculate slot namespace
        bytes32 slotNamespace = keccak256(
            abi.encode(uint256(keccak256("circles.storage.patch01.StandardTreasury")) - 1)
        ) & ~bytes32(uint256(0xff));

        // Compare with actual constant
        assertEq(slotNamespace, mock.getStandardTreasurySlot());

        // Ensure result matches expected format
        assert(uint256(slotNamespace) & 0xff == 0);
    }
}
