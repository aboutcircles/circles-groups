// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

library PolicyTypes {
    // Domain separator for operator requests
    bytes32 public constant DOMAIN_SEPARATOR =
        keccak256("PolicyOperatorRequest(address minter,uint256 group,uint256[] collateral,uint256[] amounts)");

    function hashRequest(address minter, address group, uint256[] calldata collateral, uint256[] calldata amounts)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(DOMAIN_SEPARATOR, minter, group, collateral, amounts));
    }
}
