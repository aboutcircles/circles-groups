// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.24 >=0.8.28 ^0.8.20;

// lib/circles-contracts-v2/lib/openzeppelin-contracts/contracts/proxy/Proxy.sol

// OpenZeppelin Contracts (last updated v5.0.0) (proxy/Proxy.sol)

/**
 * @dev This abstract contract provides a fallback function that delegates all calls to another contract using the EVM
 * instruction `delegatecall`. We refer to the second contract as the _implementation_ behind the proxy, and it has to
 * be specified by overriding the virtual {_implementation} function.
 *
 * Additionally, delegation to the implementation can be triggered manually through the {_fallback} function, or to a
 * different contract through the {_delegate} function.
 *
 * The success and return data of the delegated call will be returned back to the caller of the proxy.
 */
abstract contract Proxy {
    /**
     * @dev Delegates the current call to `implementation`.
     *
     * This function does not return to its internal call site, it will return directly to the external caller.
     */
    function _delegate(address implementation) internal virtual {
        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    /**
     * @dev This is a virtual function that should be overridden so it returns the address to which the fallback
     * function and {_fallback} should delegate.
     */
    function _implementation() internal view virtual returns (address);

    /**
     * @dev Delegates the current call to the address returned by `_implementation()`.
     *
     * This function does not return to its internal call site, it will return directly to the external caller.
     */
    function _fallback() internal virtual {
        _delegate(_implementation());
    }

    /**
     * @dev Fallback function that delegates calls to the address returned by `_implementation()`. Will run if no other
     * function in the contract matches the call data.
     */
    fallback() external payable virtual {
        _fallback();
    }
}

// lib/circles-contracts-v2/lib/openzeppelin-contracts/contracts/proxy/beacon/IBeacon.sol

// OpenZeppelin Contracts (last updated v5.0.0) (proxy/beacon/IBeacon.sol)

/**
 * @dev This is the interface that {BeaconProxy} expects of its beacon.
 */
interface IBeacon {
    /**
     * @dev Must return an address that can be used as a delegate call target.
     *
     * {UpgradeableBeacon} will check that this address is a contract.
     */
    function implementation() external view returns (address);
}

// lib/circles-contracts-v2/lib/openzeppelin-contracts/contracts/utils/Address.sol

// OpenZeppelin Contracts (last updated v5.0.0) (utils/Address.sol)

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev The ETH balance of the account is not enough to perform the operation.
     */
    error AddressInsufficientBalance(address account);

    /**
     * @dev There's no code at `target` (it is not a contract).
     */
    error AddressEmptyCode(address target);

    /**
     * @dev A call to an address target failed. The target may have reverted.
     */
    error FailedInnerCall();

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://consensys.net/diligence/blog/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.8.20/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        if (address(this).balance < amount) {
            revert AddressInsufficientBalance(address(this));
        }

        (bool success, ) = recipient.call{value: amount}("");
        if (!success) {
            revert FailedInnerCall();
        }
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason or custom error, it is bubbled
     * up by this function (like regular Solidity function calls). However, if
     * the call reverted with no returned reason, this function reverts with a
     * {FailedInnerCall} error.
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        if (address(this).balance < value) {
            revert AddressInsufficientBalance(address(this));
        }
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Tool to verify that a low level call to smart-contract was successful, and reverts if the target
     * was not a contract or bubbling up the revert reason (falling back to {FailedInnerCall}) in case of an
     * unsuccessful call.
     */
    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata
    ) internal view returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            // only check if target is a contract if the call was successful and the return data is empty
            // otherwise we already know that it was a contract
            if (returndata.length == 0 && target.code.length == 0) {
                revert AddressEmptyCode(target);
            }
            return returndata;
        }
    }

    /**
     * @dev Tool to verify that a low level call was successful, and reverts if it wasn't, either by bubbling the
     * revert reason or with a default {FailedInnerCall} error.
     */
    function verifyCallResult(bool success, bytes memory returndata) internal pure returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            return returndata;
        }
    }

    /**
     * @dev Reverts with returndata if present. Otherwise reverts with {FailedInnerCall}.
     */
    function _revert(bytes memory returndata) private pure {
        // Look for revert reason and bubble it up if present
        if (returndata.length > 0) {
            // The easiest way to bubble the revert reason is using memory via assembly
            /// @solidity memory-safe-assembly
            assembly {
                let returndata_size := mload(returndata)
                revert(add(32, returndata), returndata_size)
            }
        } else {
            revert FailedInnerCall();
        }
    }
}

// lib/circles-contracts-v2/lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol

// OpenZeppelin Contracts (last updated v5.0.0) (utils/StorageSlot.sol)
// This file was procedurally generated from scripts/generate/templates/StorageSlot.js.

/**
 * @dev Library for reading and writing primitive types to specific storage slots.
 *
 * Storage slots are often used to avoid storage conflict when dealing with upgradeable contracts.
 * This library helps with reading and writing to such slots without the need for inline assembly.
 *
 * The functions in this library return Slot structs that contain a `value` member that can be used to read or write.
 *
 * Example usage to set ERC1967 implementation slot:
 * ```solidity
 * contract ERC1967 {
 *     bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
 *
 *     function _getImplementation() internal view returns (address) {
 *         return StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value;
 *     }
 *
 *     function _setImplementation(address newImplementation) internal {
 *         require(newImplementation.code.length > 0);
 *         StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value = newImplementation;
 *     }
 * }
 * ```
 */
