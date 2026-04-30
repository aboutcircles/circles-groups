// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

// Mock
contract Score {
    uint256 public constant SCALE = 1e18;

    bytes32 internal _root;

    function root() external view returns (bytes32) {
        return _root;
    }

    function rootAt(uint256 /*version*/ ) external view returns (bytes32) {
        return _root;
    }

    function currentVersion() external pure returns (uint256) {
        return 0;
    }

    function verify(bytes calldata, /*proof*/ address, /*avatar*/ uint256 /*score*/ ) external pure {
        return;
    }

    function setRoot(bytes32 newRoot) external {
        _root = newRoot;
    }
}
