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

// src/operator/IOperator.sol

/// @notice Operator interface for (super)group
interface IOperator {
// function redeem
}

// src/policies/PolicyTypes.sol

library PolicyTypes {
    /// @notice Domain separator for operator requests
    bytes32 internal constant DOMAIN_SEPARATOR_OPERATOR_REQUEST =
        keccak256("PolicyOperatorRequest(address minter,address group,uint256[] collateral,uint256[] amounts)");

    /// @notice Domain separator for policy fingerprints
    bytes32 internal constant DOMAIN_SEPARATOR_POLICY_FINGERPRINT =
        keccak256("PolicyFingerprint(address group,uint256 collateral)");

    function hashRequest(address _minter, address _group, uint256[] calldata _collateral, uint256[] calldata _amounts)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(DOMAIN_SEPARATOR_OPERATOR_REQUEST, _minter, _group, _collateral, _amounts));
    }

    function hashFingerprint(address _group, uint256 _collateral) internal pure returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_SEPARATOR_POLICY_FINGERPRINT, _group, _collateral));
    }
}

// src/projects/ces/ICirclesBackingFactory.sol

interface ICirclesBackingFactory {
    /// @notice checks if the backer has an active LBP at the factory
    function isActiveLBP(address backer) external view returns (bool);
}

// src/supergroup/ISupergroup.sol

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

// src/projects/ces/CESCoreAddresses.sol

