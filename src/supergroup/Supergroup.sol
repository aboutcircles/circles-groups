// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "circles-contracts-v2/hub/IHub.sol";

/// Supergroups are opinionated liquidity clusters of valued Circles
/// Either personal Circles directly, or nuclear group Circles can be
/// trusted as valid collateral for the supergroup.
contract Supergroup {
    // State variables

    /// Hub contract
    IHubV2 immutable hub;

    // Constructor

    constructor(IHubV2 _hub) {
        hub = _hub;
    }
}
