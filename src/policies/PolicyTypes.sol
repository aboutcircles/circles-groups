// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

library PolicyTypes {
    // Domain separator for operator requests
    bytes32 public constant DOMAIN_SEPARATOR = keccak256(
        "PolicyOperatorRequest(address operator,uint256 policyId,uint256 tokenId,uint256 amount,uint256 nonce)"
    );

    struct OperatorRequest {
        address operator; // Address of the operator contract
        uint256 policyId; // (optional) a policy configuration identifier
        uint256 tokenId; // ECR1155 token ID (which identifies the group for the policy)
        uint256 amount; // amount being requested by operator
        uint256 nonce; // Nonce to prevent replay
            // (optional when operator uses transient storage and re-entrancy guard)
    }

    function hashOperatorRequest(OperatorRequest memory _request) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                DOMAIN_SEPARATOR,
                _request.operator,
                _request.policyId,
                _request.tokenId,
                _request.amount,
                _request.nonce
            )
        );
    }
}