/// @notice Circles Core Addresses list the constant addresses
///         of the deployed core contracts of Circles on Gnosis Chain.
contract CESSupergroupCoreAddresses {
    // Constants

    /// @notice Launchpad enables people to back their personal CRC in an LBP pool.
    ///         This CES supergroup will explicitly check the launchpad whether
    ///         a person has backed their Circles.
    /// WARNING: this is not the final production address
    ICirclesBackingFactory public constant launchpad =
        ICirclesBackingFactory(address(0x4bB5A425a68ed73Cf0B26ce79F5EEad9103C30fc));
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

// src/circles/Types.sol

contract CirclesTypes is TypeDefinitions, BaseMintPolicyDefinitions {}

// src/supergroup/OperatorRequests.sol

abstract contract OperatorRequests is ISupergroupRequestErrors {
    // Internal functions

    /// @dev Validate request subtracts from the counter stored under the request hash
    ///      and returns false if no such request is available (anymore).
    function _validateRequest(bytes32 _requestHash) internal returns (bool) {
        uint256 slot = _getTransientStorageSlot(_requestHash);
        bool isValid;
        assembly {
            let counter := tload(slot)
            // Check if counter is greater than zero
            isValid := gt(counter, 0)
            // if valid, decrement the counter
            if isValid { tstore(slot, sub(counter, 1)) }
        }
        return isValid;
    }

    /// @dev Submit request updates a counter under the request hash in the transient storage
    ///      of the supergroup. This allows an operator to preregister within the same transaction
    ///      in the mint policy a request for minting during a path transfer.
    function _submitRequest(address minter, address group, uint256[] calldata collateral, uint256[] calldata amounts)
        internal
    {
        bytes32 requestHash = PolicyTypes.hashRequest(minter, group, collateral, amounts);
        assembly {
            let currentCounter := tload(requestHash)
            let newCounter := add(currentCounter, 1)
            tstore(requestHash, newCounter)
        }
    }

    /// @dev Simply use the request hash as
    function _getTransientStorageSlot(bytes32 _requestHash) internal pure returns (uint256) {
        return uint256(_requestHash);
    }
}

// src/supergroup/PolicyFingerprints.sol

abstract contract PolicyFingerprints is ISupergroupPolicyFingerprintsErrors {
    // Internal functions

    /// @notice Subtract from fingerprint subtracts the amount from the fingerprint stored
    ///         in transient storage to ensure that no group Circles are sent out during
    ///         acceptance call handlers that were not minted in the same transaction.
    function _subtractFromFingerprint(address _group, uint256 _collateral, uint256 _amount) internal {
        bytes32 fingerprintHash = PolicyTypes.hashFingerprint(_group, _collateral);
        uint256 currentAmount;

        assembly {
            currentAmount := tload(fingerprintHash) // load current amount from transient storage
        }
        // do this outside of assembly to avoid errors on error identifiers
        if (currentAmount < _amount) {
            revert SupergroupFingerprintUnderflow();
        }
        assembly {
            let newAmount := sub(currentAmount, _amount)
            tstore(fingerprintHash, newAmount)
        }
    }

    /// @notice add to fingerprint adds the amount under the collateral in transient storage
    ///         so that during acceptance calls we can deduct from this fingerprint
    ///         before returning minted group circles to the sender
    function _addToFingerprint(address _group, uint256 _collateral, uint256 _amount) internal {
        bytes32 fingerprintHash = PolicyTypes.hashFingerprint(_group, _collateral);
        assembly {
            let currentAmount := tload(fingerprintHash) // load current amount from transient storage slot
            let newAmount := add(currentAmount, _amount) // Add new amount to current amount
            tstore(fingerprintHash, newAmount)
        }
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

// src/operator/CompletionHandler.sol

contract CompletionHandler is ERC1155Holder, ISupergroupOperatorCompletionErrors {
    // Constants

    /// @dev single transient slot where to store expected acceptance call
    bytes32 internal constant EXPECTATION_SLOT = keccak256("EXPECTATION_SLOT");
    /// @dev transient slot to store planned final receiver of funds
    bytes32 internal constant FINAL_RECEIVER_SLOT = keccak256("FINAL_RECEIVER_SLOT");
    /// @dev transient slot where to store expected fee
    bytes32 internal constant FEE_SLOT = keccak256("FEE_SLOT");
    /// @dev transient slot to store fee collection address
    bytes32 internal constant FEE_COLLECTION_ADDRESS_SLOT = keccak256("FEE_COLLECTION_ADDRESS_SLOT");

    /// @dev Domain separator for expecting a single transfer acceptance call
    bytes32 internal constant DOMAIN_SEPARATOR_SINGLE_ACCEPTANCE =
        keccak256("onERC1155ReceivedExpecteduint256 id,uint256 value,bytes data)");
    /// @dev Domain separator for expecting a batch transfer acceptance call
    bytes32 internal constant DOMAIN_SEPARATOR_BATCH_ACCEPTANCE =
        keccak256("onERC1155BatchReceived(uint256[] ids,uint256[] values,bytes data)");

    // Internal functions

    /// @notice Sets expectation for a single acceptance call if no other expectation is active
    /// @param _finalReceiver The address of the final receiver
    /// @param _id The token id being transferred
    /// @param _value The amount being transferred
    /// @param _data Additional data passed with transfer
    /// @param _fee The fee to be charged
    /// @param _feeCollection The address to collect the fee
    function _setExpectationSingleAcceptanceCall(
        address _finalReceiver,
        uint256 _id,
        uint256 _value,
        bytes memory _data,
        uint256 _fee,
        address _feeCollection
    ) internal {
        // Check if slot is empty
        bytes32 currentExpectation;
        // assembly does not like the constants
        bytes32 expectationSlot = EXPECTATION_SLOT;
        bytes32 receiverSlot = FINAL_RECEIVER_SLOT;
        bytes32 feeSlot = FEE_SLOT;
        bytes32 feeCollectionSlot = FEE_COLLECTION_ADDRESS_SLOT;
        assembly {
            currentExpectation := tload(expectationSlot)
        }
        if (currentExpectation != bytes32(0)) {
            revert ExpectationAlreadySet(currentExpectation);
        }

        // Generate and store the acceptance hash
        bytes32 acceptanceHash = _hashSingleAcceptanceCall(_id, _value, _data);

        assembly {
            tstore(expectationSlot, acceptanceHash)
            tstore(receiverSlot, _finalReceiver)
            tstore(feeSlot, _fee)
            tstore(feeCollectionSlot, _feeCollection)
        }
    }

    /// @notice Sets expectation for a batch acceptance call if no other expectation is active
    /// @param _finalReceiver The address of the final receiver
    /// @param _ids Array of token ids being transferred
    /// @param _values Array of amounts being transferred
    /// @param _data Additional data passed with transfer
    /// @param _fee The fee to be charged
    /// @param _feeCollection The address to collect the fee
    function _setExpectationBatchAcceptanceCall(
        address _finalReceiver,
        uint256[] memory _ids,
        uint256[] memory _values,
        bytes memory _data,
        uint256 _fee,
        address _feeCollection
    ) internal {
        // Check if slot is empty
        bytes32 currentExpectation;
        // assembly does not like the constants
        bytes32 slot = EXPECTATION_SLOT;
        bytes32 receiverSlot = FINAL_RECEIVER_SLOT;
        bytes32 feeSlot = FEE_SLOT;
        bytes32 feeCollectionSlot = FEE_COLLECTION_ADDRESS_SLOT;
        assembly {
            currentExpectation := tload(slot)
        }
        if (currentExpectation != bytes32(0)) {
            revert ExpectationAlreadySet(currentExpectation);
        }

        // Generate and store the acceptance hash
        bytes32 acceptanceHash = _hashBatchAcceptanceCall(_ids, _values, _data);

        assembly {
            tstore(slot, acceptanceHash)
            tstore(receiverSlot, _finalReceiver)
            tstore(feeSlot, _fee)
            tstore(feeCollectionSlot, _feeCollection)
        }
    }

    /// @notice Checks if a single acceptance call matches the stored expectation and returns receiver info
    /// @dev Clears stored expectations after successful check
    /// @param _id The token id being transferred
    /// @param _value The amount being transferred
    /// @param _data Additional data passed with transfer
    /// @return address The final receiver address
    /// @return uint256 The fee amount
    /// @return address The fee collection address
    function _checkExpectationSingleAcceptanceCall(uint256 _id, uint256 _value, bytes memory _data)
        internal
        returns (address, uint256, address)
    {
        // Check if expectation exists
        bytes32 currentExpectation;
        address finalReceiver;
        uint256 fee;
        address feeCollection;
        bytes32 expectationSlot = EXPECTATION_SLOT;
        bytes32 receiverSlot = FINAL_RECEIVER_SLOT;
        bytes32 feeSlot = FEE_SLOT;
        bytes32 feeCollectionSlot = FEE_COLLECTION_ADDRESS_SLOT;

        assembly {
            currentExpectation := tload(expectationSlot)
            finalReceiver := tload(receiverSlot)
            fee := tload(feeSlot)
            feeCollection := tload(feeCollectionSlot)
        }

        if (currentExpectation == bytes32(0)) {
            revert NoExpectationSet();
        }

        // Generate hash from actual parameters
        bytes32 acceptanceHash = _hashSingleAcceptanceCall(_id, _value, _data);

        // Verify hash matches expectation
        if (acceptanceHash != currentExpectation) {
            revert ExpectationMismatch(currentExpectation, acceptanceHash);
        }

        // Clear expectation after successful check
        assembly {
            tstore(expectationSlot, 0)
            tstore(receiverSlot, 0)
            tstore(feeSlot, 0)
            tstore(feeCollectionSlot, 0)
        }

        return (finalReceiver, fee, feeCollection);
    }

    /// @notice Checks if a batch acceptance call matches the stored expectation and returns receiver info
    /// @dev Clears stored expectations after successful check
    /// @param _ids Array of token ids being transferred
    /// @param _values Array of amounts being transferred
    /// @param _data Additional data passed with transfer
    /// @return address The final receiver address
    /// @return uint256 The fee amount
    /// @return address The fee collection address
    function _checkExpectationBatchAcceptanceCall(uint256[] memory _ids, uint256[] memory _values, bytes memory _data)
        internal
        returns (address, uint256, address)
    {
        // Check if expectation exists
        bytes32 currentExpectation;
        address finalReceiver;
        uint256 fee;
        address feeCollection;
        bytes32 expectationSlot = EXPECTATION_SLOT;
        bytes32 receiverSlot = FINAL_RECEIVER_SLOT;
        bytes32 feeSlot = FEE_SLOT;
        bytes32 feeCollectionSlot = FEE_COLLECTION_ADDRESS_SLOT;

        assembly {
            currentExpectation := tload(expectationSlot)
            finalReceiver := tload(receiverSlot)
            fee := tload(feeSlot)
            feeCollection := tload(feeCollectionSlot)
        }

        if (currentExpectation == bytes32(0)) {
            revert NoExpectationSet();
        }

        // Generate hash from actual parameters
        bytes32 acceptanceHash = _hashBatchAcceptanceCall(_ids, _values, _data);

        // Verify hash matches expectation
        if (acceptanceHash != currentExpectation) {
            revert ExpectationMismatch(currentExpectation, acceptanceHash);
        }

        // Clear expectation after successful check
        assembly {
            tstore(expectationSlot, 0)
            tstore(receiverSlot, 0)
            tstore(feeSlot, 0)
            tstore(feeCollectionSlot, 0)
        }

        return (finalReceiver, fee, feeCollection);
    }

    /// @notice Hashes parameters for a single token acceptance call
    /// @param _id The token id being transferred
    /// @param _value The amount being transferred
    /// @param _data Additional data passed with transfer
    function _hashSingleAcceptanceCall(uint256 _id, uint256 _value, bytes memory _data)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(DOMAIN_SEPARATOR_SINGLE_ACCEPTANCE, _id, _value, keccak256(_data)));
    }

    /// @notice Hashes parameters for a batch token acceptance call
    /// @param _ids Array of token ids being transferred
    /// @param _values Array of amounts being transferred
    /// @param _data Additional data passed with transfer
    function _hashBatchAcceptanceCall(uint256[] memory _ids, uint256[] memory _values, bytes memory _data)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(DOMAIN_SEPARATOR_BATCH_ACCEPTANCE, _ids, _values, keccak256(_data)));
    }
}

