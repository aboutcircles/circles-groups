// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "src/base-group/BaseGroup.sol";

contract BaseGroupFactory {
    // Events

    /// @notice Emitted when a new BaseGroup is created
    /// @param group Base group address
    /// @param owner Owner of the new group
    /// @param mintHandler Address of the mintHandler contract
    /// @param treasury Address of the treasury contract
    event BaseGroupCreated(address indexed group, address indexed owner, address indexed mintHandler, address treasury);

    // State

    /// @notice simple registration of deployment by this factory
    mapping(address => bool) public deployedByFactory;

    // External functions

    /// @notice Creates a new Base Group
    /// @param _owner The owner address for the new group
    /// @param _service The service address for the new group
    /// @param _initialConditions Array of initial condition addresses
    /// @param _name Name of the token
    /// @param _symbol Symbol of the token
    /// @param _metadataDigest Hash of additional metadata
    /// @return group Address of the deployed Base Group contract
    /// @return mintHandler Address of the deployed mint handler contract
    /// @return treasury Address of the deployed treasury contract
    function createBaseGroup(
        address _owner,
        address _service,
        address[] memory _initialConditions,
        string memory _name,
        string memory _symbol,
        bytes32 _metadataDigest
    ) external returns (address group, address mintHandler, address treasury) {
        // create Base Group itself
        BaseGroup baseGroup = new BaseGroup(_owner, _service, _initialConditions, _name, _symbol, _metadataDigest);

        mintHandler = address(baseGroup.BASE_MINT_HADLER());
        treasury = baseGroup.BASE_TREASURY();
        group = address(baseGroup);

        // store deployment explicitly for easiest check by wallet
        deployedByFactory[group] = true;

        emit BaseGroupCreated(group, _owner, mintHandler, treasury);
    }
}
