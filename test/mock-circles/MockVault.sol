// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "openzeppelin-contracts/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "test/mock-circles/MockHub.sol";
import "test/mock-circles/MockStandardTreasury.sol";

contract MockVault is ERC1155Holder {
    // State

    /// @notice hub
    MockHub public hub;
    /// @notice standard treasury
    MockStandardTreasury public standardTreasury;

    // Modifiers

    // @notice only treasury can call
    modifier onlyTreasury() {
        require(msg.sender == address(standardTreasury), "only standard treasury can call");
        _;
    }

    // Constructor

    constructor() {
        standardTreasury = MockStandardTreasury(msg.sender);
    }

    // Public functions

    function returnCollateral(
        address _receiver,
        uint256[] calldata _ids,
        uint256[] calldata _values,
        bytes calldata _data
    ) external onlyTreasury {
        // return the collateral to the receiver
        hub.safeBatchTransferFrom(address(this), _receiver, _ids, _values, _data);
    }
}