// src/circles/IHub.sol

interface IHub is IHubV2 {
    /// @notice registers group with Circles hub
    function registerGroup(address policy, string calldata name, string calldata symbol, bytes32 metadataDigest)
        external;
    /// @notice trust sets the trust of the caller for the receiver with an expiry time.
    function trust(address _trustReceiver, uint96 _expiry) external;
    /// @notice isTrusted returns true if the expiry time of the trust relation is in the future
    function isTrusted(address truster, address trustee) external returns (bool);
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

// src/projects/ces/helpers/UpgradeableRenounceableProxy.sol

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

// src/operator/SupergroupOperator.sol

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

// src/supergroup/Supergroup.sol

/// @notice Supergroups are opinionated liquidity clusters of valued Circles
///         Supergroups follow a pattern where the group avatar is a contract address
///         that registers itself as the group and acts as a policy at the same time.
///         This pattern allows the group to have transparant behaviour.
///         Furthermore, this supergroup contract is intended to be used as an implementation
///         for a (renounceable) proxy contract, so the constructor blocks
///         the mastercopy deployment, and the proxy should call setup to configure the state.
contract Supergroup is
    MintPolicy,
    PolicyFingerprints,
    OperatorRequests,
    ERC1155Holder,
    CirclesCoreAddresses,
    ISupergroup,
    ISupergroupErrors
{
    // Constants

    /// @notice Max ratio for minting fee or redemption burn ratio
    ///         is set to 2 out of 24, stored as a percentage.
    ///         With 18 decimals; 2/24 * 10**18 = 0,08333.. * 10**18
    uint256 public constant MAX_RATIO = 83333333333333333;
    /// @dev The sentinel value used as the first element in the linked list of operators
    address private constant SENTINEL = address(0x1);

    // Enum

    /// @notice Proxy status keeps an explicit byte about this state instance
    enum ProxyStatus {
        Uninitialised,
        Mastercopy,
        SetUp
    }

    // State variables

    /// @notice Owner address. This is a copied value of ERC1967 ADMIN_SLOT
    ///         if this supergroup mastercopy is consumed by an ERC1067 proxy.
    ///         For simplicity and readability we duplicate owner with ERC1967 admin,
    ///         even if for the intended deployment they are the same address.
    address public owner;
    /// @notice Require an authorized operator to register group mint requests ahead,
    ///         so that advanced checks can be performed by the operator.
    ///         If operators are not required, then direct mint access over the Circles
    ///         hub - either as a direct call or over a path transfer - will all
    ///         be allowed (if the collateral is trusted by the group).
    bool public requireOperator = false;
    /// @notice Return group Circles to sender, when true, will send group Circles
    ///         back to the original sender of a path, if collateral was sent to the group
    ///         as an end-receiver of that path.
    bool public returnGroupCirclesToSender = true;
    /// @notice fee levied upon group minting can be between zero and MAX_FEE (1/12th)
    ///         of the amount minted. Setting the fee to zero disables the fee charge.
    uint256 public mintFee = 0;
    /// @notice fee collection address collects group minting fees when enabled
    address public feeCollection;
    /// @notice redemption burn ratio will burn this ratio (expressed per 10**18). This amount
    ///         will be burnt and is not sent to a collection address.
    uint256 public redemptionBurnRatio = 0;
    /// @notice We take Hub address from core constants, so we need a minimal variable to
    ///         track whether this state (mastercopy or proxy) has been constructed or setup.
    ProxyStatus public proxyStatus = ProxyStatus.Uninitialised;
    /// @notice Mapping of operator addresses to the next operator in the linked list
    mapping(address => address) public operators;

    // Events

    /// @notice Emitted when fee, and collection address updated
    event MintFeeSet(address indexed feeCollection, uint256 fee);

    /// @notice Emitted when the operator requirement is updated
    event OperatorsRequired(bool required);

    /// @notice Emitted when the redemption burn rate is updated
    event RedemptionBurnRateUpdated(uint256 redemptionRate);

    /// @notice Emitted when the flag whether to return group Circles to sender
    ///         is updated
    event ReturnGroupCirclesToSender(bool returnGroupCircles);

    // Modifiers

    /// @notice Only the Circles Hub can call this function
    modifier onlyHub() {
        if (msg.sender != address(hub)) {
            revert SupergroupOnlyHub();
        }
        _;
    }

    /// @notice Only owner can call
    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert SupergroupOnlyOwner();
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
        uint256 _mintFee,
        address _feeCollection,
        uint256 _redemptionBurnRatio,
        address[] calldata _operators,
        string calldata _name,
        string calldata _symbol,
        bytes32 _metadataDigest
    ) public virtual {
        if (proxyStatus != ProxyStatus.Uninitialised) {
            // contract state already initialised.
            revert SupergroupProxyAlreadyInitialised();
        }

        // mark this proxy as set up
        proxyStatus = ProxyStatus.SetUp;

        // set the owner to the same address (msg.sender) as ERC1967 ADMIN_SLOT
        // in Renounceable proxy
        owner = _owner;

        // register group in hub and set the mint policy to this address
        hub.registerGroup(address(this), _name, _symbol, _metadataDigest);

        // authorize operators
        uint256 length = _operators.length;
        for (uint256 i = 0; i < length; i++) {
            // authorize each operator
            _setAuthorizedOperator(_operators[i], true);
        }
        // sanity check
        if (length != countOperators()) {
            revert SupergroupLogicAssertion();
        }

        // set the fee and fee collection address
        _setMintFee(_mintFee, _feeCollection);

        // set redemption burn ratio
        _setRedemptionBurn(_redemptionBurnRatio);
    }

