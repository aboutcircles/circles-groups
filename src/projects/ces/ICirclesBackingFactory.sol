// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

interface ICirclesBackingFactory {
    /// @notice checks if the backer has an active LBP at the factory
    function isActiveLBP(address backer) external view returns (bool);
}
