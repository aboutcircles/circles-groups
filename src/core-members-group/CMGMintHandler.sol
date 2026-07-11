// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "openzeppelin-contracts/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "circles-contracts-v2/hub/TypeDefinitions.sol";
import "src/circles/Core.sol";
import "src/errors/Errors.sol";
import "src/core-members-group/CMGHandler.sol";
import "src/core-members-group/ICMGMintHandler.sol";

/// @notice CoreMembers group (CMG) Mint Handler is deployed by the CMgroup
///         and functions as a helper for group mints. It mirrors the
///         trust relations of the CMGroup so that path transfers to it
///         result in valid collateral the handler can mint in the group
///         and return to the original sender.
///         For path-based group mints the handler can not enforce
///         custom requirements (eg. extended membership to the group),
///         so for a general framework one should use ERC1155 operators.
contract CMGMintHandler is CMGHandler, ERC1155Holder, ICMGMintHandler {
    // Constants

    /// @dev single transient slot where to store conversion amount in progress
    ///      to handle acceptance call gracefully
    bytes32 internal constant CONVERSION_SLOT = keccak256("CONVERSION_SLOT");
    /// @dev single transient slot where to store beneficiary address
    bytes32 internal constant BENEFICIARY_SLOT = keccak256("BENEFICIARY_SLOT");

    // Events

    /// @notice Clarification event to report handler returned minted group Circles to beneficiary
    event ReturnedMintedGroupCircles(address indexed group, address indexed beneficiary, uint256 amount);

    // Constructor

    constructor(address _owner, string memory _name, CirclesCore memory _circlesCore)
        CMGHandler(msg.sender, _owner, _circlesCore)
    {
        // append "-minter" to group's name to register organization
        string memory orgName = string.concat(_name, "-minter");
        // register handler as organization in hub
        circlesCore.hub.registerOrganization(orgName, bytes32(0));
    }

    // External functions

    /// @notice Mirror trust relationships from the CMgroup to the handler.
    ///         This allows the handler to maintain the same trust state
    ///         as the CMgroup for automatic path mints/redemptions.
    /// @param _backer Address that is trusted by the CMgroup
    /// @param _expiry Expiry time until when trust is valid
    function mirrorTrust(address _backer, uint96 _expiry) external onlyCMGroup {
        circlesCore.hub.trust(_backer, _expiry);
    }

    /// @notice Sync trust relationships from the CMgroup to the handler.
    ///         For each trust relation of the CMgroup, trust that account
    ///         with the same expiry time. If the handler currently trusts
    ///         an account that is not trusted by the CMgroup anymore,
    ///         untrust by setting the expiry time to current block.
    /// @param _trustRelations Array of addresses to sync trust status for
    function syncTrust(address[] calldata _trustRelations) external {
        uint256 length = _trustRelations.length;
        address trustee;
        for (uint256 i = 0; i < length; i++) {
            trustee = _trustRelations[i];
            if (circlesCore.hub.isTrusted(cmGroup, trustee)) {
                TypeDefinitions.TrustMarker memory marker = circlesCore.hub.trustMarkers(cmGroup, trustee);
                circlesCore.hub.trust(trustee, marker.expiry);
            } else {
                // if handler trusts this trustee
                // untrust by setting expiry to block.timestamp
                if (circlesCore.hub.isTrusted(address(this), trustee)) {
                    circlesCore.hub.trust(trustee, uint96(block.timestamp));
                }
            }
        }
    }

    // ERC1155 acceptance call handlers

    /// @notice Handler for receiving single ERC1155 token transfers.
    ///         Upon receiving valid collateral, it will try to
    ///         group mint the received collateral and return the group
    ///         Circles to the original sender.
    /// @dev Only callable by the Circles Hub.
    /// @param _from Address that initiated the transfer
    /// @param _id Token ID being transferred
    /// @param _value Amount of tokens being transferred
    /// @param _data Additional data passed with transfer
    /// @return bytes4 Function selector to confirm transfer acceptance
    function onERC1155Received(
        address,
        /*_operator*/
        address _from,
        uint256 _id,
        uint256 _value,
        bytes memory _data
    ) public override onlyHub returns (bytes4) {
        // check transient storage to see if we are expecting a return
        (uint256 ongoingConversion,) = _expectingConversionReturn();

        if (_from == address(0)) {
            // group CRC were minted here
            // so expect an ongoing conversion from collateral to gCRC
            if (ongoingConversion == _value && _id == cmGroupId) {
                _clearConversion();
                // return the gCRC at the conclusion of the original handler,
                // so gracefully accept and return
                return this.onERC1155Received.selector;
            } else {
                // unexpected gCRC mint
                revert CMGHandlerLogicAssertion();
            }
        } else if (_id == cmGroupId) {
            // redemptions are handled only by redemption handler
            revert CMGHandlerAcceptanceCallUnhandled();
        } else {
            // from is not zero (ie. not minted) && id is not gCRC

            // set our expectation lock (reverts if already ongoing)
            _initiateConversion(_from, _value);

            // assume any tokens received (that are not gCRC)
            // to be an attempt to mint gCRC
            address[] memory collateralAvatars = new address[](1);
            uint256[] memory amounts = new uint256[](1);
            // safely cast because ids received from hub
            collateralAvatars[0] = address(uint160(_id));
            amounts[0] = _value;
            // initiate groupMint (which will call back, but expectation lock is set)
            circlesCore.hub.groupMint(cmGroup, collateralAvatars, amounts, _data);

            // conversion in cleared upon receiving gCRC from minting; double check it is indeed cleared
            (uint256 verifyCleared,) = _expectingConversionReturn();
            if (verifyCleared != uint256(0)) {
                // unexpected gCRC mint did not occur to clear the ongoing conversion
                revert CMGHandlerLogicAssertion();
            }

            // return the freshly minted gCRC to sender
            circlesCore.hub.safeTransferFrom(address(this), _from, cmGroupId, _value, _data);

            // emit event for clarity
            emit ReturnedMintedGroupCircles(cmGroup, _from, _value);
        }
        return this.onERC1155Received.selector;
    }

    /// @notice Handler for receiving batch ERC1155 token transfers
    /// @dev Only callable by the Circles Hub.
    ///      First parameter _operator is unused.
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
    ) public virtual override onlyHub returns (bytes4) {
        if (_from == address(0)) {
            // it should be impossible that Circles get minted here (as batch)
            revert CMGHandlerLogicAssertion();
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

        // check transient storage to see if we are expecting a return
        (uint256 ongoingConversion,) = _expectingConversionReturn();

        if (ongoingConversion != uint256(0)) {
            // redemptions are handled by redemption handler,
            // so a batch acceptance call must only happen at the start of a mint conversion
            revert CMGHandlerConversionOngoing(ongoingConversion);
        }
        // there is no ongoing conversion registered, so interpret this as
        // a request to group mint

        // revert if ids reference our Core Members group directly
        address[] memory collateralAvatars = _doesNotContainGroupCircles(_ids);
        // enable the lock
        _initiateConversion(_from, totalValue);
        // attempt group mint
        circlesCore.hub.groupMint(cmGroup, collateralAvatars, _values, _data);
        // tidy up afterwards
        _clearConversion();
        // return the freshly minted gCRC to sender
        circlesCore.hub.safeTransferFrom(address(this), _from, cmGroupId, totalValue, _data);

        // emit event for clarity
        emit ReturnedMintedGroupCircles(cmGroup, _from, totalValue);

        return this.onERC1155BatchReceived.selector;
    }

    // Owner interaction helper functions

    /// @notice Safely transfers a single ERC1155 token through the Circles Hub.
    /// @dev Only callable by the owner of this contract. Reverts if _from is not this contract.
    /// @param _from The address currently holding the token to be transferred.
    /// @param _to The address to which the token will be transferred.
    /// @param _id The ID of the token being transferred.
    /// @param _value The amount of the token being transferred.
    /// @param _data Additional data with no specified format, sent in call to `_to`.
    function safeTransferFrom(address _from, address _to, uint256 _id, uint256 _value, bytes calldata _data)
        external
        onlyOwner
    {
        if (_from != address(this)) {
            revert CMGHandlerOnlyTransferOwnCircles();
        }
        circlesCore.hub.safeTransferFrom(_from, _to, _id, _value, _data);
    }

    /// @notice Safely transfers a batch of ERC1155 tokens through the Circles Hub.
    /// @dev Only callable by the owner of this contract. Reverts if _from is not this contract.
    /// @dev Only callable by the owner of this contract.
    /// @param _from The address currently holding the tokens to be transferred.
    /// @param _to The address to which the tokens will be transferred.
    /// @param _ids An array of token IDs being transferred.
    /// @param _values An array of amounts being transferred for each token ID.
    /// @param _data Additional data with no specified format, sent in call to `_to`.
    function safeBatchTransferFrom(
        address _from,
        address _to,
        uint256[] calldata _ids,
        uint256[] calldata _values,
        bytes calldata _data
    ) external onlyOwner {
        if (_from != address(this)) {
            revert CMGHandlerOnlyTransferOwnCircles();
        }
        circlesCore.hub.safeBatchTransferFrom(_from, _to, _ids, _values, _data);
    }

    /// @notice Sets advanced usage flags for this group in the Hub
    /// @param _flag Advanced usage flag value to set
    function setAdvancedUsageFlag(bytes32 _flag) external onlyOwner {
        circlesCore.hub.setAdvancedUsageFlag(_flag);
    }

    /// @notice Updates the metadata digest for this group in the name registry
    /// @param _metadataDigest New metadata digest value
    function updateMetadataDigest(bytes32 _metadataDigest) external onlyOwner {
        circlesCore.nameRegistry.updateMetadataDigest(_metadataDigest);
    }

    /// @notice Registers a short name for this group in the name registry
    function registerShortName() external onlyOwner {
        circlesCore.nameRegistry.registerShortName();
    }

    /// @notice Registers a short name for this group with a specified nonce
    /// @param _nonce Nonce value to use for short name registration
    function registerShortNameWithNonce(uint256 _nonce) external onlyOwner {
        circlesCore.nameRegistry.registerShortNameWithNonce(_nonce);
    }

    // Internal functions

    /// @notice Checks if token IDs do not contain group circles and converts to avatar addresses
    /// @dev Used internally to validate batch transfers don't contain group circles.
    ///      Token IDs from hub are trusted to be valid addresses after conversion.
    /// @param _ids Array of token IDs to check and convert
    /// @return Array of collateral avatar addresses converted from token IDs
    function _doesNotContainGroupCircles(uint256[] memory _ids) internal view returns (address[] memory) {
        uint256 length = _ids.length;
        address[] memory collateralAvatars = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            if (_ids[i] == cmGroupId) {
                revert CMGHandlerRefuseGroupCircles();
            }
            // confidently cast to address, as ids are given by hub
            collateralAvatars[i] = address(uint160(_ids[i]));
        }
        return collateralAvatars;
    }

    /// @notice Initiates a conversion process by storing the amount in transient storage
    /// @dev Uses transient storage to track ongoing conversions within a transaction
    /// @param _amount Amount to convert - must be non-zero
    function _initiateConversion(address _beneficiary, uint256 _amount) internal {
        // Revert if amount is zero
        if (_amount == uint256(0)) {
            revert CMGHandlerReceivedZeroAmount();
        }

        uint256 ongoingConversion;
        bytes32 conversionSlot = CONVERSION_SLOT;
        bytes32 beneficiarySlot = BENEFICIARY_SLOT;

        // Load any existing conversion amount from transient storage
        assembly {
            ongoingConversion := tload(conversionSlot)
        }

        // Revert if there is already an ongoing conversion
        if (ongoingConversion != uint256(0)) {
            // don't initiate a new conversion if one is ongoing
            revert CMGHandlerConversionOngoing(ongoingConversion);
        }

        // Store the new conversion amount, and beneficiary in transient storage
        assembly {
            tstore(conversionSlot, _amount)
            tstore(beneficiarySlot, _beneficiary)
        }

        emit ConversionInitiated(_beneficiary, _amount);
    }

    /// @notice Checks if there is an ongoing conversion and returns the amount and beneficiary
    /// @dev Reads the current conversion amount and beneficiary from transient storage
    /// @return ongoingConversion The amount of the ongoing conversion, or 0 if none is active
    /// @return beneficiary The address of the beneficiary for the ongoing conversion
    function _expectingConversionReturn() internal view returns (uint256 ongoingConversion, address beneficiary) {
        bytes32 conversionSlot = CONVERSION_SLOT;
        bytes32 beneficiarySlot = BENEFICIARY_SLOT;

        // Load the current conversion amount, beneficiary and data hash from transient storage
        assembly {
            ongoingConversion := tload(conversionSlot)
            beneficiary := tload(beneficiarySlot)
        }

        return (ongoingConversion, beneficiary);
    }

    /// @notice Clears the ongoing conversion by resetting transient storage
    /// @dev Clears conversion amount, beneficiary and data hash slots
    function _clearConversion() internal {
        bytes32 conversionSlot = CONVERSION_SLOT;
        bytes32 beneficiarySlot = BENEFICIARY_SLOT;

        assembly {
            tstore(conversionSlot, 0)
            tstore(beneficiarySlot, 0)
        }

        emit ConversionCleared();
    }
}
