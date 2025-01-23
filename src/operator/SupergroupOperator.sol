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
    /// @notice supergroup id
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
        // (because hub.groupMint pulls the collateral from the caller ... learning mistakes)
        hub.safeBatchTransferFrom(msg.sender, address(this), collateralIds, _amounts, "");

        if (supergroup.requireOperator()) {
            if (!_amIAuthorized()) {
                revert SupergroupOperatorNotAuthorizedAndAuthorizationRequired(address(supergroup));
            }
            // when operators are required, an authorized operator must pre-register request before execution
            supergroup.registerOperatorRequest(address(this), address(supergroup), collateralIds, _amounts);
        }

        // transfer resulting group Circles back to caller, possibly withholding fee
        uint256 mintFee = supergroup.mintFee();
        if (mintFee > 0) {
            address feeCollection = supergroup.feeCollection();
            _setExpectationSingleAcceptanceCall(msg.sender, supergroupId, value, _data, mintFee, feeCollection);
        } else {
            _setExpectationSingleAcceptanceCall(msg.sender, supergroupId, value, _data, 0, address(0));
        }
        // after setting the expectations for the acceptance call handler, group mint on behalf of caller
        hub.groupMint(_group, _collateralAvatars, _amounts, _data);

        // the acceptence call handler will handle returning the gCRC to caller, withholding fee if necessary
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
        uint256 length = _redemptionIds.length;
        if (length != _redemptionValues.length || length == 0) {
            revert SupergroupInvalidCallingParameters();
        }
        // sum the total of collateral to claim back, as this amount of group Circles must be sent to treasury
        // to redeem
        uint256 value = 0;
        for (uint256 i = 0; i < length; i++) {
            value += _redemptionValues[i];
        }

        bytes memory userData = abi.encode(BaseRedemptionPolicy(_redemptionIds, _redemptionValues));
        bytes memory data = abi.encode(Metadata(METADATATYPE_GROUPREDEEM, "", userData));

        if (supergroup.redemptionBurnRatio() > 0) {
            // todo: calculate amounts to expect to have returned so that we can set the expectations accordingly
            revert SupergroupOperatorDoesNotImplement();
        }
        // note: for redemption there is no need to set expectation handler yet, because standardVault can directly
        // return the collateral to msg.sender. Keep this code to enable later exit-fee-withholding

        // // the redemption will return the collateral to the operator, and in the on(Batch)Received handler
        // // the operator can forward the returned collateral to the caller,
        // // so first set the expectation for the acceptance handler in our own transient storage.
        // if (length == 1) {
        //     // supergroup does not have a fee on exit (nor do we intend to set a burn, see above)
        //     _setExpectationSingleAcceptanceCall(msg.sender, _redemptionIds[0], _redemptionValues[0], data, 0, address(0));
        // } else {
        //     _setExpectationBatchAcceptanceCall(msg.sender, _redemptionIds, _redemptionValues, data, 0, address(0));
        // }

        // to redeem the group Circles must be sent to StandardTreasury with the correct data formatted.
        hub.safeTransferFrom(msg.sender, standardTreasury, supergroupId, value, data);

        // the vault will directly transfer to msg.sender, so no need for acceptance handler
    }

    // ERC1155 acceptance handlers

    function onERC1155Received(
        address, /*_operator*/
        address, /*_from*/
        uint256 _id,
        uint256 _value,
        bytes memory _data
    ) public override onlyHub returns (bytes4) {
        // current operator only supports a single supergroup, so add sanity check
        if (_id != supergroupId) {
            revert ExpectationSingleReceiveOnlySupergroupId(_id);
        }
        // Check expectation and get final receiver, and possible fee and collection address
        (address finalReceiver, uint256 mintFee, address feeCollection) =
            _checkExpectationSingleAcceptanceCall(_id, _value, _data);

        if (mintFee > 0) {
            // calculate fee and send respective amounts to finalReceiver and collection
            (uint256 returnAmount, uint256 fee) = _splitAmountInReturnAndFee(_value, mintFee);
            // send the return amount to finalReceiver
            hub.safeTransferFrom(address(this), finalReceiver, supergroupId, returnAmount, _data);
            // send the minting fee to collection
            hub.safeTransferFrom(address(this), feeCollection, supergroupId, fee, _data);
        } else {
            // simply return all group Circles to the finalReceiver
            hub.safeTransferFrom(address(this), finalReceiver, supergroupId, _value, _data);
        }

        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address, /*_operator*/
        address, /*_from*/
        uint256[] memory _ids,
        uint256[] memory _values,
        bytes memory _data
    ) public override onlyHub returns (bytes4) {
        // Check expectation and get final receiver, and possible fee and collection address
        (address finalReceiver, uint256 redemptionFee, address feeCollection) =
            _checkExpectationBatchAcceptanceCall(_ids, _values, _data);

        uint256 length = _values.length;
        if (redemptionFee > 0) {
            // Calculate return amounts and fees for each value
            uint256[] memory returnAmounts = new uint256[](length);
            uint256[] memory fees = new uint256[](length);

            for (uint256 i = 0; i < length; i++) {
                (returnAmounts[i], fees[i]) = _splitAmountInReturnAndFee(_values[i], redemptionFee);
            }

            // Send return amounts to finalReceiver
            hub.safeBatchTransferFrom(address(this), finalReceiver, _ids, returnAmounts, _data);
            // Send fees to collection
            hub.safeBatchTransferFrom(address(this), feeCollection, _ids, fees, _data);
        } else {
            // Simply return all group Circles to the finalReceiver
            hub.safeBatchTransferFrom(address(this), finalReceiver, _ids, _values, _data);
        }

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
