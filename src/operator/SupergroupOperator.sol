// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "src/circles/Core.sol";
import "src/circles/Types.sol";
import "src/errors/Errors.sol";
import "src/operator/OperatorRequest.sol";

contract SupergroupOperator is OperatorRequest, CirclesCoreAddresses, CirclesTypes, ISupergroupErrors {
    // State variables

    /// @notice Supergroup is the explicit group this operator is deployed for.
    address public immutable supergroup;

    // Modifiers

    /// @notice Only the Circles Hub can call this function
    modifier onlyHub() {
        if (msg.sender != address(hub)) {
            revert SupergroupOnlyHub();
        }
        _;
    }

    // Constructor

    constructor(address _supergroup) {
        if (_supergroup == address(0)) {
            // supergroup address must not be zero
            revert SupergroupInvalidCallingParameters();
        }
        supergroup = _supergroup;
        // supergroup must have registered in hub before constructing this operator
        address collateralTreasury = hub.treasuries(supergroup);
        // calling hub.isGroup is a redundant check, but check it nonetheless for readability
        if (collateralTreasury == address(0) || !hub.isGroup(supergroup)) {
            revert SupergroupMustBeRegistered();
        }
        // We want to encourage people to only use the standard treasury, so enforce explicitly.
        if (collateralTreasury != standardTreasury) {
            revert SupergroupMustUseStandardTreasury();
        }
    }

    // External functions

    /// @notice Explicit group mint
    function groupMint() external {}

    /// @notice OperateFlowMatrix
    function operateFlowMatrix() external {}

    /// @notice Redeem is a helper function to construct the data for redeeming
    ///         the collateral from the supergroup. The caller must have authorized
    ///         this operator.
    function redeem(address group, uint256[] calldata redemptionIds, uint256[] calldata redemptionValues) external {
        // sanity check as the operator for groups might get mixed up
        // once many groups and their operators are authorized.
        if (group != supergroup) {
            revert SupergroupInvalidCallingParameters();
        }
        if (redemptionIds.length != redemptionValues.length) {
            revert SupergroupInvalidCallingParameters();
        }

        bytes memory userData = abi.encode(BaseRedemptionPolicy(redemptionIds, redemptionValues));
        bytes memory data = abi.encode(Metadata(METADATATYPE_GROUPREDEEM, "", userData));
    }

    /// @notice Following the behaviour of
    function onERC1155Received(address _operator, address _from, uint256 _id, uint256 _value, bytes calldata _data)
        public
        onlyHub
        returns (bytes4)
    {}

    // function onERC1155BatchReceived(address _operator, address _from, uint256 _id, uint256 _value, bytes calldata _data)
    //     public
    //     override
    //     onlyHub
    //     returns (bytes4)
    // {}
}
