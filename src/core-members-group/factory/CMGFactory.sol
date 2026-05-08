// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "src/circles/Core.sol";
import "src/core-members-group/CoreMembersGroup.sol";
// import "src/core-members-group/CMGMintHandler.sol";
// import "src/core-members-group/CMGRedemptionHandler.sol";
import "src/redemption-operator/CMGRedemptionOperator.sol";
import "src/liquidity-provider/helpers/GroupLiquidityProviderDeployer.sol";

contract CMGroupFactory is CirclesCoreAddresses, CirclesV2BetaAddresses {
    // State

    /// @notice simple registration of deployment by this factory
    mapping(address => bool) public deployedByFactory;

    /// @notice deployer for liquidity providers
    GroupLiquidityProviderDeployer public immutable lpDeployer;

    /// @notice redemption operator used by liquidity providers
    CMGRedemptionOperator public immutable redemptionOperator;

    // Events

    /// @notice Emitted when a new CMGroup proxy is created
    /// @param cmgroup Core Members group address
    /// @param owner Owner of the new group
    /// @param mintHandler Address of the mintHandler contract
    /// @param redemptionHandler Address of the redemptionHandler contract
    event CMGroupCreated(
        address indexed cmgroup, address indexed owner, address indexed mintHandler, address redemptionHandler
    );

    // Constructor

    constructor() {
        // create redemption operator
        redemptionOperator = new CMGRedemptionOperator(getCirclesCore());
        // create deployer for liquidity providers
        lpDeployer = new GroupLiquidityProviderDeployer(redemptionOperator, getCirclesCore());
    }

    // External functions

    /// @notice Creates a new Core Members Group with associated handlers
    /// @dev Deploys three contracts: CMGMintHandler, CMGRedemptionHandler, and CoreMembersGroup
    ///      Uses create2 for deterministic addressing and verifies the predicted address matches
    /// @param _owner The owner address for the new group
    /// @param _service The service address for the new group
    /// @param _initialConditions Array of initial condition addresses
    /// @param _name Name of the token
    /// @param _symbol Symbol of the token
    /// @param _metadataDigest Hash of additional metadata
    /// @return coreMembersGroup Address of the deployed Core Members Group contract
    /// @return mintHandler Address of the deployed mint handler contract
    /// @return redemptionHandler Address of the deployed redemption handler contract
    function createCMGroup(
        address _owner,
        address _service,
        address[] memory _initialConditions,
        string memory _name,
        string memory _symbol,
        bytes32 _metadataDigest
    ) external returns (address, address, address) {
        // load Circles v2 core protocol addresses
        CirclesCore memory circlesCore = getCirclesCore();

        // create Core Members Group itself
        ICoreMembersGroup coreMembersGroup =
        (new CoreMembersGroup(_owner, _service, _initialConditions, _name, _symbol, _metadataDigest, circlesCore));

        address mintHandler = coreMembersGroup.mintHandler();
        address redemptionHandler = coreMembersGroup.redemptionHandler();

        // store deployment explicitly for easiest check by wallet
        deployedByFactory[address(coreMembersGroup)] = true;

        // ensure static ERC20 wrapper is deployed for group
        circlesCore.erc20Lift.ensureERC20(address(coreMembersGroup), CirclesType.Inflation);

        emit CMGroupCreated(address(coreMembersGroup), _owner, mintHandler, redemptionHandler);

        return (address(coreMembersGroup), mintHandler, redemptionHandler);
    }
}
