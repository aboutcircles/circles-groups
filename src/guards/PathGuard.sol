// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.24;

import "../errors/Errors.sol";

contract PathGuard is IGuardsErrors {
    // Modifiers

    modifier onlyExplicitGroupMint(bytes calldata _data, uint8 _code) {
        if (_data.length == 0) {
            revert CirclesPathGuardOnlyExplicitGroupMint(_code);
        }
        _;
    }
}