    function trust(address _trustReceiver, uint96 _expiry) external onlyOwner {
        _trust(_trustReceiver, _expiry);
    }

    /// @notice beforeMintPolicy returns true always, unless it is required to act over
    ///         an authorized operator of the supergroup, in which case the operator
    ///         must first have asserted potential requirements and registered an operator
    ///         request before initiating a further calls which trigger the mint policy.
    function beforeMintPolicy(
        address _minter,
        address _group,
        uint256[] calldata _collateral,
        uint256[] calldata _amounts,
        bytes calldata /*_data*/
    ) external override onlyHub returns (bool) {
        // sanity-check that group is this group
        if (_group != address(this)) {
            return false;
        }
        // if minting is required to go via operators, then the operator must have
        // registered its request to initiate a group mint.
        if (requireOperator) {
            // for explicit groupmint from the operator, we could short-cut
            // because the _minter is the operator address,
            // but for the path-triggered groupmint, we need to know whether
            // this request has been vetted by the operator before it reaches the policy.
            // So for clarity, we use the same pattern for both.
            bytes32 requestHash = PolicyTypes.hashRequest(_minter, _group, _collateral, _amounts);
            if (!_validateRequest(requestHash)) {
                return false;
            }
        }
        // next register the executed fingerprints to match them during potential acceptance calls
        uint256 length = _collateral.length;
        for (uint256 i = 0; i < length; i++) {
            _addToFingerprint(_group, _collateral[i], _amounts[i]);
        }
        return true;
    }

