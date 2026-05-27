// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

interface IScoreTreasury {
    error AtomicMintRequired();
    error CollateralIsNotTrustedByGroup();
    error OnlyGroup();
    error OnlyHub();
    error OnlyMintRouter();

    function GROUP() external view returns (address);
    function HIGH_SCORE_SUB_TREASURY() external view returns (address);
    function HIGH_SCORE_THRESHOLD() external view returns (uint256);
    function HUB() external view returns (address);
    function LOW_SCORE_SUB_TREASURY() external view returns (address);
    function MINT_POLICY() external view returns (address);
    function MINT_ROUTER() external view returns (address);
    function balanceOfCollateral(uint256 collateralId) external view returns (uint256 balance);
    function onERC1155Received(address, address from, uint256 _id, uint256 _value, bytes memory)
        external
        returns (bytes4);
    function updateMetadataDigest(address nameRegistry, bytes32 _metadataDigest) external;
}