library StorageSlot {
    struct AddressSlot {
        address value;
    }

    struct BooleanSlot {
        bool value;
    }

    struct Bytes32Slot {
        bytes32 value;
    }

    struct Uint256Slot {
        uint256 value;
    }

    struct StringSlot {
        string value;
    }

    struct BytesSlot {
        bytes value;
    }

    /**
     * @dev Returns an `AddressSlot` with member `value` located at `slot`.
     */
    function getAddressSlot(bytes32 slot) internal pure returns (AddressSlot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `BooleanSlot` with member `value` located at `slot`.
     */
    function getBooleanSlot(bytes32 slot) internal pure returns (BooleanSlot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `Bytes32Slot` with member `value` located at `slot`.
     */
    function getBytes32Slot(bytes32 slot) internal pure returns (Bytes32Slot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `Uint256Slot` with member `value` located at `slot`.
     */
    function getUint256Slot(bytes32 slot) internal pure returns (Uint256Slot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `StringSlot` with member `value` located at `slot`.
     */
    function getStringSlot(bytes32 slot) internal pure returns (StringSlot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `StringSlot` representation of the string storage pointer `store`.
     */
    function getStringSlot(string storage store) internal pure returns (StringSlot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := store.slot
        }
    }

    /**
     * @dev Returns an `BytesSlot` with member `value` located at `slot`.
     */
    function getBytesSlot(bytes32 slot) internal pure returns (BytesSlot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `BytesSlot` representation of the bytes storage pointer `store`.
     */
    function getBytesSlot(bytes storage store) internal pure returns (BytesSlot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := store.slot
        }
    }
}

// lib/circles-contracts-v2/lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol

// OpenZeppelin Contracts (last updated v5.0.0) (utils/introspection/IERC165.sol)

/**
 * @dev Interface of the ERC165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[EIP].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others ({ERC165Checker}).
 *
 * For an implementation, see {ERC165}.
 */
interface IERC165 {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

// lib/circles-contracts-v2/src/circles/IDemurrage.sol

interface IDemurrage {
    function inflationDayZero() external view returns (uint256);
}

// lib/circles-contracts-v2/src/groups/Definitions.sol

contract BaseMintPolicyDefinitions {
    // Type declarations

    /**
     * @notice Base redemption policy to user specify desired collateral to redeem
     */
    struct BaseRedemptionPolicy {
        uint256[] redemptionIds;
        uint256[] redemptionValues;
    }
}

// lib/circles-contracts-v2/src/groups/IMintPolicy.sol

interface IMintPolicy {
    function beforeMintPolicy(
        address minter,
        address group,
        uint256[] calldata collateral,
        uint256[] calldata amounts,
        bytes calldata data
    ) external returns (bool);

    function beforeRedeemPolicy(address operator, address redeemer, address group, uint256 value, bytes calldata data)
        external
        returns (
            uint256[] memory redemptionIds,
            uint256[] memory redemptionValues,
            uint256[] memory burnIds,
            uint256[] memory burnValues
        );

    function beforeBurnPolicy(address burner, address group, uint256 value, bytes calldata data)
        external
        returns (bool);
}

// lib/circles-contracts-v2/src/hub/TypeDefinitions.sol

contract TypeDefinitions {
    // Type declarations

    /**
     * @notice TrustMarker stores the expiry of a trust relation as uint96,
     * and is iterable as a linked list of trust markers.
     * @dev This is used to store the directional trust relation between two avatars,
     * and the expiry of the trust relation as uint96 in unix time.
     */
    struct TrustMarker {
        address previous;
        uint96 expiry;
    }

    struct FlowEdge {
        uint16 streamSinkId;
        uint192 amount;
    }

    struct Stream {
        uint16 sourceCoordinate;
        uint16[] flowEdgeIds; // todo: this can possible be packed more compactly manually, evaluate
        bytes data;
    }

    struct Metadata {
        bytes32 metadataType;
        bytes metadata;
        bytes erc1155UserData;
    }

    struct GroupMintMetadata {
        address group;
    }

    // note: Redemption does not require Metadata

    // Constants

    bytes32 internal constant METADATATYPE_GROUPMINT = keccak256("CIRCLESv2:RESERVED_DATA:CirclesGroupMint");
    bytes32 internal constant METADATATYPE_GROUPREDEEM = keccak256("CIRCLESv2:RESERVED_DATA:CirclesGroupRedeem");
}

// lib/circles-contracts-v2/src/names/INameRegistry.sol

interface INameRegistry {
    function setMetadataDigest(address avatar, bytes32 metadataDigest) external;
    function registerCustomName(address avatar, string calldata name) external;
    function registerCustomSymbol(address avatar, string calldata symbol) external;

    function name(address avatar) external view returns (string memory);
    function symbol(address avatar) external view returns (string memory);
    function getMetadataDigest(address _avatar) external view returns (bytes32);

    function isValidName(string calldata name) external pure returns (bool);
    function isValidSymbol(string calldata symbol) external pure returns (bool);
}

// src/CoreMembersGroup/ICMAncillary.sol

interface ICMAncillary {
    /// @notice Mirrors trust of the CM group with _backer until _expiry for the Ancillary
    function mirrorTrust(address _backer, uint96 _expiry) external;
}

// src/errors/Errors.sol

interface ISupergroupErrors {
    /// @notice Supergroup proxy is already initialised
    error SupergroupProxyAlreadyInitialised();
    /// @notice Only Hub can call
    error SupergroupOnlyHub();
    /// @notice Only owner can call
    error SupergroupOnlyOwner();
    /// @notice Only owner or service can call
    error SupergroupOnlyOwnerOrService();
    /// @notice Only authorized operator can call
    error SupergroupOnlyAuthorizedOperator();
    /// @notice Supergroup must have been registered
    error SupergroupMustBeRegistered();
    /// @notice For security reasons we enforce explicitly that a supergroup registers with the standard treasury only.
    error SupergroupMustUseStandardTreasury();
    /// @notice Sanity check error on calling parameters
    error SupergroupInvalidCallingParameters();
    /// @notice Group only accepts ERC1155 acceptance call if it was for
    ///         minting group circles and returning the resulting gCRC.
    error SupergroupBlockNormalERC1155Transfers();
    /// @notice Group should always block acceptance call for its own id
    ///         or that of untrusted avatars
    error SupergroupAlwaysBlockUntrustedIds();
    /// @notice Reserved addresses cannot be set as operator
    error SupergroupInvalidOperator(address operator);
    /// @notice when operators are required, at least one operator must be activated
    error SupergroupMustHaveOperatorsActivated();
    /// @notice logic assertion
    error SupergroupLogicAssertion();
}

interface ISupergroupRequestErrors {
    /// @notice Operator request is already in progress
    error SupergroupOperatorRequestInProgress();
}

interface ISupergroupPolicyFingerprintsErrors {
    /// @notice Throws when during acceptance call more is
    error SupergroupFingerprintUnderflow();
}

interface ISupergroupOperatorErrors {
    error SupergroupOperatorUnservicedGroup(address group);
    /// @notice the action requires that an authorized operator performs it,
    ///         and this operator is currently not authorized for this supergroup.
    error SupergroupOperatorNotAuthorizedAndAuthorizationRequired(address group);
    /// @notice error to indicate this operator does not implement this (yet).
    error SupergroupOperatorDoesNotImplement();
}

interface ISupergroupOperatorCompletionErrors {
    /// @notice An expectation for a completion call is already set
    error ExpectationAlreadySet(bytes32 expectation);
    /// @notice No expectation was set when checking completion call
    error NoExpectationSet();
    /// @notice The actual completion call parameters did not match the expected ones
    error ExpectationMismatch(bytes32 expected, bytes32 actual);
    /// @notice only expect supergroup id on single receive
    error ExpectationSingleReceiveOnlySupergroupId(uint256 id);
}

interface ICMGroupErrors {
    /// @notice CoreMembers group proxy is already initialised
    error CMGroupProxyAlreadyInitialised();
    /// @notice Only Hub can call
    error CMGroupOnlyHub();
    /// @notice Only owner can call
    error CMGroupOnlyOwner();
    /// @notice Only owner or service can call
    error CMGroupOnlyOwnerOrService();
    /// @notice Sanity check error on calling parameters
    error CMGroupInvalidCallingParameters();
}

interface ICMGroupAncillaryErrors {
    /// @notice only CM Group can call
    error CMAncillaryOnlyCMGroup();
    /// @notice only owner can call
    error CMAncillaryOnlyOwner();
    /// @notice AcceptanceCallUnhandled
    error CMAncillaryAcceptanceCallUnhandled();
    /// @notice Avoid attempting to collateralize self-referential group Circles
    error CMAncillaryRefuseGroupCircles();
    /// @notice Only a single conversion can be ongoing at one time
    error CMAncillaryConversionOngoing(uint256 amount);
    /// @notice Revert on receiving zero amount
    error CMAncillaryReceivedZeroAmount();
    /// @notice logic assertion
    error CMAncillaryLogicAssertion();
}

// lib/circles-contracts-v2/lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol

// OpenZeppelin Contracts (last updated v5.0.1) (token/ERC1155/IERC1155.sol)

/**
 * @dev Required interface of an ERC1155 compliant contract, as defined in the
 * https://eips.ethereum.org/EIPS/eip-1155[EIP].
 */
interface IERC1155 is IERC165 {
    /**
     * @dev Emitted when `value` amount of tokens of type `id` are transferred from `from` to `to` by `operator`.
     */
    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);

    /**
     * @dev Equivalent to multiple {TransferSingle} events, where `operator`, `from` and `to` are the same for all
     * transfers.
     */
    event TransferBatch(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256[] ids,
        uint256[] values
    );

    /**
     * @dev Emitted when `account` grants or revokes permission to `operator` to transfer their tokens, according to
     * `approved`.
     */
    event ApprovalForAll(address indexed account, address indexed operator, bool approved);

    /**
     * @dev Emitted when the URI for token type `id` changes to `value`, if it is a non-programmatic URI.
     *
     * If an {URI} event was emitted for `id`, the standard
     * https://eips.ethereum.org/EIPS/eip-1155#metadata-extensions[guarantees] that `value` will equal the value
     * returned by {IERC1155MetadataURI-uri}.
     */
    event URI(string value, uint256 indexed id);

    /**
     * @dev Returns the value of tokens of token type `id` owned by `account`.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function balanceOf(address account, uint256 id) external view returns (uint256);

    /**
     * @dev xref:ROOT:erc1155.adoc#batch-operations[Batched] version of {balanceOf}.
     *
     * Requirements:
     *
     * - `accounts` and `ids` must have the same length.
     */
    function balanceOfBatch(
        address[] calldata accounts,
        uint256[] calldata ids
    ) external view returns (uint256[] memory);

    /**
     * @dev Grants or revokes permission to `operator` to transfer the caller's tokens, according to `approved`,
     *
     * Emits an {ApprovalForAll} event.
     *
     * Requirements:
     *
     * - `operator` cannot be the caller.
     */
    function setApprovalForAll(address operator, bool approved) external;

    /**
     * @dev Returns true if `operator` is approved to transfer ``account``'s tokens.
     *
     * See {setApprovalForAll}.
     */
    function isApprovedForAll(address account, address operator) external view returns (bool);

    /**
     * @dev Transfers a `value` amount of tokens of type `id` from `from` to `to`.
     *
     * WARNING: This function can potentially allow a reentrancy attack when transferring tokens
     * to an untrusted contract, when invoking {onERC1155Received} on the receiver.
     * Ensure to follow the checks-effects-interactions pattern and consider employing
     * reentrancy guards when interacting with untrusted contracts.
     *
     * Emits a {TransferSingle} event.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - If the caller is not `from`, it must have been approved to spend ``from``'s tokens via {setApprovalForAll}.
     * - `from` must have a balance of tokens of type `id` of at least `value` amount.
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155Received} and return the
     * acceptance magic value.
     */
    function safeTransferFrom(address from, address to, uint256 id, uint256 value, bytes calldata data) external;

    /**
     * @dev xref:ROOT:erc1155.adoc#batch-operations[Batched] version of {safeTransferFrom}.
     *
     * WARNING: This function can potentially allow a reentrancy attack when transferring tokens
     * to an untrusted contract, when invoking {onERC1155BatchReceived} on the receiver.
     * Ensure to follow the checks-effects-interactions pattern and consider employing
     * reentrancy guards when interacting with untrusted contracts.
     *
     * Emits either a {TransferSingle} or a {TransferBatch} event, depending on the length of the array arguments.
     *
     * Requirements:
     *
     * - `ids` and `values` must have the same length.
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155BatchReceived} and return the
     * acceptance magic value.
     */
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external;
}

// lib/circles-contracts-v2/lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155Receiver.sol

// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC1155/IERC1155Receiver.sol)

/**
 * @dev Interface that must be implemented by smart contracts in order to receive
 * ERC-1155 token transfers.
 */
interface IERC1155Receiver is IERC165 {
    /**
     * @dev Handles the receipt of a single ERC1155 token type. This function is
     * called at the end of a `safeTransferFrom` after the balance has been updated.
     *
     * NOTE: To accept the transfer, this must return
     * `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))`
     * (i.e. 0xf23a6e61, or its own function selector).
     *
     * @param operator The address which initiated the transfer (i.e. msg.sender)
     * @param from The address which previously owned the token
     * @param id The ID of the token being transferred
     * @param value The amount of tokens being transferred
     * @param data Additional data with no specified format
     * @return `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))` if transfer is allowed
     */
    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external returns (bytes4);

    /**
     * @dev Handles the receipt of a multiple ERC1155 token types. This function
     * is called at the end of a `safeBatchTransferFrom` after the balances have
     * been updated.
     *
     * NOTE: To accept the transfer(s), this must return
     * `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))`
     * (i.e. 0xbc197c81, or its own function selector).
     *
     * @param operator The address which initiated the batch transfer (i.e. msg.sender)
     * @param from The address which previously owned the token
     * @param ids An array containing ids of each token being transferred (order and length must match values array)
     * @param values An array containing amounts of each token being transferred (order and length must match ids array)
     * @param data Additional data with no specified format
     * @return `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))` if transfer is allowed
     */
    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external returns (bytes4);
}

// lib/circles-contracts-v2/lib/openzeppelin-contracts/contracts/utils/introspection/ERC165.sol

// OpenZeppelin Contracts (last updated v5.0.0) (utils/introspection/ERC165.sol)

/**
 * @dev Implementation of the {IERC165} interface.
 *
 * Contracts that want to implement ERC165 should inherit from this contract and override {supportsInterface} to check
 * for the additional interface id that will be supported. For example:
 *
 * ```solidity
 * function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
 *     return interfaceId == type(MyInterface).interfaceId || super.supportsInterface(interfaceId);
 * }
 * ```
 */
abstract contract ERC165 is IERC165 {
    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}

// lib/circles-contracts-v2/src/circles/ICircles.sol

interface ICircles is IDemurrage {}

// src/circles/INameRegistry.sol

interface INameRegistryExtended is INameRegistry {
    /// @notice updates metadata digest
    function updateMetadataDigest(bytes32 metadataDigest) external;
    /// @notice registers short name
    function registerShortName() external;
    /// @notice registers short name with nonce
    function registerShortNameWithNonce(uint256 nonce) external;
}

// lib/circles-contracts-v2/src/groups/BaseMintPolicy.sol

contract MintPolicy is IMintPolicy {
    // External functions

    /**
     * @notice Simple mint policy that always returns true
     */
    function beforeMintPolicy(
        address, /*_minter*/
        address, /*_group*/
        uint256[] calldata, /*_collateral*/
        uint256[] calldata, /*_amounts*/
        bytes calldata /*_data*/
    ) external virtual override returns (bool) {
        return true;
    }

    /**
     * @notice Simple burn policy that always returns true
     */
    function beforeBurnPolicy(address, address, uint256, bytes calldata) external virtual override returns (bool) {
        return true;
    }

    /**
     * @notice Simple redeem policy that returns the redemption ids and values as requested in the data
     * @param _data Optional data bytes passed to redeem policy
     */
    function beforeRedeemPolicy(
        address, /*_operator*/
        address, /*_redeemer*/
        address, /*_group*/
        uint256, /*_value*/
        bytes calldata _data
    )
        external
        virtual
        override
        returns (
            uint256[] memory _ids,
            uint256[] memory _values,
            uint256[] memory _burnIds,
            uint256[] memory _burnValues
        )
    {
        // simplest policy is to return the collateral as the caller requests it in data
        BaseMintPolicyDefinitions.BaseRedemptionPolicy memory redemption =
            abi.decode(_data, (BaseMintPolicyDefinitions.BaseRedemptionPolicy));

        // and no collateral gets burnt upon redemption
        _burnIds = new uint256[](0);
        _burnValues = new uint256[](0);

        // standard treasury checks whether the total sums add up to the amount of group Circles redeemed
        // so we can simply decode and pass the request back to treasury.
        // The redemption will fail if it does not contain (sufficient of) these Circles
        return (redemption.redemptionIds, redemption.redemptionValues, _burnIds, _burnValues);
    }
}

// lib/circles-contracts-v2/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Utils.sol

// OpenZeppelin Contracts (last updated v5.0.0) (proxy/ERC1967/ERC1967Utils.sol)

/**
 * @dev This abstract contract provides getters and event emitting update functions for
 * https://eips.ethereum.org/EIPS/eip-1967[EIP1967] slots.
 */
library ERC1967Utils {
    // We re-declare ERC-1967 events here because they can't be used directly from IERC1967.
    // This will be fixed in Solidity 0.8.21. At that point we should remove these events.
    /**
     * @dev Emitted when the implementation is upgraded.
     */
    event Upgraded(address indexed implementation);

    /**
     * @dev Emitted when the admin account has changed.
     */
    event AdminChanged(address previousAdmin, address newAdmin);

    /**
     * @dev Emitted when the beacon is changed.
     */
    event BeaconUpgraded(address indexed beacon);

    /**
     * @dev Storage slot with the address of the current implementation.
     * This is the keccak-256 hash of "eip1967.proxy.implementation" subtracted by 1.
     */
    // solhint-disable-next-line private-vars-leading-underscore
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /**
     * @dev The `implementation` of the proxy is invalid.
     */
    error ERC1967InvalidImplementation(address implementation);

    /**
     * @dev The `admin` of the proxy is invalid.
     */
    error ERC1967InvalidAdmin(address admin);

    /**
     * @dev The `beacon` of the proxy is invalid.
     */
    error ERC1967InvalidBeacon(address beacon);

    /**
     * @dev An upgrade function sees `msg.value > 0` that may be lost.
     */
    error ERC1967NonPayable();

    /**
     * @dev Returns the current implementation address.
     */
    function getImplementation() internal view returns (address) {
        return StorageSlot.getAddressSlot(IMPLEMENTATION_SLOT).value;
    }

    /**
     * @dev Stores a new address in the EIP1967 implementation slot.
     */
    function _setImplementation(address newImplementation) private {
        if (newImplementation.code.length == 0) {
            revert ERC1967InvalidImplementation(newImplementation);
        }
        StorageSlot.getAddressSlot(IMPLEMENTATION_SLOT).value = newImplementation;
    }

    /**
     * @dev Performs implementation upgrade with additional setup call if data is nonempty.
     * This function is payable only if the setup call is performed, otherwise `msg.value` is rejected
     * to avoid stuck value in the contract.
     *
     * Emits an {IERC1967-Upgraded} event.
     */
    function upgradeToAndCall(address newImplementation, bytes memory data) internal {
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);

        if (data.length > 0) {
            Address.functionDelegateCall(newImplementation, data);
        } else {
            _checkNonPayable();
        }
    }

    /**
     * @dev Storage slot with the admin of the contract.
     * This is the keccak-256 hash of "eip1967.proxy.admin" subtracted by 1.
     */
    // solhint-disable-next-line private-vars-leading-underscore
    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /**
     * @dev Returns the current admin.
     *
     * TIP: To get this value clients can read directly from the storage slot shown below (specified by EIP1967) using
     * the https://eth.wiki/json-rpc/API#eth_getstorageat[`eth_getStorageAt`] RPC call.
     * `0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103`
     */
    function getAdmin() internal view returns (address) {
        return StorageSlot.getAddressSlot(ADMIN_SLOT).value;
    }

    /**
     * @dev Stores a new address in the EIP1967 admin slot.
     */
    function _setAdmin(address newAdmin) private {
        if (newAdmin == address(0)) {
            revert ERC1967InvalidAdmin(address(0));
        }
        StorageSlot.getAddressSlot(ADMIN_SLOT).value = newAdmin;
    }

    /**
     * @dev Changes the admin of the proxy.
     *
     * Emits an {IERC1967-AdminChanged} event.
     */
    function changeAdmin(address newAdmin) internal {
        emit AdminChanged(getAdmin(), newAdmin);
        _setAdmin(newAdmin);
    }

    /**
     * @dev The storage slot of the UpgradeableBeacon contract which defines the implementation for this proxy.
     * This is the keccak-256 hash of "eip1967.proxy.beacon" subtracted by 1.
     */
    // solhint-disable-next-line private-vars-leading-underscore
    bytes32 internal constant BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    /**
     * @dev Returns the current beacon.
     */
    function getBeacon() internal view returns (address) {
        return StorageSlot.getAddressSlot(BEACON_SLOT).value;
    }

    /**
     * @dev Stores a new beacon in the EIP1967 beacon slot.
     */
    function _setBeacon(address newBeacon) private {
        if (newBeacon.code.length == 0) {
            revert ERC1967InvalidBeacon(newBeacon);
        }

        StorageSlot.getAddressSlot(BEACON_SLOT).value = newBeacon;

        address beaconImplementation = IBeacon(newBeacon).implementation();
        if (beaconImplementation.code.length == 0) {
            revert ERC1967InvalidImplementation(beaconImplementation);
        }
    }

    /**
     * @dev Change the beacon and trigger a setup call if data is nonempty.
     * This function is payable only if the setup call is performed, otherwise `msg.value` is rejected
     * to avoid stuck value in the contract.
     *
     * Emits an {IERC1967-BeaconUpgraded} event.
     *
     * CAUTION: Invoking this function has no effect on an instance of {BeaconProxy} since v5, since
     * it uses an immutable beacon without looking at the value of the ERC-1967 beacon slot for
     * efficiency.
     */
    function upgradeBeaconToAndCall(address newBeacon, bytes memory data) internal {
        _setBeacon(newBeacon);
        emit BeaconUpgraded(newBeacon);

        if (data.length > 0) {
            Address.functionDelegateCall(IBeacon(newBeacon).implementation(), data);
        } else {
            _checkNonPayable();
        }
    }

    /**
     * @dev Reverts if `msg.value` is not zero. It can be used to avoid `msg.value` stuck in the contract
     * if an upgrade doesn't perform an initialization call.
     */
    function _checkNonPayable() private {
        if (msg.value > 0) {
            revert ERC1967NonPayable();
        }
    }
}

// lib/circles-contracts-v2/lib/openzeppelin-contracts/contracts/token/ERC1155/utils/ERC1155Holder.sol

// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC1155/utils/ERC1155Holder.sol)

/**
 * @dev Simple implementation of `IERC1155Receiver` that will allow a contract to hold ERC1155 tokens.
 *
 * IMPORTANT: When inheriting this contract, you must include a way to use the received tokens, otherwise they will be
 * stuck.
 */
abstract contract ERC1155Holder is ERC165, IERC1155Receiver {
    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId || super.supportsInterface(interfaceId);
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }
}

// lib/circles-contracts-v2/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol

// OpenZeppelin Contracts (last updated v5.0.0) (proxy/ERC1967/ERC1967Proxy.sol)

/**
 * @dev This contract implements an upgradeable proxy. It is upgradeable because calls are delegated to an
 * implementation address that can be changed. This address is stored in storage in the location specified by
 * https://eips.ethereum.org/EIPS/eip-1967[EIP1967], so that it doesn't conflict with the storage layout of the
 * implementation behind the proxy.
 */
contract ERC1967Proxy is Proxy {
    /**
     * @dev Initializes the upgradeable proxy with an initial implementation specified by `implementation`.
     *
     * If `_data` is nonempty, it's used as data in a delegate call to `implementation`. This will typically be an
     * encoded function call, and allows initializing the storage of the proxy like a Solidity constructor.
     *
     * Requirements:
     *
     * - If `data` is empty, `msg.value` must be zero.
     */
    constructor(address implementation, bytes memory _data) payable {
        ERC1967Utils.upgradeToAndCall(implementation, _data);
    }

    /**
     * @dev Returns the current implementation address.
     *
     * TIP: To get this value clients can read directly from the storage slot shown below (specified by EIP1967) using
     * the https://eth.wiki/json-rpc/API#eth_getstorageat[`eth_getStorageAt`] RPC call.
     * `0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc`
     */
    function _implementation() internal view virtual override returns (address) {
        return ERC1967Utils.getImplementation();
    }
}

// lib/circles-contracts-v2/src/hub/IHub.sol

interface IHubV2 is IERC1155, ICircles {
    function avatars(address avatar) external view returns (address);
    function isHuman(address avatar) external view returns (bool);
    function isGroup(address avatar) external view returns (bool);
    function isOrganization(address avatar) external view returns (bool);

    function migrate(address owner, address[] calldata avatars, uint256[] calldata amounts) external;
    function mintPolicies(address avatar) external view returns (address);
    function burn(uint256 id, uint256 amount, bytes calldata data) external;

    function operateFlowMatrix(
        address[] calldata _flowVertices,
        TypeDefinitions.FlowEdge[] calldata _flow,
        TypeDefinitions.Stream[] calldata _streams,
        bytes calldata _packedCoordinates
    ) external;
}

// src/CoreMembersGroup/helpers/UpgradeableRenounceableProxy.sol

interface IUpgradeableRenounceableProxy {
    function implementation() external view returns (address);
    function upgradeToAndCall(address newImplementation, bytes memory data) external;
    function renounceUpgradeability() external;
}

contract UpgradeableRenounceableProxy is ERC1967Proxy {
    // Errors

    error BlockReceive();

    /// Triggered when the delegatecall modifies values, indicating a violation of proxy-native functionality.
    error ProxyNative();

    // Constructor

    constructor(address _owner, address _implementation, bytes memory _data) ERC1967Proxy(_implementation, _data) {
        // set the admin to the _owner
        ERC1967Utils.changeAdmin(_owner);
    }

    /// @dev Handles proxy function calls: attempts to dispatch to a specific
    ///      function or delegates all calls to the implementation contract.
    function _fallback() internal virtual override {
        // staticcall implementation() returns the address
        if (msg.sig == IUpgradeableRenounceableProxy.implementation.selector) {
            bytes32 slot = ERC1967Utils.IMPLEMENTATION_SLOT;
            assembly {
                let implementation := sload(slot)
                mstore(0, shr(12, shl(12, implementation)))
                return(0, 0x20)
            }
        }
        // dispatch if caller is admin, otherwise delegate to the implementation
        if (msg.sender == ERC1967Utils.getAdmin()) {
            _dispatchAdmin();
        } else {
            // in principle this can allow the admin to reenter the proxy,
            // and hot swap the implementation.
            _delegate(_implementation());
        }
    }

    /// @dev Overrides the function to add a check that prevents rewriting of admin and implementation slots.
    function _delegate(address implementation) internal virtual override {
        bytes32 adminSlot = ERC1967Utils.ADMIN_SLOT;
        bytes32 implementationSlot = ERC1967Utils.IMPLEMENTATION_SLOT;
        bytes32 errorProxyNative = ProxyNative.selector;
        assembly {
            // put the admin value on the stack before delegatecall (the implementation value has already been read and is on the stack)
            let originalAdminValue := sload(adminSlot)
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())
            switch result
            // delegatecall returns 0 on error.
            case 0 { revert(0, returndatasize()) }
            default {
                // read the values after the delegatecall
                let currentAdminValue := sload(adminSlot)
                let currentImplementationValue := sload(implementationSlot)
                // check that the values remain unchanged
                if iszero(
                    and(eq(originalAdminValue, currentAdminValue), eq(implementation, currentImplementationValue))
                ) {
                    // revert with ProxyNative error, as delegatecall has modified values (proxy-native functionality)
                    mstore(0, errorProxyNative)
                    revert(0, 0x04)
                }
                return(0, returndatasize())
            }
        }
    }

    /// @dev Upgrades to new implementation, renounces the ability to upgrade or moves to regular flow based on admin request.
    function _dispatchAdmin() private {
        if (msg.sig == IUpgradeableRenounceableProxy.upgradeToAndCall.selector) {
            // upgrades to new implementation
            (address newImplementation, bytes memory data) = abi.decode(msg.data[4:], (address, bytes));
            ERC1967Utils.upgradeToAndCall(newImplementation, data);
        } else if (msg.sig == IUpgradeableRenounceableProxy.renounceUpgradeability.selector) {
            // renounces the ability to upgrade the contract, by setting the admin to 0x01.
            ERC1967Utils.changeAdmin(address(0x01));
        } else {
            _delegate(_implementation());
        }
    }

    // Fallback function

    receive() external payable {
        revert BlockReceive();
    }
}

// src/circles/IHub.sol

interface IHub is IHubV2 {
    /// @notice registers group with Circles hub
    function registerGroup(address policy, string calldata name, string calldata symbol, bytes32 metadataDigest)
        external;
    /// @notice register organization with Circles hub
    function registerOrganization(string calldata name, bytes32 metadataDigest) external;
    /// @notice trust sets the trust of the caller for the receiver with an expiry time.
    function trust(address _trustReceiver, uint96 _expiry) external;
    /// @notice isTrusted returns true if the expiry time of the trust relation is in the future
    function isTrusted(address truster, address trustee) external returns (bool);
    /// @notice Trustmarkers returns (iterator, expiry uint96)
    function trustMarkers(address, address) external returns (TypeDefinitions.TrustMarker memory);
    /// @notice treasuries returns the collateral treasury of the group
    function treasuries(address) external returns (address);
    /// @notice sets advanced usage flags
    function setAdvancedUsageFlag(bytes32 flag) external;
    /// @notice groupMint allows the holder of collateral to directly group mint
    function groupMint(
        address group,
        address[] calldata collateralAvatars,
        uint256[] calldata amounts,
        bytes calldata data
    ) external;
}

// src/circles/Core.sol

/// @notice Circles Core Addresses list the constant addresses
///         of the deployed core contracts of Circles on Gnosis Chain.
contract CirclesCoreAddresses {
    // Constants

    // these constants can be verified on
    // https://gnosis.blockscout.com/address/0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8?tab=contract
    /// @dev Hub contract address
    IHub internal constant hub = IHub(address(0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8));
    /// @dev Standard Treasury
    address internal constant standardTreasury = address(0x08F90aB73A515308f03A718257ff9887ED330C6e);
    /// @dev Name Registry
    INameRegistryExtended internal constant nameRegistry =
        INameRegistryExtended(address(0xA27566fD89162cC3D40Cb59c87AAaA49B85F3474));
    /// @dev Migration contract to migrate Circles from Hub v1 to Hub v2
    address internal constant migration = address(0xD44B8dcFBaDfC78EA64c55B705BFc68199B56376);
    /// @dev Lift ERC20 helps lift ERC1155 Circles out into an ERC20 wrapper contract
    address internal constant liftERC20 = address(0x5F99a795dD2743C36D63511f0D4bc667e6d3cDB5);
    /// @dev the original Circles Hub v1 contract
    address internal constant hubV1 = address(0x29b9a7fBb8995b2423a71cC17cf9810798F6C543);
}

// src/CoreMembersGroup/CMAncillary.sol

/// @notice CoreMembers(CM) group Ancillary is deployed by the CMgroup
///         and functions as a helper for group mints and redemptions.
///         For path-based group mints the ancillary can not enforce
///         custom requirements (eg. extended membership to the group),
///         so for a general framework one should use ERC1155 operators.
///         For redemption the ancillary provides simplified methods
///         to perform automatic redemption to the underlying collateral.
contract CMAncillary is CirclesCoreAddresses, ERC1155Holder, ICMGroupAncillaryErrors, ICMGroupErrors {
    // Constants

    /// @dev single transient slot where to store conversion amount in progress
    ///      to handle acceptance call gracefully
    bytes32 internal constant CONVERSION_SLOT = keccak256("CONVERSION_SLOT");
    /// @dev single transient slot where to store beneficiary address
    bytes32 internal constant BENEFICIARY_SLOT = keccak256("BENEFICIARY_SLOT");

    // State

    /// @notice CMgroup for which this is an ancillary.
    address public cmGroup;
    /// @notice tokenId of cmGroup
    uint256 public cmGroupId;
    /// @notice owner
    address public owner;

    // Events

    /// @notice Emitted when a new conversion is initiated
    event ConversionInitiated(address indexed beneficiary, uint256 amount);

    /// @notice Emitted when a conversion is completed and cleared
    event ConversionCleared();

    // Modifiers

    /// @notice Only the Circles Hub can call this function
    modifier onlyHub() {
        if (msg.sender != address(hub)) {
            revert CMGroupOnlyHub();
        }
        _;
    }

    /// @notice Only the CM group can call this function
    modifier onlyCMGroup() {
        if (msg.sender != cmGroup) {
            revert CMAncillaryOnlyCMGroup();
        }
        _;
    }

    /// @notice Only owner can call
    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert CMAncillaryOnlyOwner();
        }
        _;
    }

    // Constructor

    constructor(address _cmGroup, address _owner, string memory _name) {
        // ancillary is deployed by deployment helper
        cmGroup = _cmGroup;
        cmGroupId = uint256(uint160(cmGroup));
        // store the group owner for ERC1155 safe transfers
        owner = _owner;
        // append "-ancillary" to group's name to register organization
        string memory orgName = string.concat(_name, "-ancillary");
        // register ancillary as organization in hub
        hub.registerOrganization(orgName, bytes32(0));
    }

    // External functions

    /// @notice Mirror trust relationships from the CMgroup to the ancillary.
    ///         This allows the ancillary to maintain the same trust state
    ///         as the CMgroup for automatic path mints/redemptions.
    /// @param _backer Address that is trusted by the CMgroup
    /// @param _expiry Expiry time until when trust is valid
    function mirrorTrust(address _backer, uint96 _expiry) external onlyCMGroup {
        hub.trust(_backer, _expiry);
    }

    /// @notice Sync trust relationships from the CMgroup to the ancillary.
    ///         For each trust relation of the CMgroup, trust that account
    ///         with the same expiry time. If the ancillary currently trusts
    ///         an account that is not trusted by the CMgroup anymore,
    ///         untrust by setting the expiry time to current block.
    /// @param _trustRelations Array of addresses to sync trust status for
    function syncTrust(address[] calldata _trustRelations) external {
        uint256 length = _trustRelations.length;
        address trustee;
        for (uint256 i = 0; i < length; i++) {
            trustee = _trustRelations[i];
            if (hub.isTrusted(cmGroup, trustee)) {
                TypeDefinitions.TrustMarker memory marker = hub.trustMarkers(cmGroup, trustee);
                hub.trust(trustee, marker.expiry);
            } else {
                // if ancillary trusts this trustee
                // untrust by setting expiry to block.timestamp
                if (hub.isTrusted(address(this), trustee)) {
                    hub.trust(trustee, uint96(block.timestamp));
                }
            }
        }
    }

    /// @notice Safely transfers a single ERC1155 token from one address to another.
    /// @dev Only callable by the owner of this contract.
    /// @param _from The address currently holding the token to be transferred.
    /// @param _to The address to which the token will be transferred.
    /// @param _id The ID of the token being transferred.
    /// @param _value The amount of the token being transferred.
    /// @param _data Additional data with no specified format, sent in call to `_to`.
    function safeTransferFrom(address _from, address _to, uint256 _id, uint256 _value, bytes calldata _data)
        external
        onlyOwner
    {
        hub.safeTransferFrom(_from, _to, _id, _value, _data);
    }

    /// @notice Safely transfers a batch of ERC1155 tokens from one address to another.
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
        hub.safeBatchTransferFrom(_from, _to, _ids, _values, _data);
    }

    // ERC1155 acceptance call handlers

    /// @notice Handler for receiving single ERC1155 token transfers
    /// @dev Only callable by the Circles Hub. Verifies fingerprints and handles group token returns
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
        // check transient storage to see if we are expecting a return
        (uint256 ongoingConversion,) = _expectingConversionReturn();
        if (_from == address(0)) {
            // group CRC were minted here
            // so expect an ongoing conversion from collateral to gCRC
            if (ongoingConversion == _value && _id == cmGroupId) {
                // return the gCRC at the conclusion of the original handler,
                // so gracefully accept and return
                return this.onERC1155Received.selector;
            } else {
                // unexpected gCRC mint
                revert CMAncillaryLogicAssertion();
            }
        } else if (_id == cmGroupId) {
            // todo: attempt automatic redemption from gCRC to collateral
            revert CMAncillaryAcceptanceCallUnhandled();
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
            hub.groupMint(cmGroup, collateralAvatars, amounts, _data);
            // return the freshly minted gCRC to sender
            hub.safeTransferFrom(address(this), _from, cmGroupId, _value, _data);
            // tidy up afterwards
            _clearConversion();
        }
        return this.onERC1155Received.selector;
    }

    /// @notice Handler for receiving batch ERC1155 token transfers
    /// @dev Only callable by the Circles Hub. Verifies fingerprints and handles group token returns.
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
            revert CMAncillaryLogicAssertion();
        }
        // sum the _values
        uint256 length = _values.length;
        uint256 totalValue = 0;
        for (uint256 i = 0; i < length; i++) {
            totalValue += _values[i];
        }
        if (totalValue == uint256(0)) {
            revert CMAncillaryReceivedZeroAmount();
        }

        // check transient storage to see if we are expecting a return
        (uint256 ongoingConversion, address beneficiary) = _expectingConversionReturn();

        if (ongoingConversion == totalValue) {
            // expect this to be the redemption returned from the group
            // so return directly to the beneficiary
            hub.safeBatchTransferFrom(address(this), beneficiary, _ids, _values, _data);
            // tidy up afterwards
            _clearConversion();
        } else if (ongoingConversion == uint256(0)) {
            // there is no ongoing conversion registered, so interpret this as
            // a request to group mint

            // revert if ids reference our Core Members group directly
            address[] memory collateralAvatars = _doesNotContainGroupCircles(_ids);
            // enable the lock
            _initiateConversion(_from, totalValue);
            // attempt group mint
            hub.groupMint(cmGroup, collateralAvatars, _values, _data);
            // return the freshly minted gCRC to sender
            hub.safeTransferFrom(address(this), _from, cmGroupId, totalValue, _data);
            // tidy up afterwards
            _clearConversion();
        }

        return this.onERC1155BatchReceived.selector;
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
                revert CMAncillaryRefuseGroupCircles();
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
            revert CMAncillaryReceivedZeroAmount();
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
            revert CMAncillaryConversionOngoing(ongoingConversion);
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

