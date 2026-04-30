// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IHub} from "src/circles/IHub.sol";
import {Score} from "./Score.sol";

contract MintHandler is ERC1155Holder {
    enum Mode {
        SCORE,
        HISTORICAL_VIA_HANDLER
    }

    error NoIssuance();
    error NoSnapshot();
    error ExceedsScoreBudget();

    event Snapshotted(address indexed user, uint256 issuance);
    event ScoreMinted(address indexed user, uint256 score, uint256 amount);
    event HistoricalMinted(address indexed user, address indexed collateralAvatar, uint256 amount);

    address public immutable POLICY;
    Score public immutable SCORE;
    IHub public immutable HUB;
    address public immutable GROUP;

    constructor(address _policy, address _score, address _hub, address _group) {
        POLICY = _policy;
        SCORE = Score(_score);
        HUB = IHub(_hub);
        GROUP = _group;
    }

    function snapshotIssuance() external {
        (uint256 z,,) = HUB.calculateIssuance(msg.sender);
        if (z == 0) revert NoIssuance();
        bytes32 slot = keccak256(abi.encode("scorePathSnapshot", msg.sender));
        assembly {
            tstore(slot, z)
        }
        emit Snapshotted(msg.sender, z);
    }

    function finalizeScoreMint(bytes calldata proof, uint256 score, uint256 amount) external {
        bytes32 slot = keccak256(abi.encode("scorePathSnapshot", msg.sender));
        uint256 z;
        assembly {
            z := tload(slot)
        }
        if (z == 0) revert NoSnapshot();

        SCORE.verify(proof, msg.sender, score);

        if (amount > (score * z) / SCORE.SCALE()) revert ExceedsScoreBudget();

        uint256 collateralId = uint256(uint160(msg.sender));
        HUB.safeTransferFrom(msg.sender, address(this), collateralId, amount, "");

        address[] memory collaterals = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        collaterals[0] = msg.sender;
        amounts[0] = amount;
        HUB.groupMint(GROUP, collaterals, amounts, abi.encode(Mode.SCORE));

        HUB.safeTransferFrom(address(this), msg.sender, uint256(uint160(GROUP)), amount, "");

        assembly {
            tstore(slot, 0)
        }

        emit ScoreMinted(msg.sender, score, amount);
    }

    function historicalMint(address collateralAvatar, uint256 amount) external {
        uint256 collateralId = uint256(uint160(collateralAvatar));
        HUB.safeTransferFrom(msg.sender, address(this), collateralId, amount, "");

        address[] memory collaterals = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        collaterals[0] = collateralAvatar;
        amounts[0] = amount;
        HUB.groupMint(GROUP, collaterals, amounts, abi.encode(Mode.HISTORICAL_VIA_HANDLER));

        HUB.safeTransferFrom(address(this), msg.sender, uint256(uint160(GROUP)), amount, "");

        emit HistoricalMinted(msg.sender, collateralAvatar, amount);
    }
}
