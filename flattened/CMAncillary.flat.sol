// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.24 >=0.8.28 ^0.8.20;

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

