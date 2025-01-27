// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "circles-contracts-v2/groups/BaseMintPolicy.sol";
import "src/errors/Errors.sol";
import "src/circles/Core.sol";
import "src/CoreMembersGroup/ICMAncillary.sol";

contract CoreMembersGroup is MintPolicy, CirclesCoreAddresses, ICMGroupErrors {
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
