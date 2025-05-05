// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

/**
 * @title BaseMintPolicy
 * @notice A base contract defining simple mint and burn policies that always return true.
 * @dev This contract can be inherited by other contracts to quickly implement basic mint/burn checks.
 */
contract BaseMintPolicy {
    /**
     * @notice Checks whether a mint operation is allowed before execution.
     * @dev Always returns true in this base implementation.
     * @return bool A boolean value indicating whether the mint is approved (always true here).
     */
    function beforeMintPolicy(
        address, /*_minter*/
        address, /*_group*/
        uint256[] calldata, /*_collateral*/
        uint256[] calldata, /*_amounts*/
        bytes calldata /*_data*/
    ) external virtual returns (bool) {
        return true;
    }

    /**
     * @notice Checks whether a burn operation is allowed before execution.
     * @dev Always returns true in this base implementation.
     * @return bool A boolean value indicating whether the burn is approved (always true here).
     */
    function beforeBurnPolicy(address, /*_burner*/ address, /*_group*/ uint256, /*_amount*/ bytes calldata /*_data*/ )
        external
        virtual
        returns (bool)
    {
        return true;
    }
}
