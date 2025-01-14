// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "circles-contracts-v2/hub/IHub.sol";

contract SupergroupOperator {
    // State variables

    /// @notice Supergroup is the explicit group this operator is deployed for.
    address public immutable supergroup;
    /// @notice hub address
    IHubV2 public immutable hub;
    /// @notice feeCollection address where the supergroup collects mint fees
    address public immutable feeCollection;
    /// @notice group treasury where collateral is stored
    address public immutable collateralTreasury;


    // Constructor

    constructor(IHubV2 _hub, address _treasury) {
        hub = _hub;
        treasury = _treasury;
    }

    // External functions

    /// @notice Explicit group mint
    function groupMint() external {}

    /// @notice OperateFlowMatrix
    function operateFlowMatrix() external {}

    /// @notice Following the behaviour
    function onERC1155Received(address _operator, address _from, uint256 _id, uint256 _value, bytes calldata _data)
        public
        onlyHub()
        returns (bytes4) {}

    function onERC1155BatchReceived(address _operator, address _from, uint256 _id, uint256 _value, bytes calldata _data)
        public
        override
        onlyHub())
        returns (bytes4) {}
}
