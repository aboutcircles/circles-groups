// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IHub} from "src/base-group/interfaces/IHub.sol";
import {INameRegistry} from "src/base-group/interfaces/INameRegistry.sol";

/**
 * @title BaseTreasury
 * @notice A contract that holds and manages ERC1155 tokens for a specific group as collateral within the Circles Hub ecosystem.
 * @dev Extends the ERC1155Holder contract to allow receiving ERC1155 tokens. Treasury is registered as organization and trusts
 *      itself group in order to enable collateral redeem feature via transitive transfers.
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
     * @notice Thrown when a function is called by an account other than the Group.
     */
    error OnlyGroup();

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
     * @notice Circles v2 Name Registry contract.
     */
    INameRegistry public immutable NAME_REGISTRY;

    /**
     * @notice The address of the group for which this treasury is created.
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
     * @param _nameRegistry The address of the NameRegistry contract.
     * @param _group The address of the group for this treasury.
     * @param _groupName The human-readable name of the group.
     * @param _metadataDigest The IPFS or other off-chain data digest used for metadata references.
     */
    constructor(
        address _hub,
        address _nameRegistry,
        address _group,
        string memory _groupName,
        bytes32 _metadataDigest
    ) {
        HUB = IHub(_hub);
        NAME_REGISTRY = INameRegistry(_nameRegistry);
        GROUP = _group;

        string memory treasuryName = string.concat(_groupName, "-treasury");
        HUB.registerOrganization(treasuryName, _metadataDigest);
        HUB.trust(_group, type(uint96).max);
    }

    // =================================================
    //                EXTERNAL FUNCTIONS
    // =================================================

    /**
     * @notice Burns all ERC1155 Group id tokens balance held by this treasury.
     * @dev The token ID for the group is derived from the `GROUP` address.
     */
    function burn() public {
        uint256 id = uint256(uint160(GROUP));
        uint256 amount = HUB.balanceOf(address(this), id);
        if (amount > 0) HUB.burn(id, amount, "");
    }

    /**
     * @notice Updates the metadata digest for this organization in the Name Registry.
     * @param _metadataDigest The new off-chain metadata digest (e.g., IPFS hash).
     * @dev Only callable by the group.
     */
    function updateMetadataDigest(bytes32 _metadataDigest) external {
        if (msg.sender != GROUP) revert OnlyGroup();
        NAME_REGISTRY.updateMetadataDigest(_metadataDigest);
    }

    // =================================================
    //         ERC1155 RECEIVER OVERRIDDEN FUNCTIONS
    // =================================================

    /**
     * @notice Handles the receipt of a single ERC1155 token id.
     * @dev Only the Hub contract can call this function.
     *      Checks if the received ERC1155 token is trusted by the group.
     *      Burns group id balance, if present.
     * @param _id The ID of the token being transferred.
     * @return A bytes4 constant (this function’s selector), indicating success.
     */
    function onERC1155Received(address, address, uint256 _id, uint256, bytes memory)
        public
        virtual
        override
        onlyHub
        returns (bytes4)
    {
        uint256[] memory _ids = new uint256[](1);
        _ids[0] = _id;
        _verifyGroupTrusts(_ids);
        burn();
        return this.onERC1155Received.selector;
    }

    /**
     * @notice Handles the receipt of multiple ERC1155 token ids in a single batch transfer.
     * @dev Only the Hub contract can call this function.
     *      Checks if each of the received token IDs is trusted by the group.
     *      Burns group id balance, if present.
     * @param _ids An array containing IDs of each token being transferred.
     * @return A bytes4 constant (this function’s selector), indicating success.
     */
    function onERC1155BatchReceived(address, address, uint256[] memory _ids, uint256[] memory, bytes memory)
        public
        virtual
        override
        onlyHub
        returns (bytes4)
    {
        _verifyGroupTrusts(_ids);
        burn();
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
    function _verifyGroupTrusts(uint256[] memory _ids) internal {
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
