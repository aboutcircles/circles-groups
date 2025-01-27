// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "src/circles/Core.sol";
import "src/errors/Errors.sol";

/// @notice CoreMembers(CM) group Ancillary is deployed by the CMgroup
///         and functions as a helper for group mints and redemptions.
///         For path-based group mints the ancillary can not enforce
///         custom requirements (eg. extended membership to the group),
///         so for a general framework one should use ERC1155 operators.
///         For redemption the ancillary provides simplified methods
///         to perform automatic redemption to the underlying collateral.
contract CMAncillary is CirclesCoreAddresses, ICMGroupAncillaryErrors, ICMGroupErrors {
    // State

    /// @notice CMgroup for which this is an ancillary.
    address public cmGroup;

    // Modifiers

    /// @notice Only the Circles Hub can call this function
    modifier onlyHub() {
        if (msg.sender != address(hub)) {
            revert CMGroupOnlyHub();
        }
        _;
    }

    modifier onlyCMGroup() {
        if (msg.sender != cmGroup) {
            revert CMAncillaryOnlyCMGroup();
        }
        _;
    }

    // Constructor

    constructor(address _cmGroup, string memory _name) {
        // ancillary is deployed by deployment helper
        cmGroup = _cmGroup;

        // register ancillary as organization in hub
    }

    // External functions

    function mirrorTrust(address _backer, uint96 _expiry) external onlyCMGroup {
        hub.trust(_backer, _expiry);
    }

    // ERC1155 acceptance call handlers
}
