// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "src/circles/Core.sol";
import "src/core-members-group/CoreMembersGroup.sol";
import "src/core-members-group/CMGMintHandler.sol";
import "src/core-members-group/CMGRedemptionHandler.sol";
import "src/redemption-operator/CMGRedemptionOperator.sol";
import "src/liquidity-provider/helpers/GroupLiquidityProviderDeployer.sol";

contract CMGroupFactory is CirclesCoreAddresses, CirclesV2BetaAddresses {
    // State

    /// @notice simple salt counter
    uint256 public saltCounter;

    /// @notice simple registration of deployment by this factory
    mapping(address => bool) public deployedByFactory;

    /// @notice deployer for liquidity providers
    GroupLiquidityProviderDeployer public immutable lpDeployer;

    /// @notice redemption operator used by liquidity providers
    CMGRedemptionOperator public immutable redemptionOperator;

    // Events

    /// @notice Emitted when a new CMGroup proxy is deployed
    /// @param cmgroup Core Members group address
    /// @param owner Owner of the new group
    /// @param mintHandler Address of the mintHandler contract
    /// @param redemptionHandler Address of the redemptionHandler contract
    event CMGroupDeployed(
        address indexed cmgroup, address indexed owner, address indexed mintHandler, address redemptionHandler
    );

    // Errors

    /// @notice Logical assertion predicted address matches deployed address
    error CMGroupFactoryWrongPredictedAddress(address predicted, address deployed);

    constructor() {
        // create redemption operator
        redemptionOperator = new CMGRedemptionOperator(getCirclesCore());
        // create deployer for liquidity providers
        lpDeployer = new GroupLiquidityProviderDeployer(redemptionOperator, getCirclesCore());
    }

    /// @notice Creates a new Core Members Group with associated handlers
    /// @dev Deploys three contracts: CMGMintHandler, CMGRedemptionHandler, and CoreMembersGroup
    ///      Uses create2 for deterministic addressing and verifies the predicted address matches
    /// @param _owner The owner address for the new group
    /// @param _service The service address for the new group
    /// @param _mintHandler The mint handler address for the new group
    /// @param _redemptionHandler The redemption handler address for the new group
    /// @param _initialConditions Array of initial condition addresses
    /// @param _name Name of the token
    /// @param _symbol Symbol of the token
    /// @param _metadataDigest Hash of additional metadata
    /// @param _circlesCore Struct containing core protocol addresses
    /// @return coreMembersGroup Address of the deployed Core Members Group contract
    /// @return mintHandler Address of the deployed mint handler contract
    /// @return redemptionHandler Address of the deployed redemption handler contract
    function createCMGroup(
        address _owner,
        address _service,
        address _mintHandler,
        address _redemptionHandler,
        address[] memory _initialConditions,
        string memory _name,
        string memory _symbol,
        bytes32 _metadataDigest,
        CirclesCore memory _circlesCore
    ) external returns (address coreMembersGroup, address mintHandler, address redemptionHandler) {
        // use a sequence number as salt
        ++saltCounter;

        // load Circles v2 core protocol addresses
        CirclesCore memory circlesCore = getCirclesCore();

        // note: we need to use a predicted address to pass it to the handlers for separate deployment
        address predictedCMGAddress = computeCMGroupAddress(
            saltCounter,
            _owner,
            _service,
            _mintHandler,
            _redemptionHandler,
            _initialConditions,
            _name,
            _symbol,
            _metadataDigest,
            circlesCore
        );

        // deploy mint and redemption handlers
        mintHandler = address(new CMGMintHandler(predictedCMGAddress, _owner, _name, circlesCore));
        redemptionHandler = address(new CMGRedemptionHandler(predictedCMGAddress, _owner, circlesCore));

        // create Core Members Group itself
        coreMembersGroup = address(
            new CoreMembersGroup{salt: bytes32(saltCounter)}(
                saltCounter,
                _owner,
                _service,
                _mintHandler,
                _redemptionHandler,
                _initialConditions,
                _name,
                _symbol,
                _metadataDigest,
                circlesCore
            )
        );

        if (coreMembersGroup != predictedCMGAddress) {
            revert CMGroupFactoryWrongPredictedAddress(predictedCMGAddress, coreMembersGroup);
        }

        // store deployment explicitly for easiest check by wallet
        deployedByFactory[coreMembersGroup] = true;

        // ensure static ERC20 wrapper is deployed for group
        _circlesCore.erc20Lift.ensureERC20(coreMembersGroup, CirclesType.Inflation);

        emit CMGroupDeployed(coreMembersGroup, _owner, _mintHandler, _redemptionHandler);

        return (coreMembersGroup, _mintHandler, _redemptionHandler);
    }

    /// @notice Computes the deterministic deployment address for a Core Members Group
    function computeCMGroupAddress(
        uint256 saltIndex,
        address _owner,
        address _service,
        address _mintHandler,
        address _redemptionHandler,
        address[] memory _initialConditions,
        string memory _name,
        string memory _symbol,
        bytes32 _metadataDigest,
        CirclesCore memory _circlesCore
    ) public view returns (address) {
        bytes32 salt = bytes32(saltIndex);

        bytes32 encodedConstructorArgs = encodeConstructorArguments(
            _owner,
            _service,
            _mintHandler,
            _redemptionHandler,
            _initialConditions,
            _name,
            _symbol,
            _metadataDigest,
            _circlesCore
        );

        address predictedAddress = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, encodedConstructorArgs))))
        );

        return predictedAddress;
    }

    /// @notice encoding function to compute the deterministic deployment address of a CMG
    function encodeConstructorArguments(
        address _owner,
        address _service,
        address _mintHandler,
        address _redemptionHandler,
        address[] memory _initialConditions,
        string memory _name,
        string memory _symbol,
        bytes32 _metadataDigest,
        CirclesCore memory _circlesCore
    ) public pure returns (bytes32) {
        bytes memory constructorArgs = abi.encode(
            _owner,
            _service,
            _mintHandler,
            _redemptionHandler,
            _initialConditions,
            _name,
            _symbol,
            _metadataDigest,
            _circlesCore
        );

        return keccak256(abi.encodePacked(type(CoreMembersGroup).creationCode, constructorArgs));
    }

    /// @notice additional helper verification function to recalculate deployment address
    /// @dev largely superceded by explicitly storing the deployedByFactory boolean,
    /// but because we still use create2, for deploying the three contracts, keep this helper function here
    function verifyFactoryGroupDeployment(address deployedAddress, uint256 saltIndex, bytes32 encodedConstructorArgs)
        public
        view
        returns (bool)
    {
        // salt index must be smaller than counter
        if (saltIndex >= saltCounter) return false;

        // proceed to generate the predicted address
        address predictedAddress = address(
            uint160(
                uint256(
                    keccak256(abi.encodePacked(bytes1(0xff), address(this), bytes32(saltIndex), encodedConstructorArgs))
                )
            )
        );

        return predictedAddress == deployedAddress;
    }
}
