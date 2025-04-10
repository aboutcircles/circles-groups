// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IHub} from "src/base-group/interfaces/IHub.sol";

/**
 * @title BaseTreasury
 * @notice A contract that holds and manages ERC1155 tokens for a specific group within the Circles Hub ecosystem.
 * @dev Extends the ERC1155Holder contract to allow receiving ERC1155 tokens.
 */
contract BaseTreasury is ERC1155Holder {
    // =================================================
    //                       ERRORS
    // =================================================

    /**
     * @notice Thrown when a function is called by an account other than the Hub.
     */
    error OnlyHub();

    /**
     * @notice Thrown when an ERC1155 collateral token received is not trusted by the group.
     */
    error CollateralIsNotTrustedByGroup();

    // =================================================
    //                     CONSTANTS
    // =================================================

    /**
     * @notice The Hub contract that manages trust relationships and other Circles operations.
     */
    IHub public immutable HUB;

    /**
     * @notice The address of the group (or organization) for which this treasury is created.
     */
    address public immutable GROUP;

    // =================================================
    //                    MODIFIERS
    // =================================================

    /**
     * @notice Ensures the function is only called by the Hub.
     * @dev Reverts if `msg.sender` is not the Hub contract.
     */
    modifier onlyHub() {
        if (msg.sender != address(HUB)) {
            revert OnlyHub();
        }
        _;
    }

    // =================================================
    //                    CONSTRUCTOR
    // =================================================

    /**
     * @notice Deploys a new BaseTreasury contract and registers it as an organization within the Hub.
     * @dev Concatenates `_groupName` with "-treasury" for organizational registration.
     *      Grants unlimited trust to the group within the Hub.
     * @param _hub The address of the Hub contract.
     * @param _group The address of the group for this treasury.
     * @param _groupName The human-readable name of the group.
     */
    constructor(address _hub, address _group, string memory _groupName) {
        HUB = IHub(_hub);
        GROUP = _group;

        string memory treasuryName = string.concat(_groupName, "-treasury");
        HUB.registerOrganization(treasuryName, bytes32(0));
        HUB.trust(_group, type(uint96).max);
    }

    // =================================================
    //                EXTERNAL FUNCTIONS
    // =================================================

    /**
     * @notice Burns all ERC1155 tokens corresponding to the group’s CRC balance held by this treasury.
     * @dev The token ID for the group is derived from the `GROUP` address.
     */
    function burn() external {
        uint256 id = uint256(uint160(GROUP));
        if (id != 0) {
            uint256 amount = HUB.balanceOf(address(this), id);
            HUB.burn(id, amount, "");
        }
    }

    // =================================================
    //         ERC1155 RECEIVER OVERRIDDEN FUNCTIONS
    // =================================================

    /**
     * @notice Handles the receipt of a single ERC1155 token type.
     * @dev Only the Hub contract can call this function.
     *      Checks if the received ERC1155 token is trusted by the group.
     * @param _id The ID of the token being transferred.
     * @return A bytes4 constant (this function’s selector), indicating success.
     */
    function onERC1155Received(address, address, uint256 _id, uint256, bytes memory)
        public
        override
        onlyHub
        returns (bytes4)
    {
        uint256[] memory _ids = new uint256[](1);
        _ids[0] = _id;
        _checkGroupTrusts(_ids);
        return this.onERC1155Received.selector;
    }

    /**
     * @notice Handles the receipt of multiple ERC1155 token types in a single batch transfer.
     * @dev Only the Hub contract can call this function.
     *      Checks if each of the received token IDs is trusted by the group.
     * @param _ids An array containing IDs of each token being transferred.
     * @return A bytes4 constant (this function’s selector), indicating success.
     */
    function onERC1155BatchReceived(address, address, uint256[] memory _ids, uint256[] memory, bytes memory)
        public
        override
        onlyHub
        returns (bytes4)
    {
        _checkGroupTrusts(_ids);
        return this.onERC1155BatchReceived.selector;
    }

    // =================================================
    //                 INTERNAL FUNCTIONS
    // =================================================

    /**
     * @notice Verifies that all token IDs in `_ids` are trusted by the group.
     * @dev Reverts with `CollateralIsNotTrustedByGroup()` if any token ID is not trusted.
     * @param _ids An array of ERC1155 token IDs to be checked.
     */
    function _checkGroupTrusts(uint256[] memory _ids) internal {
        for (uint256 i; i < _ids.length;) {
            if (!HUB.isTrusted(GROUP, address(uint160(_ids[i])))) {
                revert CollateralIsNotTrustedByGroup();
            }
            unchecked {
                ++i;
            }
        }
    }
}
