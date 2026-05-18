// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IHub} from "src/score-group/interfaces/IHub.sol";

/// @title SinkGroupWrapperInflationary

contract SinkGroupWrapperInflationary {
    // =================================================
    //                       ERRORS
    // =================================================

    /// @notice Thrown when a function is called by an account other than the Hub.
    error OnlyHub();

    /// @notice Thrown when a function is called by an account other than the Group.
    error OnlyGroup();

    error InvalidSource();

    /// @notice Thrown when a zero amount is received where a non-zero amount is expected.
    error ReceivedZeroAmount();

    // =================================================
    //                    EVENTS
    // =================================================

    event GroupWrapped(address indexed group, uint256 indexed amount, address indexed beneficiary);

    // =================================================
    //                     CONSTANTS
    // =================================================

    /// @notice Circles v2 Hub.
    IHub public constant HUB = IHub(address(0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8));

    // =================================================
    //                    MODIFIERS
    // =================================================

    /// @notice Ensures the function is only called by the Hub.
    /// @dev Reverts if `msg.sender` is not the Hub contract.
    modifier onlyHub() {
        if (msg.sender != address(HUB)) {
            revert OnlyHub();
        }
        _;
    }

    // =================================================
    //                    CONSTRUCTOR
    // =================================================

    constructor() {
        HUB.registerOrganization("group-inflationary-wrapper", bytes32(0));
    }

    // =================================================
    //                EXTERNAL FUNCTIONS
    // =================================================

    function trust(address _group) external {
        if (!HUB.isGroup(_group)) revert OnlyGroup();
        HUB.trust(_group, type(uint96).max);
    }

    // =================================================
    //         ERC1155 RECEIVER FUNCTION
    // =================================================

    function onERC1155Received(address, address _from, uint256 _id, uint256 _value, bytes memory)
        external
        onlyHub
        returns (bytes4)
    {
        if (_from == address(0)) revert InvalidSource();
        if (_value == 0) revert ReceivedZeroAmount();
        address group = address(uint160(_id));
        if (!HUB.isGroup(group)) revert OnlyGroup();

        address erc20Inflationary = HUB.wrap(group, _value, uint8(1));
        uint256 balanceInflationary = IERC20(erc20Inflationary).balanceOf(address(this));
        IERC20(erc20Inflationary).transfer(_from, balanceInflationary);

        emit GroupWrapped(group, _value, _from);

        return this.onERC1155Received.selector;
    }
}