    function beforeRedeemPolicy(
        address, /*_operator*/
        address, /*_redeemer*/
        address _group,
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
        // sanity-check that group is this group
        if (_group != address(this)) {
            revert SupergroupLogicAssertion();
        }
        // simplest policy is to return the collateral as the caller requests it in data
        BaseMintPolicyDefinitions.BaseRedemptionPolicy memory redemption =
            abi.decode(_data, (BaseMintPolicyDefinitions.BaseRedemptionPolicy));

        if (redemptionBurnRatio > 0) {
            uint256 length = redemption.redemptionIds.length;
            _burnIds = new uint256[](length);
            _burnValues = new uint256[](length);

            for (uint256 i = 0; i < length; i++) {
                _burnIds[i] = redemption.redemptionIds[i];
                (uint256 returnAmount, uint256 burnAmount) =
                    _splitAmountInReturnAndFee(redemption.redemptionValues[i], redemptionBurnRatio);
                redemption.redemptionValues[i] = returnAmount;
                _burnValues[i] = burnAmount;
            }
        } else {
            _burnIds = new uint256[](0);
            _burnValues = new uint256[](0);
        }

        // standard treasury checks whether the total sums add up to the amount of group Circles redeemed
        // so we can simply decode, update for potential return and burn, and
        // pass the request back to treasury.
        // The redemption will fail if it does not contain (sufficient of) these Circles
        return (redemption.redemptionIds, redemption.redemptionValues, _burnIds, _burnValues);
    }

    /// @notice Authorized operators can register a request to mint group currency
    ///         within the same transaction, by preregistering the parameters of the request
    ///         before initiating the hub either explicitly or over a path.
    ///         This can be called multiple times for multiple group mints along a path
    ///         (eg. different collateral arriving at the group).
    function registerOperatorRequest(
        address _minter,
        address _group,
        uint256[] calldata _collateral,
        uint256[] calldata _amounts
    ) external returns (bool) {
        // todo: this check can now use the locally stored operators - after tests written
        // the operator must be authorized by the supergroup to register request
        if (!hub.isApprovedForAll(address(this), msg.sender)) {
            revert SupergroupOnlyAuthorizedOperator();
        }
        _submitRequest(_minter, _group, _collateral, _amounts);
        return true;
    }

