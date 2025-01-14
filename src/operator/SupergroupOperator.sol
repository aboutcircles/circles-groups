// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "circles-contracts-v2/groups/Definitions.sol";
import "src/circles/IHub.sol";
import "src/errors/Errors.sol";

contract SupergroupOperator is ISupergroupErrors {
    // State variables

    /// @notice Supergroup is the explicit group this operator is deployed for.
    address public immutable supergroup;
    /// @notice hub address
    IHub public immutable hub;
    /// @notice feeCollection address where the supergroup collects mint fees
    address public immutable feeCollection;
    /// @notice group treasury where collateral is stored
    address public immutable collateralTreasury;

    // Modifiers

    /// @notice Only the Circles Hub can call this function
    modifier onlyHub() {
        if (msg.sender != address(hub)) {
            revert SupergroupOnlyHub();
        }
        _;
    }

    // Constructor

    constructor(IHub _hub, address _feeCollection) {
        supergroup = msg.sender;
        hub = _hub;
        feeCollection = _feeCollection;
        // supergroup must have registered in hub before constructing this operator
        collateralTreasury = hub.treasuries(supergroup);
        // calling hub.isGroup is a redundant check, but check it nonetheless for readability
        if (collateralTreasury == address(0) || !hub.isGroup(supergroup)) {
            revert SupergroupMustBeRegistered();
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
    function redeem(
        address group,
        uint256[] calldata redemptionIds,
        uint256[] calldata redemptionValues
    ) external {
        // sanity check as the operator for groups might get mixed up
        // once many groups and their operators are authorized.
        if (group != supergroup) {
            revert
        }
        if (redemptionIds.
            redemptionIds.length != redemptionValues.length)

        bytes memory userData = abi.encode(BaseMintPolicyDefinitions.BaseRedemptionPolicy(redemptionIds, redemptionValues));
    }

    /// @notice Following the behaviour of
    function onERC1155Received(
        address _operator,
        address _from,
        uint256 _id,
        uint256 _value,
        bytes calldata _data
    ) public onlyHub returns (bytes4) {}

    function onERC1155BatchReceived(
        address _operator,
        address _from,
        uint256 _id,
        uint256 _value,
        bytes calldata _data
    ) public override onlyHub returns (bytes4) {}
}
