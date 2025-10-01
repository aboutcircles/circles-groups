// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {IHub} from "src/base-group/interfaces/IHub.sol";
import {IBaseGroupFactory} from "src/base-group/interfaces/IBaseGroupFactory.sol";

// no callbacks, should not hold CRC

contract BaseGroupMintRouter {
    error Frozen();
    error OnlyAdmin();
    error OnlyHuman();
    error OnlyBaseGroup();

    IHub internal constant HUB = IHub(address(0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8));
    IBaseGroupFactory internal constant BASE_GROUP_FACTORY =
        IBaseGroupFactory(address(0xD0B5Bd9962197BEaC4cbA24244ec3587f19Bd06d));
    address internal immutable ADMIN;

    bool frozen;

    /// @notice Ensures the function is only called by the Admin.
    /// @dev Reverts if `msg.sender` is not the Admin.
    modifier onlyAdmin() {
        if (msg.sender != ADMIN) {
            revert OnlyAdmin();
        }
        _;
    }

    constructor(address admin) {
        ADMIN = admin;
        HUB.registerOrganization("BaseGroupMintRouter", bytes32(0));
    }

    function enableCRCForRouting(address baseGroup, address[] memory crcArray) external {
        if (frozen) revert Frozen();
        if (!BASE_GROUP_FACTORY.deployedByFactory(baseGroup)) revert OnlyBaseGroup();

        for (uint256 i; i < crcArray.length;) {
            address crc = crcArray[i];
            if (!HUB.isHuman(crc)) revert OnlyHuman();
            if (HUB.isTrusted(baseGroup, crc)) HUB.trust(crc, type(uint96).max);
            HUB.setApprovalForAll(crc, true);
            unchecked {
                ++i;
            }
        }
    }

    // way to roll the whole state back

    // Roll back logic

    function freeze(bool _freeze) external onlyAdmin {
        frozen = _freeze;
    }

    function disableCRCForRouting(address[] memory crcArray) external onlyAdmin {
        for (uint256 i; i < crcArray.length;) {
            address crc = crcArray[i];
            // untrust
            if (HUB.isTrusted(address(this), crc)) HUB.trust(crc, uint96(0));
            // revoke approval
            HUB.setApprovalForAll(crc, false);
            unchecked {
                ++i;
            }
        }
    }
}
