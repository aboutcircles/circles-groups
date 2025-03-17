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

    /// @notice salt counter is to use as a salt a sequence number to
    /// verify deployed contracts originated from this factory
    uint256 public saltCounter;

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

    constructor() {
        // create redemption operator
        redemptionOperator = new CMGRedemptionOperator(getCirclesCore());
        // create deployer for liquidity providers
        lpDeployer = new GroupLiquidityProviderDeployer(redemptionOperator, getCirclesCore());
    }

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

        (address predictedCMGAddress,) = computeCMGroupAddress(
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

        // ensure static ERC20 wrapper is deployed for group
        _circlesCore.erc20Lift.ensureERC20(coreMembersGroup, CirclesType.Inflation);

        emit CMGroupDeployed(coreMembersGroup, _owner, _mintHandler, _redemptionHandler);

        return (coreMembersGroup, _mintHandler, _redemptionHandler);
    }

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
    ) public view returns (address, bytes32) {
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

        return (predictedAddress, encodedConstructorArgs);
    }

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

    function verifyCMGroupDeployment(address deployedAddress, uint256 saltIndex, bytes32 encodedConstructorArgs)
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
