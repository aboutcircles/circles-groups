// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

interface IOffchainScoreBasedMintPolicy {
    error AmountExceedsCollateralLimit();
    error AmountExceedsScoreLimit();
    error CollateralLimitReached();
    error GroupAlreadyInitialized();
    error InvalidCollateralForPersonalIssuanceMint();
    error InvalidScore();
    error NoIssuance();
    error NoSnapshot();
    error NotAtomicMint();
    error NotGroupMintPolicy();
    error NotMerkleTreeManager();
    error OnlyHub();
    error ZeroAddress();

    event GroupInitialized(address indexed group, address indexed merkleTreeManager, address pathMintRouter);
    event HistoricalSupply(address indexed group, uint256 indexed collateral, uint256 supply, uint256 day);
    event MerkleRootUpdated(
        address indexed group, bytes32 newMerkleRoot, bytes32 previousRoot, uint256 updateBlockNumber
    );
    event PersonalMinted(
        address indexed group,
        uint256 indexed collateral,
        uint256 amount,
        uint256 score,
        uint256 mintedAmountOnToday,
        uint256 day
    );
    event RouterMinted(
        address indexed group, uint256 indexed collateral, uint256 amount, uint256 currentAvailableLimit
    );

    function HUB() external view returns (address);
    function MAX_SCORE() external view returns (uint256);
    function beforeBurnPolicy(address, address, uint256, bytes memory) external view returns (bool);
    function beforeMintPolicy(
        address minter,
        address group,
        uint256[] memory collateral,
        uint256[] memory amounts,
        bytes memory data
    ) external returns (bool);
    function consumeScore(bytes32 slot) external returns (uint256 score);
    function getHistoricalSupplyOnToday(address group, uint256 collateral)
        external
        view
        returns (uint256 historicalSupplyOnToday);
    function getMintedAmountOnToday(address group, uint256 collateral)
        external
        view
        returns (uint256 mintedAmountOnToday);
    function initializeGroup(address merkleTreeManager, address pathMintRouter) external;
    function merkleRoots(address group)
        external
        view
        returns (bytes32 currentRoot, bytes32 previousRoot, uint256 updateBlockNumber);
    function merkleTreeManagers(address group) external view returns (address merkleRootManager);
    function pathMintRouters(address group) external view returns (address pathMintRouter);
    function snapshotIssuance() external;
    function updateMerkleRoot(address group, bytes32 newMerkleRoot) external;
}
