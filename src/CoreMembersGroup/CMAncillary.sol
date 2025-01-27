// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "circles-contracts-v2/hub/TypeDefinitions.sol";
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
        // append "-ancillary" to group's name to register organization
        string memory orgName = string.concat(_name, "-ancillary");
        // register ancillary as organization in hub
        hub.registerOrganization(orgName, bytes32(0));
    }

    // External functions

    function mirrorTrust(address _backer, uint96 _expiry) external onlyCMGroup {
        hub.trust(_backer, _expiry);
    }

    /// @notice Sync trust relationships from the CMgroup to the ancillary.
    ///         For each trust relation of the CMgroup, trust that account
    ///         with the same expiry time. If the ancillary currently trusts
    ///         an account that is not trusted by the CMgroup anymore,
    ///         untrust by setting the expiry time to current block.
    /// @param _trustRelations Array of addresses to sync trust status for
    function syncTrust(address[] calldata _trustRelations) external {
        uint256 length = _trustRelations.length;
        address trustee;
        for (uint256 i = 0; i < length; i++) {
            trustee = _trustRelations[i];
            if (hub.isTrusted(cmGroup, trustee)) {
                TypeDefinitions.TrustMarker memory marker = hub.trustMarkers(cmGroup, trustee);
                hub.trust(trustee, marker.expiry);
            } else {
                // if ancillary trusts this trustee
                // untrust by setting expiry to block.timestamp
                if (hub.isTrusted(address(this), trustee)) {
                    hub.trust(trustee, uint96(block.timestamp));
                }
            }
        }
    }

    // ERC1155 acceptance call handlers
}