// src/CoreMembersGroup/CoreMembersGroup.sol

contract CoreMembersGroup is MintPolicy, CirclesCoreAddresses, ERC1155Holder, ICMGroupErrors {
    // Enum

    /// @notice Proxy status keeps an explicit byte about this state instance
    enum ProxyStatus {
        Uninitialised,
        Mastercopy,
        SetUp
    }

    // State

    /// @notice Owner address. This is a copied value of ERC1967 ADMIN_SLOT
    ///         if this group mastercopy is consumed by an ERC1067 proxy.
    ///         For simplicity and readability we duplicate owner with ERC1967 admin,
    ///         even if for the intended deployment they are the same address.
    address public owner;
    /// @notice stores the ancillary for the CM Group to assist with
    ///         automatic path mints and redemptions for the group.
    ICMAncillary public ancillary;
    /// @notice Service address. The service is limited to trusting (or untrusting) avatars.
    address public service;
    /// @notice We take Hub address from core constants, so we need a minimal variable to
    ///         track whether this state (mastercopy or proxy) has been constructed or setup.
    ProxyStatus public proxyStatus = ProxyStatus.Uninitialised;

    // Events

    /// @notice Track service address changes
    /// @param newService New service address.
    event ServiceUpdated(address indexed newService);

    /// @notice Track ancillary contract changes
    /// @param newAncillary New ancillary contract address.
    event AncillaryUpdated(address indexed newAncillary);

    // Modifiers

    /// @notice Only the Circles Hub can call this function
    modifier onlyHub() {
        if (msg.sender != address(hub)) {
            revert CMGroupOnlyHub();
        }
        _;
    }

    /// @notice Only owner can call
    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert CMGroupOnlyOwner();
        }
        _;
    }

    /// @notice Only owner or service can call
    modifier onlyOwnerOrService() {
        if (msg.sender != owner && msg.sender != service) {
            revert CMGroupOnlyOwnerOrService();
        }
        _;
    }

    // Constructor

    constructor() {
        // set proxy status to mastercopy to block its direct usage
        proxyStatus = ProxyStatus.Mastercopy;
    }

    // Setup

    function setup(
        address _owner,
        address _ancillary,
        address _service,
        string calldata _name,
        string calldata _symbol,
        bytes32 _metadataDigest
    ) public virtual {
        if (proxyStatus != ProxyStatus.Uninitialised) {
            // contract state already initialised.
            revert CMGroupProxyAlreadyInitialised();
        }
        if (_owner == address(0)) {
            revert CMGroupInvalidCallingParameters();
        }
        // set the owner explicitly
        // (recommended same value as ERC1967 ADMIN SLOT)
        owner = _owner;
        // set the service key, can initially be zero address
        service = _service;
        // set the ancillary address, can be zero address
        ancillary = ICMAncillary(_ancillary);

        // register group in hub and set the mint policy to this address
        hub.registerGroup(address(this), _name, _symbol, _metadataDigest);
    }

    // External functions

    /// @notice Change the service address. Service account is able to trust/untrust core members
    ///         alongside the owner.
    /// @param _service Updated service address to give trustBatch privilege to.
    /// @dev The service account must be a non-zero address. Only owner can change the service address.
    function setService(address _service) external onlyOwner {
        if (_service == address(0)) {
            revert CMGroupInvalidCallingParameters();
        }
        service = _service;
        emit ServiceUpdated(service);
    }

    /// @notice Change the ancillary contract address. Ancillary contract helps
    ///         automate path minting/redemptions.
    /// @param _ancillary Updated ancillary contract address.
    /// @dev The ancillary contract can be zero address. Only owner can change the ancillary contract.
    function setAncillary(address _ancillary) external onlyOwner {
        ancillary = ICMAncillary(_ancillary);
        emit AncillaryUpdated(_ancillary);
    }

    /// @notice trust allows the owner to explicitly set trust relations
    ///         for the group.
    function trust(address _trustReceiver, uint96 _expiry) external onlyOwner {
        _trust(_trustReceiver, _expiry);
    }

    /// @notice Trust or untrust a batch of core members.
    /// @param _coreMembers Array of core member addresses to trust/untrust
    /// @param _expiry Trust expiry timestamp. If >= current timestamp, trust core member.
    ///        If < current timestamp, untrust only currently trusted core members (to avoid
    ///        accidentally trusting new core members for a single block).
    function trustBatch(address[] memory _coreMembers, uint96 _expiry) public virtual onlyOwnerOrService {
        uint256 length = _coreMembers.length;
        address coreMember;
        // current block timestamp is an edge-case,
        // when expiry is now or a future time, this implies establishing trust
        // so we perform an explicit check on the launchpad whether these addresses
        // have an active LBP
        if (_expiry >= block.timestamp) {
            for (uint256 i = 0; i < length; i++) {
                coreMember = _coreMembers[i];
                _trust(coreMember, _expiry);
            }
        } else {
            // hub will update older expiry times to current block.timestamp, so preventatively
            // already update to current timestamp
            _expiry = uint96(block.timestamp);
            // if expiry is explicitly set in the past, then that means to untrust the core members
            // however, hub will set trust to current block.timestamp for expiry, so to avoid that
            // we trust a previously never-trusted core members for one block,
            // first check whether the core member is currently trusted;
            for (uint256 i = 0; i < length; i++) {
                coreMember = _coreMembers[i];
                if (hub.isTrusted(address(this), coreMember)) {
                    _trust(coreMember, _expiry);
                }
            }
        }
    }

    /// @notice Safely transfers a single ERC1155 token from one address to another.
    /// @dev Only callable by the owner of this contract.
    /// @param _from The address currently holding the token to be transferred.
    /// @param _to The address to which the token will be transferred.
    /// @param _id The ID of the token being transferred.
    /// @param _value The amount of the token being transferred.
    /// @param _data Additional data with no specified format, sent in call to `_to`.
    function safeTransferFrom(address _from, address _to, uint256 _id, uint256 _value, bytes calldata _data)
        external
        onlyOwner
    {
        hub.safeTransferFrom(_from, _to, _id, _value, _data);
    }

    /// @notice Safely transfers a batch of ERC1155 tokens from one address to another.
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

    /// @notice Internal trust function that trusts a single core member
    ///         through the hub. If ancillary contract is set,
    ///         also mirrors the trust there.
    /// @param _trustReceiver Address of core member to trust
    /// @param _expiry Timestamp when trust expires. If >= current time,
    ///         establishes trust. If < current time, serves to untrust.
    function _trust(address _trustReceiver, uint96 _expiry) internal {
        hub.trust(_trustReceiver, _expiry);
        if (address(ancillary) != address(0)) {
            ancillary.mirrorTrust(_trustReceiver, _expiry);
        }
    }
}

