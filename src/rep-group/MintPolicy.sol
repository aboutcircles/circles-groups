// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import {BaseMintPolicy} from "../base-group/BaseMintPolicy.sol";

contract MintPolicy is BaseMintPolicy {
    enum Mode {
        SCORE,
        HISTORICAL_VIA_HANDLER
    }

    struct InflationaryBudget {
        uint192 remaining;
        bool initialized;
    }

    address public MINT_HANDLER;
    address public SCORE;
    address public HUB;
    address public GROUP;
    bool public sealed_;

    mapping(address => InflationaryBudget) public historical;

    function setMintHandler(address h) external {}

    function initBatch(address[] calldata avatars) external {}

    function sealInit() external {}

    function beforeMintPolicy(
        address, /*_minter*/
        address, /*_group*/
        uint256[] calldata, /*_collateral*/
        uint256[] calldata, /*_amounts*/
        bytes calldata /*_data*/
    ) external override returns (bool) {}

    function beforeBurnPolicy(
        address, /*_burner*/
        address, /*_group*/
        uint256, /*_amount*/
        bytes calldata /*_data*/
    ) external override returns (bool) {}

    function beforeRedeemPolicy(
        address, /*_operator*/
        address, /*_redeemer*/
        address, /*_group*/
        uint256, /*_value*/
        bytes calldata /*_data*/
    )
        external
        returns (
            uint256[] memory ids,
            uint256[] memory values,
            uint256[] memory burnIds,
            uint256[] memory burnValues
        )
    {}

    function _consumeHistorical(uint256[] calldata _collateral, uint256[] calldata _amounts) internal {}
}
