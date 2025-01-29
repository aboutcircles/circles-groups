// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "openzeppelin-contracts/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "src/errors/Errors.sol";
import "src/circles/Core.sol";
import "src/CoreMembersGroup/ICMGHandler.sol";

abstract contract CMGHandler is CirclesCoreAddresses, ERC1155Holder, ICMGHandler, ICMGHandlerErrors {
    // Constants

    /// @dev single transient slot where to store conversion amount in progress
    ///      to handle acceptance call gracefully
    bytes32 internal constant CONVERSION_SLOT = keccak256("CONVERSION_SLOT");
    /// @dev single transient slot where to store beneficiary address
    bytes32 internal constant BENEFICIARY_SLOT = keccak256("BENEFICIARY_SLOT");

    // State

    /// @notice CMgroup for which this is a handler.
    address public immutable cmGroup;
    /// @notice tokenId of cmGroup
    uint256 public immutable cmGroupId;
    /// @notice owner
    address public immutable owner;

    // Events

    /// @notice Emitted when a new conversion is initiated
    event ConversionInitiated(address indexed beneficiary, uint256 amount);

    /// @notice Emitted when a conversion is completed and cleared
    event ConversionCleared();

    // Modifiers

    /// @notice Only the Circles Hub can call this function
    modifier onlyHub() {
        if (msg.sender != address(hub)) {
            revert CMGHandlerOnlyHub();
        }
        _;
    }

    /// @notice Only the CM group can call this function
    modifier onlyCMGroup() {
        if (msg.sender != cmGroup) {
            revert CMGHandlerOnlyCMGroup();
        }
        _;
    }

    /// @notice Only owner can call
    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert CMGHandlerOnlyOwner();
        }
        _;
    }

    constructor(address _cmGroup, address _owner) {
        if (_cmGroup == address(0)) {
            // note: should not yet call on hub.isGroup() because address is not
            // registered as group yet in hub.
            revert CMGHandlerInvalidCallingParameters();
        }
        // handler is deployed by deployment helper
        cmGroup = _cmGroup;
        cmGroupId = uint256(uint160(cmGroup));
        // store the group owner for ERC1155 safe transfers
        owner = _owner;
    }

    // External functions

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
        hub.safeTransferFrom(_from, _to, _id, _value, _data);
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
        hub.safeBatchTransferFrom(_from, _to, _ids, _values, _data);
    }

    /// @notice Sets advanced usage flags for this group in the Hub
    /// @param _flag Advanced usage flag value to set
    function setAdvancedUsageFlag(bytes32 _flag) external onlyOwner {
        hub.setAdvancedUsageFlag(_flag);
    }

    /// @notice Updates the metadata digest for this group in the name registry
    /// @param _metadataDigest New metadata digest value
    function updateMetadataDigest(bytes32 _metadataDigest) external onlyOwner {
        nameRegistry.updateMetadataDigest(_metadataDigest);
    }

    /// @notice Registers a short name for this group in the name registry
    function registerShortName() external onlyOwner {
        nameRegistry.registerShortName();
    }

    /// @notice Registers a short name for this group with a specified nonce
    /// @param _nonce Nonce value to use for short name registration
    function registerShortNameWithNonce(uint256 _nonce) external onlyOwner {
        nameRegistry.registerShortNameWithNonce(_nonce);
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

        // Store the new conversion amount and beneficiary in transient storage
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

        // Load the current conversion amount and beneficiary from transient storage
        assembly {
            ongoingConversion := tload(conversionSlot)
            beneficiary := tload(beneficiarySlot)
        }

        return (ongoingConversion, beneficiary);
    }

    /// @notice Clears the ongoing conversion by resetting transient storage
    /// @dev Clears both conversion amount and beneficiary slots
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
