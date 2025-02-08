// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "openzeppelin-contracts/contracts/token/ERC1155/ERC1155.sol";
import "circles-contracts-v2/groups/IMintPolicy.sol";

contract MockHub is ERC1155 {
    // Constructor
    constructor() ERC1155("") {}
}
