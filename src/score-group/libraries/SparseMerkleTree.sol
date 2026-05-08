// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

library SMT {
    function verify(bytes32 root, uint160 key, bytes32 leaf, bytes memory proof) internal pure returns (bool) {
        bytes32 calculatedRoot = _getRoot(leaf, key, proof);
        return (calculatedRoot == root);
    }

    function _getRoot(bytes32 leaf, uint160 _index, bytes memory proof) internal pure returns (bytes32) {
        require((proof.length - 20) % 32 == 0 && proof.length <= 5140, "invalid proof format");
        bytes32 proofElement;
        bytes32 computedHash = leaf;
        uint16 p = 20;
        uint160 proofBits;
        uint160 index = _index;
        assembly { proofBits := div(mload(add(proof, 32)), exp(256, 12)) }

        for (uint256 d = 0; d < 160; d++) {
            if (proofBits % 2 == 0) {
                // check if last bit of proofBits is 0
                proofElement = 0;
            } else {
                p += 32;
                require(proof.length >= p, "proof not long enough");
                assembly { proofElement := mload(add(proof, p)) }
            }
            if (computedHash == 0 && proofElement == 0) {
                computedHash = 0;
            } else if (index % 2 == 0) {
                assembly {
                    mstore(0, computedHash)
                    mstore(0x20, proofElement)
                    computedHash := keccak256(0, 0x40)
                }
            } else {
                assembly {
                    mstore(0, proofElement)
                    mstore(0x20, computedHash)
                    computedHash := keccak256(0, 0x40)
                }
            }
            proofBits = proofBits / 2; // shift it right for next bit
            index = index / 2;
        }
        return computedHash;
    }
}
