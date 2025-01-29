// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "openzeppelin-contracts/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "circles-contracts-v2/hub/TypeDefinitions.sol";
import "src/circles/Core.sol";
import "src/errors/Errors.sol";
import "src/CoreMembersGroup/CMGHandler.sol";

/// @notice
contract CMGRedemptionHandler is CMGHandler {
    // Constants

    /// @notice Indefinite future, or approximated with uint96.max
    uint96 internal constant INDEFINITE_FUTURE = type(uint96).max;

    // Constructor

    constructor(address _cmGroup, address _owner, string memory _name) CMGHandler(_cmGroup, _owner) {
        // append "-redeemer" to group's name to register organization
        string memory orgName = string.concat(_name, "-redeemer");
        // register handler as organization in hub
        hub.registerOrganization(orgName, bytes32(0));
        hub.trust(_cmGroup, INDEFINITE_FUTURE);
    }

    // External functions

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

    // ERC1155 acceptance call handlers

    /// @notice Handler for receiving single ERC1155 token transfers. Upon receiving
    ///         CMgroup Circles, it will attempt to redeem and return the collateral
    ///         to the caller.
    /// @dev Only callable by the Circles Hub.
    /// @param _from Address that initiated the transfer
    /// @param _id Token ID being transferred
    /// @param _value Amount of tokens being transferred
    /// @param _data Additional data passed with transfer
    /// @return bytes4 Function selector to confirm transfer acceptance
    function onERC1155Received(address, /*_operator*/ address _from, uint256 _id, uint256 _value, bytes memory _data)
        public
        virtual
        override
        onlyHub
        returns (bytes4)
    {

    }

}
