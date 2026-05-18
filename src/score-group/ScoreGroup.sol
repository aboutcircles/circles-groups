// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import {IHub} from "src/score-group/interfaces/IHub.sol";
import {ILiftERC20} from "src/score-group/interfaces/ILiftERC20.sol";
import {INameRegistry} from "src/score-group/interfaces/INameRegistry.sol";
import {IOffchainScoreBasedMintPolicy} from "src/score-group/interfaces/IOffchainScoreBasedMintPolicy.sol";
import {ScoreGroupMintRouter} from "src/score-group/ScoreGroupMintRouter.sol";
import {ScoreTreasury} from "src/score-group/ScoreTreasury.sol";

/// @title ScoreGroup
contract ScoreGroup {
    // =================================================
    //                       ERRORS
    // =================================================

    error OnlyHuman();

    error OnlyMetadataManager();

    /// @notice Thrown when calling parameters are invalid (e.g., zero addresses).
    error InvalidCallingParameters();

    error OptedOut();

    // =================================================
    //                    EVENTS
    // =================================================

    event ScoreGroupInitialized(
        address indexed metadataManager,
        address indexed mintRouter,
        address indexed treasury,
        address stableERC20,
        address demurrageERC20
    );

    event OptOutStatusChanged(address indexed member, bool optedOut);

    // =================================================
    //                     CONSTANTS
    // =================================================

    /// @notice Circles v2 Hub.
    IHub public constant HUB = IHub(address(0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8));

    /// @notice Circles v2 LiftERC20 contract.
    ILiftERC20 public constant LIFT_ERC20 = ILiftERC20(address(0x5F99a795dD2743C36D63511f0D4bc667e6d3cDB5));

    /// @notice Circles v2 Name Registry contract.
    INameRegistry public constant NAME_REGISTRY = INameRegistry(address(0xA27566fD89162cC3D40Cb59c87AAaA49B85F3474));

    /// @notice Address of the score mint policy that applies to newly created groups.
    address public constant SCORE_MINT_POLICY = address(0x83e4C27Dcf0068678C603c392513E05F844b5666);

    /// @notice The group's treasury contract, deployed during initialization.
    /// @dev Immutable once set in the constructor.
    ScoreTreasury public immutable SCORE_TREASURY;

    ScoreGroupMintRouter public immutable MINT_ROUTER;

    address public immutable STABLE_ERC20;
    address public immutable DEMURRAGE_ERC20;

    address public immutable METADATA_MANAGER;

    // =================================================
    //                    STATE
    // =================================================
    mapping(address => bool) public optOuts;


    // =================================================
    //                  CONSTRUCTOR
    // =================================================

    constructor(
        address _metadataManager,
        address _mintRouterAdmin,
        address _merkleTreeManager,
        string memory _name,
        string memory _symbol,
        bytes32 _metadataDigest
    ) {
        if (_metadataManager == address(0) || _mintRouterAdmin == address(0) || _merkleTreeManager == address(0)) {
            revert InvalidCallingParameters();
        }

        METADATA_MANAGER = _metadataManager;

        MINT_ROUTER = new ScoreGroupMintRouter(_mintRouterAdmin, address(this), _name);

        // Deploy the treasury for this group.
        SCORE_TREASURY = new ScoreTreasury(
            address(HUB), address(this), SCORE_MINT_POLICY, address(MINT_ROUTER), _name, _metadataDigest
        );

        // Register the group in the Hub with the base mint policy and the newly deployed treasury.
        HUB.registerCustomGroup(SCORE_MINT_POLICY, address(SCORE_TREASURY), _name, _symbol, _metadataDigest);

        IOffchainScoreBasedMintPolicy(SCORE_MINT_POLICY).initializeGroup(_merkleTreeManager, address(MINT_ROUTER));

        // Registers a short name for this group in the Name Registry without a nonce, limited by 250_000 gas.
        try NAME_REGISTRY.registerShortName{gas: 250_000}() {} catch {}

        // Deploy ERC20s for the group via the LIFT_ERC20 contract.
        DEMURRAGE_ERC20 = LIFT_ERC20.ensureERC20(address(this), uint8(0));
        STABLE_ERC20 = LIFT_ERC20.ensureERC20(address(this), uint8(1));

        emit ScoreGroupInitialized(
            _metadataManager, address(MINT_ROUTER), address(SCORE_TREASURY), STABLE_ERC20, DEMURRAGE_ERC20
        );
    }

    // =================================================
    //               EXTERNAL FUNCTIONS
    // =================================================

    function trust(address _trustReceiver) public {
        _onlyHuman(_trustReceiver);
        _optOutCheck(_trustReceiver);
        _trust(_trustReceiver, type(uint96).max);
    }

    function trustBatch(address[] memory _members) external {
        for (uint256 i; i < _members.length;) {
            trust(_members[i]);
            unchecked {
                ++i;
            }
        }
    }

    function optOut() external {
        _onlyHuman(msg.sender);
        if (HUB.isTrusted(address(this), msg.sender)) _trust(msg.sender, 0);
        optOuts[msg.sender] = true;
        emit OptOutStatusChanged(msg.sender, true);
    }

    function updateMetadataDigest(bytes32 _metadataDigest) external {
        if (msg.sender != METADATA_MANAGER) revert OnlyMetadataManager();
        NAME_REGISTRY.updateMetadataDigest(_metadataDigest);
        SCORE_TREASURY.updateMetadataDigest(address(NAME_REGISTRY), _metadataDigest);
    }

    // =================================================
    //               INTERNAL FUNCTIONS
    // =================================================

    function _trust(address _trustReceiver, uint96 _expiry) internal {
        HUB.trust(_trustReceiver, _expiry);
    }

    function _onlyHuman(address avatar) internal view {
        if (!HUB.isHuman(avatar)) revert OnlyHuman();
        assembly {
            let pointer := mload(0x40)
            mstore(0x40, add(pointer, 0x44))
            mstore(pointer, 0x44)
            mstore(pointer, 0x5624b25b553c9d7e83c58cdf3a427b0c81460372fe0d5da8900473788d506425)
            mstore(add(pointer, 0x20), 0xc7ffdc5c00000000000000000000000000000000000000000000000000000000)
            mstore(add(pointer, 0x40), 0x0000000100000000000000000000000000000000000000000000000000000000)
            if or(
                iszero(
                    eq(
                        keccak256(add(pointer, 0x44), 0x60),
                        0xbc542b7979ff2bed60ccd2c45b7437d0c0580d139eefafaffc4eec6c7686af06
                    )
                ),
                iszero(staticcall(gas(), avatar, pointer, 0x44, add(pointer, 0x44), 0x60))
            ) {
                mstore(0, 0x9aa42e7200000000000000000000000000000000000000000000000000000000)
                revert(0, 0x04)
            }
        }
    }

    function _optOutCheck(address _trustReceiver) internal {
        if (optOuts[_trustReceiver] && _trustReceiver != msg.sender) revert OptedOut();
        if (_trustReceiver == msg.sender) {
            optOuts[_trustReceiver] = false;
            emit OptOutStatusChanged(msg.sender, false);
        }
    }
}
