// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {SMT} from "src/score-group/libraries/SparseMerkleTree.sol";

contract MerkleTreeRegistry {
    using SMT for bytes32;

    struct MerkleRoot {
        bytes32 currentRoot;
        bytes32 previousRoot;
        uint256 updateBlockNumber;
    }

    // =================================================
    //                    EVENTS
    // =================================================

    event MerkleRootUpdated(
        address indexed merkleTreeManager, bytes32 newMerkleRoot, bytes32 previousRoot, uint256 updateBlockNumber
    );

    // =================================================
    //                     CONSTANTS
    // =================================================

    uint256 internal constant ROOT_GRACE_PERIOD_BLOCKS = 2;

    // =================================================
    //                    STATE
    // =================================================

    mapping(address merkleTreeManager => MerkleRoot merkleRoot) public merkleRoots;

    // =================================================
    //                 EXTERNAL FUNCTIONS
    // =================================================

    function updateMerkleRoot(bytes32 newMerkleRoot) external {
        address merkleTreeManager = msg.sender;
        bytes32 previousRoot = merkleRoots[merkleTreeManager].currentRoot;
        merkleRoots[merkleTreeManager] = MerkleRoot(newMerkleRoot, previousRoot, block.number);
        emit MerkleRootUpdated(merkleTreeManager, newMerkleRoot, previousRoot, block.number);
    }

    function verify(address merkleTreeManager, uint160 key, bytes32 leaf, bytes memory proof)
        external
        view
        returns (bool)
    {
        if (!merkleRoots[merkleTreeManager].currentRoot.verify(key, leaf, proof)) {
            if (
                block.number > merkleRoots[merkleTreeManager].updateBlockNumber + ROOT_GRACE_PERIOD_BLOCKS
                    || !merkleRoots[merkleTreeManager].previousRoot.verify(key, leaf, proof)
            ) return false;
        }
        return true;
    }
}
