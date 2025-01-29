// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "circles-contracts-v2/groups/BaseMintPolicy.sol";
import "src/errors/Errors.sol";
import "src/circles/Core.sol";
import "src/CoreMembersGroup/ICMGMintHandler.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {CoreMembersGroupStorage} from "src/CoreMembersGroup/CoreMembersGroupStorage.sol";

contract CoreMembersGroup is
    Initializable,
    CoreMembersGroupStorage,
    MintPolicy,
    CirclesCoreAddresses,
    ICMGroupErrors
{
    // Events

    /// @notice Track service address changes
    /// @param newService New service address.
    event ServiceUpdated(address indexed newService);

    /// @notice Track mintHandler contract changes
    /// @param newMintHandler New mintHandler contract address.
    event MintHandlerUpdated(address indexed newMintHandler);

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
        if (msg.sender != _state().owner) {
            revert CMGroupOnlyOwner();
        }
        _;
    }

    /// @notice Only owner or service can call
    modifier onlyOwnerOrService() {
        if (msg.sender != _state().owner && msg.sender != _state().service) {
            revert CMGroupOnlyOwnerOrService();
        }
        _;
    }

    // Constructor

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // Setup

    function setup(
        address _owner,
        address _mintHandler,
        address _service,
        string calldata _name,
        string calldata _symbol,
        bytes32 _metadataDigest
    ) external virtual initializer {
        if (_owner == address(0)) {
            revert CMGroupInvalidCallingParameters();
        }
        // set the owner explicitly
        // (recommended same value as ERC1967 ADMIN SLOT)
        _state().owner = _owner;
        // set the mintHandler address, can be zero address
        _state().mintHandler = _mintHandler;
        // set the service key, can initially be zero address
        _state().service = _service;
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
        _state().service = _service;
        emit ServiceUpdated(_service);
    }

    /// @notice Change the mintHandler contract address. MintHandler contract helps
    ///         automate path minting/redemptions.
    /// @param _mintHandler Updated mintHandler contract address.
    /// @dev The mintHandler contract can be zero address. Only owner can change the mintHandler contract.
    function setMintHandler(address _mintHandler) external onlyOwner {
        _state().mintHandler = _mintHandler;
        emit MintHandlerUpdated(_mintHandler);
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

    // View functions

    /// @notice Owner address. This is a copied value of ERC1967 ADMIN_SLOT
    ///         if this group mastercopy is consumed by an ERC1967 proxy.
    ///         For simplicity and readability we duplicate owner with ERC1967 admin,
    ///         even if for the intended deployment they are the same address.
    function owner() external view returns (address) {
        return _state().owner;
    }

    /// @notice stores the mintHandler for the CM Group to assist with
    ///         automatic path mints and redemptions for the group.
    function mintHandler() external view returns (address) {
        return _state().mintHandler;
    }

    /// @notice Service address. The service is limited to trusting (or untrusting) avatars.
    function service() external view returns (address) {
        return _state().service;
    }

    // Internal functions

    /// @notice Internal trust function that trusts a single core member
    ///         through the hub. If mintHandler contract is set,
    ///         also mirrors the trust there.
    /// @param _trustReceiver Address of core member to trust
    /// @param _expiry Timestamp when trust expires. If >= current time,
    ///         establishes trust. If < current time, serves to untrust.
    function _trust(address _trustReceiver, uint96 _expiry) internal {
        hub.trust(_trustReceiver, _expiry);
        address mintHandler_ = _state().mintHandler;
        if (mintHandler_ != address(0)) {
            ICMGMintHandler(mintHandler_).mirrorTrust(_trustReceiver, _expiry);
        }
    }
}
