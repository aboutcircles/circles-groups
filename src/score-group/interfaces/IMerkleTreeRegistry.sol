// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

interface IMerkleTreeRegistry {
    event MerkleRootUpdated(
        address indexed merkleTreeManager, bytes32 newMerkleRoot, bytes32 previousRoot, uint256 updateBlockNumber
    );

    function merkleRoots(address merkleTreeManager)
        external
        view
        returns (bytes32 currentRoot, bytes32 previousRoot, uint256 updateBlockNumber);
    function updateMerkleRoot(bytes32 newMerkleRoot) external;
    function verify(address merkleTreeManager, uint160 key, bytes32 leaf, bytes memory proof)
        external
        view
        returns (bool);
    function verifyWithGracePeriod(address merkleTreeManager, uint160 key, bytes32 leaf, bytes memory proof)
        external
        view
        returns (bool);
}
