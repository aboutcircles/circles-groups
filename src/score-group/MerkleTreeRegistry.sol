// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {SMT} from "src/score-group/libraries/SparseMerkleTree.sol";

/**
 * @title MerkleTreeRegistry
 * @notice Registry for Sparse Merkle Tree roots keyed by Merkle tree manager address.
 * @dev Each caller manages its own root namespace. Root updates retain the previous root for a short
 *      grace period, allowing consumers to choose between strict current-root verification and
 *      compatibility verification that also accepts proofs against the recently replaced root.
 */
contract MerkleTreeRegistry {
    /// @dev Adds Sparse Merkle Tree proof verification helpers to root values.
    using SMT for bytes32;

    /**
     * @notice Merkle root state for a single Merkle tree manager.
     * @dev `previousRoot` is retained so consumers using grace-period verification can accept
     *      proofs against the prior tree for `ROOT_GRACE_PERIOD_BLOCKS` blocks after an update.
     * @param currentRoot Active Sparse Merkle Tree root.
     * @param previousRoot Sparse Merkle Tree root that was active immediately before `currentRoot`.
     * @param updateBlockNumber Block number at which `currentRoot` was written.
     */
    struct MerkleRoot {
        bytes32 currentRoot;
        bytes32 previousRoot;
        uint256 updateBlockNumber;
    }

    // =================================================
    //                    EVENTS
    // =================================================

    /**
     * @notice Emitted when a Merkle tree manager updates its root.
     * @param merkleTreeManager Address whose root namespace was updated.
     * @param newMerkleRoot New active Sparse Merkle Tree root.
     * @param previousRoot Sparse Merkle Tree root that was active immediately before the update.
     * @param updateBlockNumber Block number at which the root update was recorded.
     */
    event MerkleRootUpdated(
        address indexed merkleTreeManager, bytes32 newMerkleRoot, bytes32 previousRoot, uint256 updateBlockNumber
    );

    // =================================================
    //                     CONSTANTS
    // =================================================

    /// @notice Number of blocks during which proofs against the previous root remain valid after an update.
    uint256 internal constant ROOT_GRACE_PERIOD_BLOCKS = 2;

    // =================================================
    //                    STATE
    // =================================================

    /**
     * @notice Merkle root state per Merkle tree manager.
     * @dev Public getter returns the current root, previous root, and latest update block number
     *      for `merkleTreeManager`.
     */
    mapping(address merkleTreeManager => MerkleRoot merkleRoot) public merkleRoots;

    // =================================================
    //                 EXTERNAL FUNCTIONS
    // =================================================

    /**
     * @notice Updates the caller's active Sparse Merkle Tree root.
     * @dev The caller is treated as the Merkle tree manager. The existing current root is moved to
     *      `previousRoot`, and `newMerkleRoot` becomes the active root at the current block number.
     * @param newMerkleRoot New Sparse Merkle Tree root to register for the caller.
     */
    function updateMerkleRoot(bytes32 newMerkleRoot) external {
        address merkleTreeManager = msg.sender;
        bytes32 previousRoot = merkleRoots[merkleTreeManager].currentRoot;
        merkleRoots[merkleTreeManager] = MerkleRoot(newMerkleRoot, previousRoot, block.number);
        emit MerkleRootUpdated(merkleTreeManager, newMerkleRoot, previousRoot, block.number);
    }

    /**
     * @notice Verifies a Sparse Merkle Tree proof against a manager's current root.
     * @dev This function checks only the active root for `merkleTreeManager` and does not fall back to
     *      the previous root during the grace period.
     * @param merkleTreeManager Address whose Merkle root namespace should be used for verification.
     * @param key Sparse Merkle Tree key being proven.
     * @param leaf Leaf value expected at `key`.
     * @param proof Sparse Merkle Tree proof for `key` and `leaf`.
     * @return True if the proof is valid against the current root; false otherwise.
     */
    function verify(address merkleTreeManager, uint160 key, bytes32 leaf, bytes memory proof)
        public
        view
        returns (bool)
    {
        return merkleRoots[merkleTreeManager].currentRoot.verify(key, leaf, proof);
    }

    /**
     * @notice Verifies a Sparse Merkle Tree proof against a manager's current or recently previous root.
     * @dev Verification first checks the current root for `merkleTreeManager`. If that fails, the proof is
     *      checked against the previous root only while the current block is within
     *      `ROOT_GRACE_PERIOD_BLOCKS` blocks of the latest root update.
     * @param merkleTreeManager Address whose Merkle root namespace should be used for verification.
     * @param key Sparse Merkle Tree key being proven.
     * @param leaf Leaf value expected at `key`.
     * @param proof Sparse Merkle Tree proof for `key` and `leaf`.
     * @return True if the proof is valid against the current root, or against the previous root during
     *         the grace period; false otherwise.
     */
    function verifyWithGracePeriod(address merkleTreeManager, uint160 key, bytes32 leaf, bytes memory proof)
        external
        view
        returns (bool)
    {
        if (!verify(merkleTreeManager, key, leaf, proof)) {
            if (
                block.number > merkleRoots[merkleTreeManager].updateBlockNumber + ROOT_GRACE_PERIOD_BLOCKS
                    || !merkleRoots[merkleTreeManager].previousRoot.verify(key, leaf, proof)
            ) return false;
        }
        return true;
    }
}