// src/CoreMembersGroup/helpers/CMGroupDeployer.sol

contract CMGroupDeployer {
    // State variables

    /// @notice address of the deployed mastercopy for the CMGroup
    CoreMembersGroup public masterCopyCMGroup;

    // Events

    /// @notice Emitted when a new CMGroup proxy is deployed
    /// @param proxy Address of the deployed proxy contract
    /// @param owner Owner of the new group
    /// @param ancillary Address of the ancillary contract
    event CMGroupCreated(address indexed proxy, address indexed owner, address indexed ancillary);

    /// @notice Emitted when mastercopy is deployed in constructor
    /// @param mastercopy Address of the deployed mastercopy contract
    event MasterCopyDeployed(address indexed mastercopy);

    // Constructor

    constructor() {
        // deploy a master copy for Core Members group
        masterCopyCMGroup = new CoreMembersGroup();
        emit MasterCopyDeployed(address(masterCopyCMGroup));
    }

    // External functions

    /// @notice Create Core Members group for caller
    function createCMGroup(address _service, string calldata _name, string calldata _symbol, bytes32 _metadataDigest)
        external
        returns (address)
    {
        // group and ancillary owner by caller
        address owner = msg.sender;
        // first deploy proxy to obtain address, but don't yet initialise by calling setup
        UpgradeableRenounceableProxy proxy = new UpgradeableRenounceableProxy(owner, address(masterCopyCMGroup), "");
        // instead first set up the ancillary
        CMAncillary ancillary = new CMAncillary(address(proxy), owner, _name);
        // lastly, call setup on the proxy to initialise the group
        CoreMembersGroup(address(proxy)).setup(owner, address(ancillary), _service, _name, _symbol, _metadataDigest);

        emit CMGroupCreated(address(proxy), owner, address(ancillary));
        return address(proxy);
    }
}

