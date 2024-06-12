// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.24;

import "../errors/Errors.sol";
import "../GroupPolicy.sol";

abstract contract PathGuard is GroupPolicy, IGuardsErrors {
    // Modifiers

    /**
     * @notice Reverts if `_data` is empty data. Only allows explicit minting for groups,
     * ie. minting over path transfers are disabled. A path transfer will always call to mint
     * for the group with empty data, so by reverting if the data is empty, path transfer are blocked.
     * Callers of the hub's groupmint function MUST provide (any) non-empty data.
     * By only allowing explicit group minting, a group can restrict who is able to mint for the group.
     * By contrast if widely minting over paths is not guarded against, then anyone who is connected via
     * a path to the group can mint for the group.
     * @param _data The data passed to the group mint function
     * @param _code The error code to revert with
     */
    modifier onlyExplicitGroupMint(bytes calldata _data, uint8 _code) {
        if (_data.length == 0) {
            revert CirclesPathGuardOnlyExplicitGroupMint(_code);
        }
        _;
    }

    // External functions
    /**
     * @notice Simple mint policy that always returns true
     */
    function beforeMintPolicy(
        address, /*_minter*/
        address, /*_group*/
        uint256[] calldata, /*_collateral*/
        uint256[] calldata, /*_amounts*/
        bytes calldata _data
    ) external virtual override onlyExplicitGroupMint(_data, 0) returns (bool) {
        return true;
    }
}
