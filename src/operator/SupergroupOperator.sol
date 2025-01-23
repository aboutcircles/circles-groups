// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "src/circles/Core.sol";
import "src/circles/Types.sol";
import "src/errors/Errors.sol";
import "src/supergroup/ISupergroup.sol";
import "src/operator/CompletionHandler.sol";

contract SupergroupOperator is
    CirclesCoreAddresses,
    CirclesTypes,
    CompletionHandler,
    ISupergroupErrors,
    ISupergroupOperatorErrors
{
    // State variables

    /// @notice Supergroup is the explicit group this operator is deployed for.
    ISupergroup public immutable supergroup;
    /// @dev supergroup id
    uint256 public immutable supergroupId;

    // Modifiers

    /// @notice Only the Circles Hub can call this function
    modifier onlyHub() {
        if (msg.sender != address(hub)) {
            revert SupergroupOnlyHub();
        }
        _;
    }

    /**
     * @dev Reentrancy guard for nonReentrant functions.
     * see https://soliditylang.org/blog/2024/01/26/transient-storage/
     */
    modifier nonReentrant() {
        assembly {
            if tload(0) { revert(0, 0) }
            tstore(0, 1)
        }
        _;
        assembly {
            tstore(0, 0)
        }
    }

    // Constructor

    constructor(ISupergroup _supergroup) {
        if (address(_supergroup) == address(0)) {
            // supergroup address must not be zero
            revert SupergroupInvalidCallingParameters();
        }
        supergroup = _supergroup;
        supergroupId = _groupId(address(supergroup));
        // supergroup must have registered in hub before constructing this operator
        address collateralTreasury = hub.treasuries(address(supergroup));
        // calling hub.isGroup is a redundant check, but check it nonetheless for readability
        if (collateralTreasury == address(0) || !hub.isGroup(address(supergroup))) {
            revert SupergroupMustBeRegistered();
        }
        // We want to encourage people to only use the standard treasury, so enforce explicitly.
        if (collateralTreasury != standardTreasury) {
            revert SupergroupMustUseStandardTreasury();
        }
    }

    // External functions

    /// @notice Explicit group mint;
    function groupMint(
        address _group,
        address[] calldata _collateralAvatars,
        uint256[] calldata _amounts,
        bytes calldata _data
    ) external nonReentrant {
        if (_group != address(supergroup)) {
            revert SupergroupOperatorUnservicedGroup(_group);
        }
        uint256 length = _collateralAvatars.length;
        uint256 value = 0;
        uint256[] memory collateralIds = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            collateralIds[i] = uint256(uint160(_collateralAvatars[i]));
            value += _amounts[i];
        }
        // transfer the collateral to this operator, without the data
        // (because hub.groupMint transfers it from the caller ... learning mistakes)
        hub.safeBatchTransferFrom(msg.sender, address(this), collateralIds, _amounts, "");

        if (supergroup.requireOperator()) {
            if (!_amIAuthorized()) {
                revert SupergroupOperatorNotAuthorizedAndAuthorizationRequired(address(supergroup));
            }
            // when operators are required, an authorized operator must pre-register request before execution
            supergroup.registerOperatorRequest(address(this), address(supergroup), collateralIds, _amounts);
        }

        // group mint on behalf of caller
        hub.groupMint(_group, _collateralAvatars, _amounts, _data);
        // transfer resulting group Circles back to caller, possibly withholding fee
        uint256 mintFee = supergroup.mintFee();
        if (mintFee > 0) {
            // calculate fee and send respective amounts back to caller and collection
            address feeCollection = supergroup.feeCollection();
            (uint256 returnAmount, uint256 fee) = _splitAmountInReturnAndFee(value, mintFee);
            // send the return amount to caller
            hub.safeTransferFrom(address(this), msg.sender, supergroupId, returnAmount, _data);
            // send the minting fee to collection
            hub.safeTransferFrom(address(this), feeCollection, supergroupId, fee, _data);
        } else {
            // simply return all group Circles to the caller
            hub.safeTransferFrom(address(this), msg.sender, supergroupId, value, _data);
        }
    }

    /// @notice OperateFlowMatrix
    function operateFlowMatrix() external nonReentrant {}

    /// @notice Redeem is a helper function to construct the data for redeeming
    ///         the collateral from the supergroup. The caller must have authorized
    ///         this operator.
    function redeem(address _group, uint256[] calldata _redemptionIds, uint256[] calldata _redemptionValues)
        external
        nonReentrant
    {
        // sanity check as the operator for groups might get mixed up
        // once many groups and their operators are authorized.
        if (_group != address(supergroup)) {
            revert SupergroupOperatorUnservicedGroup(_group);
        }
        if (_redemptionIds.length != _redemptionValues.length) {
            revert SupergroupInvalidCallingParameters();
        }
        // sum the total of collateral to claim back, as this amount of group Circles must be sent to treasury
        // to redeem
        uint256 value = 0;
        uint256 length = _redemptionIds.length;
        for (uint256 i = 0; i < length; i++) {
            value += _redemptionValues[i];
        }

        bytes memory userData = abi.encode(BaseRedemptionPolicy(_redemptionIds, _redemptionValues));
        bytes memory data = abi.encode(Metadata(METADATATYPE_GROUPREDEEM, "", userData));

        // to redeem the group Circles must be sent to StandardTreasury with the correct data formatted.
        hub.safeTransferFrom(msg.sender, standardTreasury, supergroupId, value, data);
    }

    // ERC1155 acceptance handlers

    function onERC1155Received(address _operator, address _from, uint256 _id, uint256 _value, bytes memory _data)
        public
        override
        onlyHub
        returns (bytes4)
    {
        // Check expectation and get final receiver
        address finalReceiver = _checkExpectationSingleAcceptanceCall(_operator, _from, _id, _value, _data);

        // Forward tokens to final receiver
        hub.safeTransferFrom(address(this), finalReceiver, _id, _value, _data);

        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address _operator,
        address _from,
        uint256[] memory _ids,
        uint256[] memory _values,
        bytes memory _data
    ) public override onlyHub returns (bytes4) {
        // Check expectation and get final receiver
        address finalReceiver = _checkExpectationBatchAcceptanceCall(_operator, _from, _ids, _values, _data);

        // Forward tokens to final receiver
        hub.safeBatchTransferFrom(address(this), finalReceiver, _ids, _values, _data);

        return this.onERC1155BatchReceived.selector;
    }

    // Internal functions

    function _amIAuthorized() internal view returns (bool) {
        return hub.isApprovedForAll(address(supergroup), address(this));
    }

    // todo: these are duplicated in supergroup and operator, clean up

    /// @dev Splits a given amount into return and fee based on the provided fee ratio.
    function _splitAmountInReturnAndFee(uint256 _amount, uint256 _feeRatio)
        internal
        pure
        returns (uint256 _returnAmount, uint256 _fee)
    {
        _returnAmount = (_amount * _feeRatio) / 1 ether;
        _fee = _amount - _returnAmount;
    }

    function _groupId(address _group) internal pure returns (uint256) {
        return uint256(uint160(address(_group)));
    }
}
