// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IHub} from "src/score-group/interfaces/IHub.sol";
import {INameRegistry} from "src/score-group/interfaces/INameRegistry.sol";
import {IOffchainScoreBasedMintPolicy} from "src/score-group/interfaces/IOffchainScoreBasedMintPolicy.sol";

/**
 * @title ScoreTreasury
 */
contract ScoreTreasury is ERC1155Holder {
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

    error OnlyMintRouter();

    error AtomicMintRequired();

    /**
     * @notice Thrown when an ERC1155 collateral token received is not trusted by the group.
     */
    error CollateralIsNotTrustedByGroup();

    // =================================================
    //                     CONSTANTS
    // =================================================

    uint256 public constant HIGH_SCORE_THRESHOLD = 50;

    /**
     * @notice The Hub contract that manages trust relationships and other Circles operations.
     */
    IHub public immutable HUB;

    /**
     * @notice The address of the group for which this treasury is created.
     */
    address public immutable GROUP;
    IOffchainScoreBasedMintPolicy public immutable MINT_POLICY;
    address public immutable MINT_ROUTER;

    address public immutable LOW_SCORE_SUB_TREASURY;
    address public immutable HIGH_SCORE_SUB_TREASURY;

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

    constructor(
        address _hub,
        address _group,
        address _mintPolicy,
        address _mintRouter,
        string memory _groupName,
        bytes32 _metadataDigest
    ) {
        HUB = IHub(_hub);
        GROUP = _group;
        MINT_POLICY = IOffchainScoreBasedMintPolicy(_mintPolicy);
        MINT_ROUTER = _mintRouter;
        LOW_SCORE_SUB_TREASURY = address(new ScoreSubTreasury(_hub, _group, _groupName, _metadataDigest));
        HIGH_SCORE_SUB_TREASURY = address(new ScoreSubTreasury(_hub, _group, _groupName, _metadataDigest));
    }

    // =================================================
    //                EXTERNAL FUNCTIONS
    // =================================================

    /**
     * @notice Updates the metadata digest for this organization in the Name Registry.
     * @param _metadataDigest The new off-chain metadata digest (e.g., IPFS hash).
     * @dev Only callable by the group.
     */
    function updateMetadataDigest(address nameRegistry, bytes32 _metadataDigest) external {
        if (msg.sender != GROUP) revert OnlyGroup();
        ScoreSubTreasury(LOW_SCORE_SUB_TREASURY).updateMetadataDigest(nameRegistry, _metadataDigest);
        ScoreSubTreasury(HIGH_SCORE_SUB_TREASURY).updateMetadataDigest(nameRegistry, _metadataDigest);
    }

    function balanceOfCollateral(uint256 collateralId) external view returns (uint256 balance) {
        balance = HUB.balanceOf(LOW_SCORE_SUB_TREASURY, collateralId);
        balance += HUB.balanceOf(HIGH_SCORE_SUB_TREASURY, collateralId);
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
    function onERC1155Received(address, address from, uint256 _id, uint256 _value, bytes memory)
        public
        virtual
        override
        onlyHub
        returns (bytes4)
    {
        uint256[] memory _ids = new uint256[](1);
        _ids[0] = _id;
        _verifyGroupTrusts(_ids);

        address subTreasury;
        if (from == MINT_ROUTER) {
            subTreasury = HIGH_SCORE_SUB_TREASURY;
        } else {
            // ask policy
            uint256 score = MINT_POLICY.consumeScore(keccak256(abi.encode(from, block.timestamp)));
            if (score == 0) revert AtomicMintRequired();
            subTreasury = score < HIGH_SCORE_THRESHOLD ? LOW_SCORE_SUB_TREASURY : HIGH_SCORE_SUB_TREASURY;
        }

        HUB.safeTransferFrom(address(this), subTreasury, _id, _value, "");

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
    function onERC1155BatchReceived(
        address,
        address from,
        uint256[] memory _ids,
        uint256[] memory _values,
        bytes memory
    ) public virtual override onlyHub returns (bytes4) {
        // limit to router
        if (from != MINT_ROUTER) revert OnlyMintRouter();
        _verifyGroupTrusts(_ids);
        // transfer to high
        HUB.safeBatchTransferFrom(address(this), HIGH_SCORE_SUB_TREASURY, _ids, _values, "");
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

contract ScoreSubTreasury is ERC1155Holder {
    // =================================================
    //                       ERRORS
    // =================================================

    /**
     * @notice Thrown when a function is called by an account other than the Hub.
     */
    error OnlyHub();

    error OnlyTreasury();

    // =================================================
    //                     CONSTANTS
    // =================================================

    /**
     * @notice The Hub contract that manages trust relationships and other Circles operations.
     */
    IHub public immutable HUB;

    address public immutable TREASURY;

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

    modifier onlyTreasury(address from) {
        if (from != TREASURY) {
            revert OnlyTreasury();
        }
        _;
    }

    // =================================================
    //                    CONSTRUCTOR
    // =================================================

    constructor(address _hub, address _group, string memory _groupName, bytes32 _metadataDigest) {
        HUB = IHub(_hub);
        GROUP = _group;
        TREASURY = msg.sender;

        string memory treasuryName = string.concat(_groupName, "-sub-treasury");
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
    function updateMetadataDigest(address nameRegistry, bytes32 _metadataDigest) external onlyTreasury(msg.sender) {
        INameRegistry(nameRegistry).updateMetadataDigest(_metadataDigest);
    }

    // =================================================
    //         ERC1155 RECEIVER OVERRIDDEN FUNCTIONS
    // =================================================

    function onERC1155Received(address, address from, uint256, uint256, bytes memory)
        public
        virtual
        override
        onlyHub
        onlyTreasury(from)
        returns (bytes4)
    {
        burn();
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address from, uint256[] memory, uint256[] memory, bytes memory)
        public
        virtual
        override
        onlyHub
        onlyTreasury(from)
        returns (bytes4)
    {
        burn();
        return this.onERC1155BatchReceived.selector;
    }
}
