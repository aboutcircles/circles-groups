// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import {BaseMintPolicy} from "../base-group/BaseMintPolicy.sol";
import {IHub} from "src/circles/IHub.sol";

contract MintPolicy is BaseMintPolicy {
    enum Mode {
        SCORE,
        HISTORICAL_VIA_HANDLER
    }

    struct InflationaryBudget {
        uint192 remaining;
        bool initialized;
    }

    error MintHandlerAlreadySet();
    error AlreadySealed();
    error NotSealed();
    error AlreadyInitialized();
    error UninitializedBucket();
    error BudgetExceeded();
    error InvalidMode();
    error NotHumanCollateral();

    event MintHandlerSet(address indexed handler);
    event Sealed();
    event Initialized(address indexed avatar, uint192 remaining);
    event Consumed(address indexed avatar, uint192 amount, uint192 remaining);

    address public MINT_HANDLER;
    address public immutable SCORE;
    IHub public immutable HUB;
    address public immutable GROUP;
    bool public sealed_;

    mapping(address => InflationaryBudget) public historical;

    constructor(address _score, address _hub, address _group) {
        SCORE = _score;
        HUB = IHub(_hub);
        GROUP = _group;
    }

    function setMintHandler(address h) external {
        if (MINT_HANDLER != address(0)) revert MintHandlerAlreadySet();
        MINT_HANDLER = h;
        emit MintHandlerSet(h);
    }

    function initBatch(address[] calldata avatars) external {
        if (sealed_) revert AlreadySealed();
        for (uint256 i; i < avatars.length;) {
            address c = avatars[i];
            if (historical[c].initialized) revert AlreadyInitialized();
            uint256 supply = HUB.totalSupply(uint256(uint160(c)));
            historical[c] = InflationaryBudget({remaining: uint192(supply), initialized: true});
            emit Initialized(c, uint192(supply));
            unchecked {
                ++i;
            }
        }
    }

    function sealInit() external {
        if (sealed_) revert AlreadySealed();
        if (MINT_HANDLER == address(0)) revert MintHandlerAlreadySet();
        sealed_ = true;
        emit Sealed();
    }

    function beforeMintPolicy(
        address _minter,
        address, /*_group*/
        uint256[] calldata _collateral,
        uint256[] calldata _amounts,
        bytes calldata _data
    ) external override returns (bool) {
        if (_minter == MINT_HANDLER) {
            Mode m = abi.decode(_data, (Mode));
            if (m == Mode.SCORE) {
                return true;
            } else if (m == Mode.HISTORICAL_VIA_HANDLER) {
                _consumeHistorical(_collateral, _amounts);
                return true;
            } else {
                revert InvalidMode();
            }
        }

        _consumeHistorical(_collateral, _amounts);
        return true;
    }

    function beforeBurnPolicy(address, address, uint256, bytes calldata)
        external
        pure
        override
        returns (bool)
    {
        return true;
    }

    function beforeRedeemPolicy(
        address, /*_operator*/
        address, /*_redeemer*/
        address, /*_group*/
        uint256, /*_value*/
        bytes calldata /*_data*/
    )
        external
        pure
        returns (
            uint256[] memory ids,
            uint256[] memory values,
            uint256[] memory burnIds,
            uint256[] memory burnValues
        )
    {
        ids = new uint256[](0);
        values = new uint256[](0);
        burnIds = new uint256[](0);
        burnValues = new uint256[](0);
    }

    function _consumeHistorical(uint256[] calldata _collateral, uint256[] calldata _amounts) internal {
        for (uint256 i; i < _collateral.length;) {
            address c = address(uint160(_collateral[i]));
            InflationaryBudget storage b = historical[c];
            if (!b.initialized) revert UninitializedBucket();
            uint256 amt = _amounts[i];
            if (amt > b.remaining) revert BudgetExceeded();
            b.remaining -= uint192(amt);
            emit Consumed(c, uint192(amt), b.remaining);
            unchecked {
                ++i;
            }
        }
    }
}
