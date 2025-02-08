// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "openzeppelin-contracts/contracts/token/ERC1155/ERC1155.sol";
import "test/mockCircles/MockHub.sol";
import "test/mockCircles/MockStandardTreasury.sol";
import "test/mockCircles/MockVault.sol";

contract MockCirclesDeployment {
    // State
    address public mockHub;
    address public mockStandardTreasury;
    address public mockVault;

    // Constructor
    constructor() {
        mockHub = address(new MockHub());
        mockStandardTreasury = address(new MockStandardTreasury());
        mockVault = address(new MockVault());
    }
}
