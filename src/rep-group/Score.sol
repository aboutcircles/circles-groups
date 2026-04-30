// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

contract Score {
    uint256 public constant SCALE = 1e18;

    function root() external view returns (bytes32) {
        
    }

    function rootAt(uint256 version) external view returns (bytes32) {}

    function currentVersion() external view returns (uint256) {}

    function verify(bytes calldata proof, address avatar, uint256 score) external view {}

    function setRoot(bytes32 newRoot) external {}
}
