// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

interface ICMGMintHandler {
    /// @notice Mirrors trust of the CM group with _backer until _expiry for the Ancillary
    function mirrorTrust(address _backer, uint96 _expiry) external;
}