    /// @notice Set authorized operator for this group in Circles hub, and also
    ///         mirror this state in the supergroup, so one can query which operators
    ///         exist for this group (without indexing).
    /// @param _operator Address of the operator
    /// @param _authorized True to authorize, false to revoke
    function setAuthorizedOperator(address _operator, bool _authorized) external onlyOwner {
        _setAuthorizedOperator(_operator, _authorized);
    }

    function setMintFee(uint256 _mintFee, address _feeCollection) external onlyOwner {
        _setMintFee(_mintFee, _feeCollection);
    }

    function setRedemptionBurn(uint256 _burnRedemptionRate) external onlyOwner {
        _setRedemptionBurn(_burnRedemptionRate);
    }

    function setRequireOperators(bool _required) external onlyOwner {
        _requireOperator(_required);
    }

    function setReturnGroupCirclesToSender(bool _returnGroupCircles) external onlyOwner {
        returnGroupCirclesToSender = _returnGroupCircles;

        emit ReturnGroupCirclesToSender(_returnGroupCircles);
    }

    // ERC1155 Acceptance Call handlers

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
        // check the fingerprint whether value has been accounted for during beforeMintPolicy calls
        // If this value is not accounted for in during beforeMintPolicy calls,
        // then this will revert.
        // Note that this is still a "treacherous pattern", and the only recommended pattern is
        // to use operators exclusively.
        //
        // An example of an unintented manipulation that is unavoidable (when explictly
        // not wanting to use operators): imagine the group has 1 gCRC, and aCRC is valid collateral
        // one can call hub.groupMint(1 aCRC), which will register a fingerprint for 1 gCRC for aCRC,
        // but does not trigger an acceptance call; in the same transaction someone can now
        // send 1 aCRC to the group with hub.safeTransfer, and in that acceptance call,
        // if `returnGroupCirclesToSender` is true, this acceptance handler will send the groups'
        // 1 gCRC to the sender, accepting the 1 aCRC (which was necessarily valid collateral).
        //
        // However, this is exactly already possible with a path transfer, because the group trusts
        // aCRC, so an easier way to achieve the same is using a path and swapping the groups' gCRC
        // for aCRC directly.
        _subtractFromFingerprint(address(this), _id, _value);

        if (returnGroupCirclesToSender) {
            if (mintFee > 0) {
                (uint256 returnAmount, uint256 fee) = _splitAmountInReturnAndFee(_value, mintFee);
                // return the return amount to sender
                hub.safeTransferFrom(address(this), _from, _groupId(), returnAmount, _data);
                // send the fee to fee collection address
                hub.safeTransferFrom(address(this), feeCollection, _groupId(), fee, "");
            } else {
                // return the same amount as gCRC to the sender
                hub.safeTransferFrom(address(this), _from, _groupId(), _value, _data);
            }
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
        uint256 length = _ids.length;
        uint256 value = 0;
        for (uint256 i = 0; i < length; i++) {
            // account for all the accepting ids and values
            _subtractFromFingerprint(address(this), _ids[i], _values[i]);
            value += _values[i];
        }
        if (returnGroupCirclesToSender) {
            if (mintFee > 0) {
                (uint256 returnAmount, uint256 fee) = _splitAmountInReturnAndFee(value, mintFee);
                // return the return amount to sender
                hub.safeTransferFrom(address(this), _from, _groupId(), returnAmount, _data);
                // send the fee to fee collection address
                hub.safeTransferFrom(address(this), feeCollection, _groupId(), fee, "");
            } else {
                // return the same amount as gCRC to the sender
                hub.safeTransferFrom(address(this), _from, _groupId(), value, _data);
            }
        }
        return this.onERC1155BatchReceived.selector;
    }

    // External pass-through helpers for owner to act on Circles hub and NameRegistry

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

    function setAdvancedUsageFlag(bytes32 _flag) external onlyOwner {
        hub.setAdvancedUsageFlag(_flag);
    }

    function updateMetadataDigest(bytes32 _metadataDigest) external onlyOwner {
        nameRegistry.updateMetadataDigest(_metadataDigest);
    }

    function registerShortName() external onlyOwner {
        nameRegistry.registerShortName();
    }

    function registerShortNameWithNonce(uint256 _nonce) external onlyOwner {
        nameRegistry.registerShortNameWithNonce(_nonce);
    }

    // External view functions

    /// @notice Gets all authorized operators
    /// @return Array of operator addresses
    function getOperators() external view returns (address[] memory) {
        // Count operators first
        uint256 count = countOperators();

        // Create and populate array
        address[] memory result = new address[](count);
        address current = operators[SENTINEL];
        for (uint256 i = 0; i < count; i++) {
            result[i] = current;
            current = operators[current];
        }

        return result;
    }

