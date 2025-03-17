// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "src/errors/Errors.sol";
import "src/circles/Core.sol";

abstract contract CMGHandler is CirclesCoreAddresses, ICMGHandlerErrors {
    // State

    /// @notice CMgroup for which this is a handler.
    address public immutable cmGroup;
    /// @notice tokenId of cmGroup
    uint256 public immutable cmGroupId;
    /// @notice owner
    address public immutable owner;
    /// @notice Circles core protocol addresses
    CirclesCore public circlesCore;

    // Events

    /// @notice Emitted when a new conversion is initiated
    event ConversionInitiated(address indexed beneficiary, uint256 amount);

    /// @notice Emitted when a conversion is completed and cleared
    event ConversionCleared();

    // Modifiers

    /// @notice Only the Circles Hub can call this function
    modifier onlyHub() {
        if (msg.sender != address(circlesCore.hub)) {
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

    /// @notice Reentrancy guard for nonReentrant functions.
    /// see https://soliditylang.org/blog/2024/01/26/transient-storage/
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

    constructor(address _cmGroup, address _owner, CirclesCore memory _circlesCore) {
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
        // store circles core addresses
        circlesCore = _circlesCore;
    }
}
