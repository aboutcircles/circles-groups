// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "src/base-group/BaseGroup.sol";

/// @title BaseGroupFactory
/// @notice Factory contract to create instances of BaseGroup.
contract BaseGroupFactory {
    // =================================================
    //                       ERRORS
    // =================================================

    /// @notice Thrown when the provided token name length exceeds 19 characters.
    error MaxNameLength19();

    // =================================================
    //                    EVENTS
    // =================================================

    /// @notice Emitted when a new BaseGroup is created.
    /// @param group BaseGroup address.
    /// @param owner Owner of the new BaseGroup.
    /// @param mintHandler Address of the group mint handler contract.
    /// @param treasury Address of the group treasury contract.
    event BaseGroupCreated(address indexed group, address indexed owner, address indexed mintHandler, address treasury);

    // =================================================
    //                    STATE
    // =================================================

    /// @notice Simple registration of deployment by this factory. Returns true if the group was deployed by this factory.
    mapping(address group => bool deployed) public deployedByFactory;

    // =================================================
    //               EXTERNAL FUNCTIONS
    // =================================================

    /// @notice Creates a new BaseGroup instance with the given parameters.
    /// @dev Reverts if the provided `_name` is longer than 19 bytes.
    /// @param _owner The address that will own the newly created BaseGroup.
    /// @param _service The address of the service for the new BaseGroup.
    /// @param _feeCollection The address of the fee collection for the new BaseGroup.
    /// @param _initialConditions An array of initial condition addresses.
    /// @param _name The group name (must be 19 characters or fewer).
    /// @param _symbol The group symbol.
    /// @param _metadataDigest A hash containing additional metadata for the BaseGroup.
    /// @return group The address of the deployed BaseGroup instance.
    /// @return mintHandler The address of the BaseGroup's mint handler contract.
    /// @return treasury The address of the BaseGroup's treasury contract.
    function createBaseGroup(
        address _owner,
        address _service,
        address _feeCollection,
        address[] memory _initialConditions,
        string memory _name,
        string memory _symbol,
        bytes32 _metadataDigest
    ) external returns (address group, address mintHandler, address treasury) {
        // early revert for long name
        if (bytes(_name).length > 19) revert MaxNameLength19();
        // create Base Group itself
        BaseGroup baseGroup =
            new BaseGroup(_owner, _service, _feeCollection, _initialConditions, _name, _symbol, _metadataDigest);

        group = address(baseGroup);
        mintHandler = address(baseGroup.BASE_MINT_HANDLER());
        treasury = address(baseGroup.BASE_TREASURY());

        // store deployment explicitly for easiest check
        deployedByFactory[group] = true;

        emit BaseGroupCreated(group, _owner, mintHandler, treasury);
    }
}