    /// @notice Checks if an address is an authorized operator
    /// @param _operator Address to check
    /// @return True if authorized, false otherwise
    function isAuthorizedOperator(address _operator) public view returns (bool) {
        return operators[_operator] != address(0);
    }

    // Public functions

    function countOperators() public view returns (uint256) {
        uint256 count = 0;
        address current = operators[SENTINEL];
        while (current != SENTINEL && current != address(0)) {
            count++;
            current = operators[current];
        }
        return count;
    }

    // Internal functions

    function _trust(address _trustReceiver, uint96 _expiry) internal {
        hub.trust(_trustReceiver, _expiry);
    }

    /// @notice Internal function to add or remove an operator from both the linked list and hub authorization
    /// @dev Uses a linked list structure to maintain operator list, with SENTINEL as guard node
    /// @param _operator The address of the operator to authorize or revoke
    /// @param _authorized True to authorize the operator, false to revoke authorization
    /// @custom:throws SupergroupInvalidOperator if operator is zero address or SENTINEL
    function _setAuthorizedOperator(address _operator, bool _authorized) internal {
        if (_operator == address(0) || _operator == SENTINEL) {
            revert SupergroupInvalidOperator(_operator);
        }

        // Initialize the linked list if it hasn't been already
        if (operators[SENTINEL] == address(0)) {
            operators[SENTINEL] = SENTINEL;
        }

        // Current states
        bool isInLinkedList = operators[_operator] != address(0);
        bool isAuthorizedInHub = hub.isApprovedForAll(address(this), _operator);

        // If desired state matches both current states, no action needed
        if (_authorized == isInLinkedList && _authorized == isAuthorizedInHub) {
            return;
        }

        // Update linked list to match desired state
        if (_authorized && !isInLinkedList) {
            // Add to linked list
            operators[_operator] = operators[SENTINEL];
            operators[SENTINEL] = _operator;
        } else if (!_authorized && isInLinkedList) {
            // Remove from linked list
            _removeOperator(_operator);
        }

        // Update hub authorization if it doesn't match desired state
        if (_authorized != isAuthorizedInHub) {
            hub.setApprovalForAll(_operator, _authorized);
        }
    }

    function _setMintFee(uint256 _mintFee, address _feeCollection) internal {
        if (_mintFee > 0 && _feeCollection == address(0)) {
            // if a fee is levied, collection address cannot be zero
            revert SupergroupInvalidCallingParameters();
        }

        if (_mintFee > MAX_RATIO) {
            revert SupergroupInvalidCallingParameters();
        }

        if (_mintFee > 0) {
            // if a minting fee is set, then operators are required,
            // because explicit hub.groupMint could by-pass the fee
            // when not done over operators.
            _requireOperator(true);
        }

        mintFee = _mintFee;
        feeCollection = _feeCollection;

        emit MintFeeSet(feeCollection, mintFee);
    }

    function _setRedemptionBurn(uint256 _burnRedemptionRate) internal {
        if (_burnRedemptionRate > MAX_RATIO) {
            revert SupergroupInvalidCallingParameters();
        }

        emit RedemptionBurnRateUpdated(redemptionBurnRatio);
    }

    function _requireOperator(bool _required) internal {
        if (_required) {
            if (countOperators() > 0) {
                revert SupergroupMustHaveOperatorsActivated();
            }
        }

        requireOperator = _required;

        emit OperatorsRequired(_required);
    }

    /// @dev Splits a given amount into return and fee based on the provided fee ratio.
    function _splitAmountInReturnAndFee(uint256 _amount, uint256 _feeRatio)
        internal
        pure
        returns (uint256 _returnAmount, uint256 _fee)
    {
        _returnAmount = (_amount * _feeRatio) / 1 ether;
        _fee = _amount - _returnAmount;
    }

    /// @dev Removes an operator from the linked list
    /// @param _operator Address of the operator to remove
    function _removeOperator(address _operator) internal {
        address current = SENTINEL;
        while (operators[current] != SENTINEL) {
            if (operators[current] == _operator) {
                operators[current] = operators[_operator];
                operators[_operator] = address(0);
                return;
            }
            current = operators[current];
        }
        // only check after removal because _operator might not be included
        if (requireOperator && countOperators() == 0) {
            revert SupergroupMustHaveOperatorsActivated();
        }
    }

    function _groupId() internal view returns (uint256) {
        return uint256(uint160(address(this)));
    }
}

// src/projects/ces/CESSupergroup.sol

