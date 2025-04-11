// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

interface ILiftERC20 {
    function ensureERC20(address _avatar, uint8 _circlesType) external returns (address);
}
