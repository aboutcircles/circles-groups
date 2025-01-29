// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "openzeppelin-contracts/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "circles-contracts-v2/hub/TypeDefinitions.sol";
import "src/circles/Core.sol";
import "src/errors/Errors.sol";
import "src/CoreMembersGroup/CMGHandler.sol";

/// @notice
contract CMGRedemptionHandler is CMGHandler {
    // Constants

    /// @notice Indefinite future, or approximated with uint96.max
    uint96 internal constant INDEFINITE_FUTURE = type(uint96).max;

    // Constructor

    constructor(address _cmGroup, address _owner, string memory _name) CMGHandler(_cmGroup, _owner) {
        // append "-redeemer" to group's name to register organization
        string memory orgName = string.concat(_name, "-redeemer");
        // register handler as organization in hub
        hub.registerOrganization(orgName, bytes32(0));
        hub.trust(_cmGroup, INDEFINITE_FUTURE);
    }
}