contract CESSupergroup is Supergroup, CESSupergroupCoreAddresses {
    // State

    /// @notice Service address. The service is limited to trusting (or untrusting) avatars.
    address public service;

    /// @notice Track service address changes
    /// @param newService New service address.
    event ServiceUpdated(address indexed newService);

    // Modifiers

    /// @notice Only owner or service can call
    modifier onlyOwnerOrService() {
        if (msg.sender != owner && msg.sender != service) {
            revert SupergroupOnlyOwnerOrService();
        }
        _;
    }

    // Constructor

    function setup(
        address _owner,
        address _service,
        uint256 _mintFee,
        address _feeCollection,
        uint256 _redemptionBurnRate,
        address[] calldata _operators,
        string calldata _name,
        string calldata _symbol,
        bytes32 _metadataDigest
    ) external {
        // first call setup on Supergroup
        super.setup(_owner, _mintFee, _feeCollection, _redemptionBurnRate, _operators, _name, _symbol, _metadataDigest);

        if (_service == address(0)) {
            revert SupergroupInvalidCallingParameters();
        }

        // set the service key
        service = _service;
    }

    // External functions

    /// @notice Trust or untrust a batch of Backers.
    /// @param _backers Array of backer addresses to trust/untrust
    /// @param _expiry Trust expiry timestamp. If >= current timestamp, trust backers with active LBPs. If < current timestamp, untrust currently trusted backers
    function trustBatch(address[] calldata _backers, uint96 _expiry) external onlyOwnerOrService {
        uint256 length = _backers.length;
        address backer;
        // current block timestamp is an edge-case, so include it in the active
        // check for active LBP.
        // when expiry is now or a future time, this implies establishing trust
        // so we perform an explicit check on the launchpad whether these addresses
        // have an active LBP
        if (_expiry >= block.timestamp) {
            for (uint256 i = 0; i < length; i++) {
                backer = _backers[i];
                // skip any backers that are not active (yet/anymore)
                if (launchpad.isActiveLBP(backer)) {
                    hub.trust(backer, _expiry);
                }
            }
        } else {
            // hub will update older expiry times to current block.timestamp, so preventatively
            // already update to current timestamp
            _expiry = uint96(block.timestamp);
            // if expiry is explicitly set in the past, then that means to untrust the backers
            // however, hub will set trust to current block.timestamp for expiry, so to avoid that
            // we trust a previously never-trusted backer for one block,
            // first check whether the backer is currently trusted;
            // ie. that meant the group has previously trusted the backer via a valid path
            //     so setting trust to expire after this block is untrusting;
            //     and doing nothing means the expiry for this backer was already 0 or < timestamp
            for (uint256 i = 0; i < length; i++) {
                backer = _backers[i];
                if (hub.isTrusted(address(this), backer)) {
                    hub.trust(backer, _expiry);
                }
            }
        }
    }

    /// @notice Change the service address. Service account is able to trust/untrust backers alongside the owner.
    /// @param _service Updated service address to give trustBatch privilege to.
    /// @dev The service account must be a non-zero address. Only owner can change the service address.
    function setService(address _service) external onlyOwner {
        if (_service == address(0)) {
            revert SupergroupInvalidCallingParameters();
        }
        service = _service;
        emit ServiceUpdated(service);
    }
}

// src/projects/ces/helpers/CESSupergroupDeployer.sol

contract CESSupergroupDeployer {
    // Constants

    // /// @dev Callprefix to setup function of CESSupergroup
    // ///  function setup(address _service, uint256 _fee, address _feeCollection,
    // ///      uint256 _redemptionBurnRate, address[] calldata _operators,
    // ///      string calldata _name, string calldata _symbol, bytes32 _metadataDigest) external
    // bytes4 private constant SUPERGROUP_SETUP_CALLPREFIX =
    //     bytes4(keccak256("setup(address,uint256,address,uint256,address[],string,string,bytes32)"));

    // State variables

    /// @notice address of the deployed mastercopy for the CES Supergroup
    CESSupergroup public masterCopyCESSupergroup;

    // Constructor

    constructor() {
        // deploy a master copy for CES Supergroup
        masterCopyCESSupergroup = new CESSupergroup();
    }

    // External functions

    /// @notice Create CES Supergroup for caller
    function createCESSupergroup(
        address _service,
        uint256 _mintFee,
        address _feeCollection,
        uint256 _redemptionBurnRate,
        address[] calldata _operators,
        string calldata _name,
        string calldata _symbol,
        bytes32 _metadataDigest
    ) external returns (address) {
        // create a proxy with the i
        bytes memory data = abi.encodeWithSignature(
            "setup(address,address,uint256,address,uint256,address[],string,string,bytes32)",
            msg.sender,
            _service,
            _mintFee,
            _feeCollection,
            _redemptionBurnRate,
            _operators,
            _name,
            _symbol,
            _metadataDigest
        );

        UpgradeableRenounceableProxy proxy =
            new UpgradeableRenounceableProxy(msg.sender, address(masterCopyCESSupergroup), data);

        return address(proxy);
    }
}

