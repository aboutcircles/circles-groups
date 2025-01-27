// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "src/CoreMembersGroup/CoreMembersGroup.sol";
import "src/projects/ces/CESCoreAddresses.sol";

contract CESgroup is CoreMembersGroup, CESCoreAddresses {
    // External functions

    /// @notice Trust or untrust a batch of LBP Backers.
    /// @param _backers Array of backer addresses to trust/untrust
    /// @param _expiry Trust expiry timestamp. If >= current timestamp,
    ///        trust backers with active LBPs. If < current timestamp,
    ///        untrust currently trusted backers
    function trustBatch(address[] memory _backers, uint96 _expiry) public override onlyOwnerOrService {
        if (_expiry >= block.timestamp) {
            uint256 count = 0;
            address[] memory activeBackers = new address[](_backers.length);

            for (uint256 i; i < _backers.length; i++) {
                if (launchpad.isActiveLBP(_backers[i])) {
                    activeBackers[count] = _backers[i];
                    count++;
                }
            }

            // Resize array to actual count of active backers
            address[] memory verifiedBackers = new address[](count);
            for (uint256 i; i < count; i++) {
                verifiedBackers[i] = activeBackers[i];
            }

            // effect the asserted verified backers
            super.trustBatch(verifiedBackers, _expiry);
        } else {
            super.trustBatch(_backers, _expiry);
        }
    }
}
