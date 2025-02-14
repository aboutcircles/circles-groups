// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "openzeppelin-contracts/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "test/mock-circles/MockHub.sol";
import "test/mock-circles/MockVault.sol";

contract MockStandardTreasury is ERC1155Holder {
    // State

    /// @notice hub
    MockHub public hub;

    /// @notice vaults for groups
    mapping(address => MockVault) public vaults;

    // Constructor
    constructor() {
        hub = MockHub(msg.sender);
    }

    function ensureVault(address _group) public returns (address) {
        require(hub.isGroup(_group), "not a group");
        if (address(vaults[_group]) == address(0)) {
            vaults[_group] = new MockVault();
        }
        return address(vaults[_group]);
    }
}
