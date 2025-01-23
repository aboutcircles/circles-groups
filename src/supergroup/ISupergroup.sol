// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

interface ISupergroup {
    /// @notice owner of the supergroup
    function owner() external returns (address);
    /// @notice fee levied upon group minting can be between zero and MAX_FEE (1/12th)
    ///         of the amount minted. Setting the fee to zero disables the fee charge.
    function mintFee() external returns (uint256);
    /// @notice fee collection address collects group minting fees when enabled
    function feeCollection() external returns (address);
    /// @notice redemption burn ratio will burn this ratio (expressed per 10**18). This amount
    ///         will be burnt and is not sent to a collection address.
    function redemptionBurnRatio() external returns (uint256);
    /// @notice returns true when the group requires authorized operators to pre-register
    ///         their mint request with the group.
    function requireOperator() external returns (bool);
    /// @notice if true, the supergroup will upon acceptance call evaluate whether
    ///         to return minted group Circles (when a path transfer terminated
    ///         at the group) to the original sender (of the path).
    function returnGroupCirclesToSender() external returns (bool);
    /// @notice linked list that stores the authorized operators for the group.
    function operators(address) external returns (address);
    /// @notice returns an array of all authorized operators
    function getOperators() external returns (address[] memory);
    /// @notice Checks if an address is an authorized operator
    function isAuthorizedOperator(address operator) external view returns (bool);
    /// @notice a registered operator can register a request for minting
    ///         ahead of explicit group mint or path-based group mints.
    function registerOperatorRequest(
        address _minter,
        address _group,
        uint256[] calldata _collateral,
        uint256[] calldata _amounts
    ) external returns (bool);
}
