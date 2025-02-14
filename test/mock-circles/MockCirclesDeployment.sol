// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "openzeppelin-contracts/contracts/token/ERC1155/ERC1155.sol";
import "src/circles/Core.sol";
import "src/circles/IHub.sol";
import "src/circles/INameRegistry.sol";
import "src/circles/IStandardTreasury.sol";
import "test/mock-circles/MockHub.sol";
import "test/mock-circles/MockStandardTreasury.sol";
import "test/mock-circles/MockVault.sol";

contract MockCirclesDeployment is CirclesCoreAddresses {
    // State

    MockHub public mockHub;
    MockStandardTreasury public mockStandardTreasury;

    // Constructor

    constructor() {
        mockHub = new MockHub();
        mockStandardTreasury = mockHub.standardTreasury();
    }

    function getCirclesCore() public view returns (CirclesCore memory) {
        return CirclesCore(
            IHub(address(mockHub)),
            IStandardTreasury(address(mockHub.standardTreasury())),
            INameRegistryExtended(address(0))
        );
    }
}
