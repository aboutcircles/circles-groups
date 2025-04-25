// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "src/membership-conditions/ICirclesBackingFactory.sol";

/// @notice Test LBP Factory for 1 USD backing contract addresses
///         on Gnosis Chain.
contract TestLBPOneUsdCoreAddresses {
    // Constants

    /// @notice Launchpad enables people to back their personal CRC in an LBP pool.
    ///         This Circles Backing group will explicitly check the launchpad whether
    ///         a person has backed their Circles.
    /// WARNING: this is not the final production address. This is the 1 USD test launchpad
    ICirclesBackingFactory public launchpad =
        ICirclesBackingFactory(address(0x4bB5A425a68ed73Cf0B26ce79F5EEad9103C30fc));
}

/// @notice Test LBP Factory for 10 USD backing contract addresses
///         on Gnosis Chain.
contract TestLBPTenUsdCoreAddresses {
    // Constants

    /// @notice Launchpad enables people to back their personal CRC in an LBP pool.
    ///         This Circles Backing group will explicitly check the launchpad whether
    ///         a person has backed their Circles.
    /// WARNING: this is not the final production address. This is the 10 USD test launchpad
    ICirclesBackingFactory public launchpad =
        ICirclesBackingFactory(address(0xD10D53Ec77cE25829b7d270D736403218AF22Ad9));
}
