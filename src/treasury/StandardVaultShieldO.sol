// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import {IHubV2, StandardVault} from "circles-contracts-v2/treasury/StandardVault.sol";

interface INameRegistry {
    function customNames(address) external view returns (string memory);
}

interface IHub {
    function registerOrganization(string memory _name, bytes32 _metadataDigest) external;
    function trust(address _trustReceiver, uint96 _expiry) external;
}

/// @dev Used by StandardTreasuryOverriden and extends StandardVault with shielding organization functionality by default.
contract StandardVaultShield is StandardVault {
    // Errors

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

    // External functions

    /**
     * @notice Setup the vault, which is by default shielding organization
     * @param _hub Address of the hub contract
     * @param _group Address of the group contract
     */
    function setup(IHubV2 _hub, address _group) external {
        if (address(hub) != address(0)) {
            // Vault: already initialized
            revert CirclesProxyAlreadyInitialized();
        }
        standardTreasury = msg.sender;
        hub = _hub;
        group = _group;

        // make vault an organization
        string memory groupName = INameRegistry(nameRegistry).customNames(_group);
        string memory orgName = string.concat(groupName, "-shieldVault");
        IHub(address(_hub)).registerOrganization(orgName, bytes32(0));
        // trust indefinitely group
        IHub(address(_hub)).trust(_group, type(uint96).max);
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
        uint256 amount = hub.balanceOf(address(this), id);
        hub.burn(id, amount, "");
    }
}
