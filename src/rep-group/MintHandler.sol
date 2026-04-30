// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

contract MintHandler {
    enum Mode {
        SCORE,
        HISTORICAL_VIA_HANDLER
    }

    address public POLICY;
    address public SCORE;
    address public HUB;
    address public GROUP;

    function snapshotIssuance() external {}

    function finalizeScoreMint(bytes calldata proof, uint256 score, uint256 amount) external {}

    function historicalMint(address collateralAvatar, uint256 amount) external {}

    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external
        returns (bytes4)
    {}

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external returns (bytes4) {}
}
