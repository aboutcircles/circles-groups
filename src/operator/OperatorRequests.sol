// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "src/errors/Errors.sol";
import "src/policies/PolicyTypes.sol";

abstract contract OperatorRequest is ISupergroupOperatorErrors {
    // Using transient storage for request validation
    uint256 internal constant REQUEST_TSTORAGE_SLOT = 0x11223344; // Arbitrary unique slot

    function _initiateRequest(address policy, uint256 policyId, uint256 tokenId, uint256 amount)
        internal
        returns (bytes memory)
    {
        // check the storage slot is empty first
        bytes32 currentRequest;
        assembly {
            currentRequest := tload(REQUEST_TSTORAGE_SLOT)
        }
        if (currentRequest != 0) {
            revert SupergroupOperatorRequestInProgress();
        }

        PolicyTypes.OperatorRequest memory request = PolicyTypes.OperatorRequest({
            operator: address(this),
            policyId: policyId,
            tokenId: tokenId,
            amount: amount,
            nonce: 0 // using transient storage and a lock instead
        });

        bytes32 requestHash = PolicyTypes.hashOperatorRequest(request);
        assembly {
            tstore(REQUEST_TSTORAGE_SLOT, requestHash)
        }

        return abi.encode(request);
    }
}
