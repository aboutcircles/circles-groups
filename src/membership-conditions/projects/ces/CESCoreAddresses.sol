// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "src/membership-conditions/projects/ces/ICirclesBackingFactory.sol";

/// @notice Circles Core Addresses list the constant addresses
///         of the deployed core contracts of Circles on Gnosis Chain.
contract CESCoreAddresses {
    // Constants

    /// @notice Launchpad enables people to back their personal CRC in an LBP pool.
    ///         This CES group will explicitly check the launchpad whether
    ///         a person has backed their Circles.
    /// WARNING: this is not the final production address
    ICirclesBackingFactory public constant launchpad =
        ICirclesBackingFactory(address(0x4bB5A425a68ed73Cf0B26ce79F5EEad9103C30fc));
}
