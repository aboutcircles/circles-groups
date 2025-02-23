// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "openzeppelin-contracts/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "src/circles/Core.sol";
import "src/circles/Types.sol";
import "src/errors/Errors.sol";
import "src/core-members-group/CMGHandler.sol";
import "src/core-members-group/ICoreMembersGroup.sol";
import "src/circles/IStandardTreasury.sol";

/// @notice
contract CMGRedemptionHandler is CMGHandler, CirclesTypes {
    // Constants

    /// @notice Indefinite future, or approximated with uint96.max
    uint96 internal constant INDEFINITE_FUTURE = type(uint96).max;

    /// @dev Treasury
    IStandardTreasury internal immutable TREASURY;

    // Events

    /// @notice Clarification event to report handler returned redeemed collateral Circles to beneficiary
    ///         for total amount redeemed.
    event ReturnedRedeemedCollateral(address indexed group, address indexed beneficiary, uint256 totalAmount);

    // Constructor

    constructor(address _cmGroup, address _treasury, address _owner, string memory _name)
        CMGHandler(_cmGroup, _owner)
    {
        TREASURY = IStandardTreasury(_treasury);
        // append "-redeemer" to group's name to register organization
        string memory orgName = string.concat(_name, "-redeemer");
        // register handler as organization in hub
        hub.registerOrganization(orgName, bytes32(0));
        // the redemption handler only trusts the CM Group so that over paths
        // it only accepts group Circles
        hub.trust(_cmGroup, INDEFINITE_FUTURE);
    }

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
        override
        onlyHub
        returns (bytes4)
    {
        // check transient storage to see if we are expecting a return
        (uint256 ongoingConversion, address beneficiary) = _expectingConversionReturn();
        // starting branch: receive groupId to initiate redemption
        if (ongoingConversion == 0 && _id == cmGroupId) {
            _initiateConversion(_from, _value);
            // use redemption data from stream
            hub.safeTransferFrom(address(this), address(TREASURY), _id, _value, _data);
        } else if (ongoingConversion == _value && _id != cmGroupId) {
            // continuation branch: receive a single collateral id

            // expect this to be sent by the vault
            if (_getGroupVault() != _from) {
                revert CGMHandlerRedemptionExpectedFromVault(_from);
            }

            _clearConversion();
            // return the collateral with the redemption data (sent back via vault to us)
            // todo: consider mirroring back the original data when stored in tstorage - now we send the "redemption structured data" which is redundant for receiver
            hub.safeTransferFrom(address(this), beneficiary, _id, _value, _data);

            // emit clarification event of returned collateral
            emit ReturnedRedeemedCollateral(cmGroup, beneficiary, _value);
        } else {
            // if the amount does not match
            // or id is groupid, unexpected
            revert CMGHandlerConversionOngoing(ongoingConversion);
        }
        return this.onERC1155Received.selector;
    }

    /// @notice Handler for receiving batch ERC1155 token transfers
    /// @param _from Address that initiated the transfer
    /// @param _ids Array of token IDs being transferred
    /// @param _values Array of amounts being transferred for each token ID
    /// @param _data Additional data passed with transfer
    /// @return bytes4 Function selector to confirm transfer acceptance
    function onERC1155BatchReceived(
        address, /*_operator*/
        address _from,
        uint256[] memory _ids,
        uint256[] memory _values,
        bytes memory _data
    ) public override onlyHub returns (bytes4) {
        // check for expected conversion
        (uint256 ongoingConversion, address beneficiary) = _expectingConversionReturn();

        // verify we are expecting a conversion
        if (ongoingConversion == 0) {
            revert CMGHandlerNoConversionExpected();
        }

        // sum the _values
        uint256 length = _values.length;
        uint256 totalValue = 0;
        for (uint256 i = 0; i < length; i++) {
            totalValue += _values[i];
        }
        if (totalValue == uint256(0)) {
            revert CMGHandlerReceivedZeroAmount();
        }
        if (ongoingConversion != totalValue) {
            revert CMGHandlerConversionOngoing(ongoingConversion);
        }

        // verify sender is the group vault
        if (_from != _getGroupVault()) {
            revert CGMHandlerRedemptionExpectedFromVault(_from);
        }

        // clear conversion state
        _clearConversion();

        // forward tokens to beneficiary
        hub.safeBatchTransferFrom(address(this), beneficiary, _ids, _values, _data);

        // emit clarification event of returned collateral
        emit ReturnedRedeemedCollateral(cmGroup, beneficiary, totalValue);

        return this.onERC1155BatchReceived.selector;
    }

    // Public view functions

    function structureRedemptionData(uint256[] memory _redemptionIds, uint256[] memory _redemptionValues)
        public
        pure
        returns (bytes memory)
    {
        bytes memory userData = abi.encode(BaseRedemptionPolicy(_redemptionIds, _redemptionValues));
        bytes memory data = abi.encode(Metadata(METADATATYPE_GROUPREDEEM, "", userData));
        return data;
    }

    // Internal helpers

    /// @dev Helper to get the vault for the core members group with standard error handling
    function _getGroupVault() internal view returns (address) {
        // get target group's vault from treasury's mapping
        // as CMG it is always created with standard treasury
        address vault = TREASURY.vaults(cmGroup); // Question: it is constant address per group, why extra read? TODO: generally fix: excess external calls/storage/constants.
        if (vault == address(0)) {
            // if no gCRC has been minted, vault is not yet deployed
            revert CMGHandlerVaultNotFound(address(cmGroup));
        }
        return vault;
    }
}
