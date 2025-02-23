// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import {StandardTreasury} from "circles-contracts-v2/treasury/StandardTreasury.sol";
import {IStandardVault} from "circles-contracts-v2/treasury/IStandardVault.sol";
import {StandardVault} from "circles-contracts-v2/treasury/StandardVault.sol";

interface INameRegistry {
    function customNames(address) external view returns (string memory);
}

interface IHub {
    function registerOrganization(string memory _name, bytes32 _metadataDigest) external;
    function trust(address _trustReceiver, uint96 _expiry) external;
}

/// @dev Used by StandardTreasury and extends StandardVault with shielding organization functionality.
contract StandardVaultShield is StandardVault {
    // Errors

    /// Vault is already registered as a shielding organization.
    error Registered();
    /// Only group the vault is coupled to is able to call.
    error OnlyGroup();

    // Immutable

    /**
     * @notice Address of the NameRegistry contract
     */
    address public immutable nameRegistry;

    // State variables

    /**
     * @notice Address of the group
     */
    address public group;

    /**
     * @notice Constructor to create a Standard Vault implementation
     * @param _nameRegistry Address of the NameRegistry contract
     */
    constructor(address _nameRegistry) StandardVault() {
        nameRegistry = _nameRegistry;
    }

    /**
     * @notice Allows group to register Standard Vault as organization.
     */
    function registerShieldOrg() external {
        if (group != address(0)) revert Registered();
        if (address(StandardTreasury(standardTreasury).vaults(msg.sender)) != address(this)) revert OnlyGroup();
        // store group
        group = msg.sender;
        // make vault an organization
        string memory groupName = INameRegistry(nameRegistry).customNames(msg.sender);
        string memory orgName = string.concat(groupName, "-shieldVault");
        IHub(address(hub)).registerOrganization(orgName, bytes32(0));
    }

    /**
     * @notice Allows group to enable/disable shielding organization functionality.
     */
    function setShieldOrgStatus(bool enabled) external {
        if (msg.sender != group) revert OnlyGroup();
        if (enabled) {
            // trust indefinitely group
            IHub(address(hub)).trust(group, type(uint96).max);
        } else {
            // untrust group
            IHub(address(hub)).trust(group, uint96(0));
        }
    }

    /**
     * @notice Burns group CRC received via transitive transfer.
     */
    function burn() external {
        uint256 id = uint256(uint160(group));
        if (id != 0) {
            uint256 amount = hub.balanceOf(address(this), id);
            hub.burn(id, amount, "");
        }
    }
}
