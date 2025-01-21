// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

library PolicyTypes {
    /// @notice Domain separator for operator requests
    bytes32 public constant DOMAIN_SEPARATOR_OPERATOR_REQUEST =
        keccak256("PolicyOperatorRequest(address minter,address group,uint256[] collateral,uint256[] amounts)");

    /// @notice Domain separator for policy fingerprints
    bytes32 public constant DOMAIN_SEPARATOR_POLICY_FINGERPRINT =
        keccak256("PolicyFingerprint(address group,uint256 collateral)");

    function hashRequest(address _minter, address _group, uint256[] calldata _collateral, uint256[] calldata _amounts)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(DOMAIN_SEPARATOR_OPERATOR_REQUEST, _minter, _group, _collateral, _amounts));
    }

    function hashFingerprint(address _group, uint256 _collateral) internal pure returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_SEPARATOR_POLICY_FINGERPRINT, _group, _collateral));
    }
}
