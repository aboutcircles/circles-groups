// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import {BaseTreasury} from "src/base-group/BaseTreasury.sol";
import {BaseMintHandler} from "src/base-group/BaseMintHandler.sol";
import {IHub} from "src/base-group/interfaces/IHub.sol";
import {ILiftERC20} from "src/base-group/interfaces/ILiftERC20.sol";
import {INameRegistryExtended} from "src/base-group/interfaces/INameRegistry.sol";
import {IMembershipCondition} from "src/membership-conditions/IMembershipCondition.sol";

contract BaseGroup {
    // =================================================
    //                       ERRORS
    // =================================================

    /// @notice Thrown when a function is called by an account other than the Hub.
    error OnlyHub();

    /// @notice Thrown when a function is called by an account other than the owner.
    error OnlyOwner();

    error OnlyOwnerOrService();

    error InvalidCallingParameters();

    error MaxConditionsActive();

    error MembershipCheckFailed(address member, address failedCondition);

    // =================================================
    //                     CONSTANTS
    // =================================================

    /// @notice Circles Hub v2.
    IHub public constant HUB = IHub(address(0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8));
    /// @notice Circles v2 LiftERC20 contract.
    ILiftERC20 public constant LIFT_ERC20 = ILiftERC20(address(0x5F99a795dD2743C36D63511f0D4bc667e6d3cDB5));
    /// @notice Circles v2 Name Registry contract.
    INameRegistryExtended public constant NAME_REGISTRY =
        INameRegistryExtended(address(0xA27566fD89162cC3D40Cb59c87AAaA49B85F3474));

    address public constant BASE_MINT_POLICY = address(0xCDFc5135AEC0aFbf102C108e7f5C8A88C6112842);
    address public immutable BASE_TREASURY;
    BaseMintHandler public immutable BASE_MINT_HADLER;

    /// @notice The maximum number of membership conditions allowed.
    uint256 public constant MAX_CONDITIONS = 10;

    // =================================================
    //                    STATE
    // =================================================

    address public owner;
    address public service;
    address public feeCollection;
    address[] public membershipConditions;

    // =================================================
    //                    EVENTS
    // =================================================

    /// @notice Event emitted when owner is set during setup
    /// @param owner New owner address.
    event OwnerUpdated(address indexed owner);

    /// @notice Track service address changes
    /// @param newService New service address.
    event ServiceUpdated(address indexed newService);

    /// @notice Event emitted when fee collection address is updated
    /// @param feeCollection New fee collection address
    event FeeCollectionUpdated(address indexed feeCollection);

    /// @notice Event emitted when membership condition is enabled/disabled
    /// @param condition Address of the membership condition contract
    /// @param enabled Whether the condition was enabled or disabled
    event MembershipConditionEnabled(address indexed condition, bool enabled);

    // =================================================
    //                    MODIFIERS
    // =================================================

    /// @notice Ensures the function is only called by the Owner.
    /// @dev Reverts if `msg.sender` is not the Owner.
    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert OnlyOwner();
        }
        _;
    }

    /// @notice Only owner or service can call
    modifier onlyOwnerOrService() {
        if (msg.sender != owner && msg.sender != service) {
            revert OnlyOwnerOrService();
        }
        _;
    }

    // Constructor

    constructor(
        address _owner,
        address _service,
        address[] memory _initialConditions,
        string memory _name,
        string memory _symbol,
        bytes32 _metadataDigest
    ) {
        if (_owner == address(0)) {
            revert InvalidCallingParameters();
        }
        _setOwner(_owner);
        _setService(_service);
        // set fee collection to be by default the owner Question: why?
        feeCollection = _owner;

        // set initial conditions
        for (uint256 i; i < _initialConditions.length;) {
            _addMembershipCondition(_initialConditions[i]);
            unchecked {
                ++i;
            }
        }

        // deploy treasury
        BASE_TREASURY = address(new BaseTreasury(address(HUB), address(this), _name));

        // register group in hub
        HUB.registerCustomGroup(BASE_MINT_POLICY, BASE_TREASURY, _name, _symbol, _metadataDigest);
        // deploy ERC20s
        address demurrage = LIFT_ERC20.ensureERC20(address(this), uint8(0));
        address inflationary = LIFT_ERC20.ensureERC20(address(this), uint8(1));

        // deploy mint handler
        BASE_MINT_HADLER = new BaseMintHandler(address(HUB), address(this), demurrage, inflationary, _name);
    }

    // External functions

    /// @notice Change the service address. Service account is able to trust/untrust group members
    ///         alongside the owner.
    /// @param _service Updated service address to give trustBatch privilege to.
    /// @dev The service account must be a non-zero address. Only owner can change the service address.
    function setService(address _service) external onlyOwner {
        if (_service == address(0)) {
            revert InvalidCallingParameters();
        }
        _setService(_service);
    }

    /// @notice Change the owner address. Only the current owner can change ownership.
    /// @param _owner New owner address
    function setOwner(address _owner) external onlyOwner {
        _setOwner(_owner);
    }

    /// @notice Enable or disable a membership condition contract
    /// @param _condition Address of membership condition contract
    /// @param _enabled Whether to enable (true) or disable (false) the condition
    function setMembershipCondition(address _condition, bool _enabled) external onlyOwner {
        if (_enabled) {
            _addMembershipCondition(_condition);
        } else {
            _removeMembershipCondition(_condition);
        }
        emit MembershipConditionEnabled(_condition, _enabled);
    }

    /// @notice Change the fee collection address
    /// @param _feeCollection New fee collection address
    /// @dev The fee collection address must not be zero. Only owner can change.
    function setFeeCollection(address _feeCollection) external onlyOwner {
        if (_feeCollection == address(0)) {
            revert InvalidCallingParameters();
        }
        feeCollection = _feeCollection;
        emit FeeCollectionUpdated(_feeCollection);
    }

    /// @notice trust allows the owner to explicitly set trust relations
    ///         for the group.
    function trust(address _trustReceiver, uint96 _expiry) external onlyOwner {
        _trust(_trustReceiver, _expiry);
    }

    /// @notice Trust or untrust a batch of group members with membership condition checks.
    /// @param _members Array of member addresses to trust/untrust
    /// @param _expiry Trust expiry timestamp. If >= current timestamp, trust member.
    ///        If < current timestamp, untrust only currently trusted members (to avoid
    ///        accidentally trusting new members for a single block).
    function trustBatchWithConditions(address[] memory _members, uint96 _expiry) public virtual onlyOwnerOrService {
        address member;
        // current block timestamp is an edge-case,
        // when expiry is now or a future time, this implies establishing trust
        // so we perform an explicit check on the launchpad whether these addresses
        // have an active LBP
        if (_expiry >= block.timestamp) {
            for (uint256 i; i < _members.length;) {
                member = _members[i];
                (bool passed, address failedCondition) = _checkMembershipConditions(member);
                if (!passed) {
                    revert MembershipCheckFailed(member, failedCondition);
                }
                _trust(member, _expiry);
                unchecked {
                    ++i;
                }
            }
        } else {
            // hub will update older expiry times to current block.timestamp, so preventatively
            // already update to current timestamp
            _expiry = uint96(block.timestamp);
            // if expiry is explicitly set in the past, then that means to untrust the members
            // however, hub will set trust to current block.timestamp for expiry, so to avoid that
            // we trust a previously never-trusted members for one block,
            // first check whether the member is currently trusted;
            for (uint256 i; i < _members.length;) {
                member = _members[i];
                if (HUB.isTrusted(address(this), member)) {
                    _trust(member, _expiry);
                }
                unchecked {
                    ++i;
                }
            }
        }
    }

    /// @notice Sets advanced usage flags for this group in the Hub
    /// @param _flag Advanced usage flag value to set
    function setAdvancedUsageFlag(bytes32 _flag) external onlyOwner {
        HUB.setAdvancedUsageFlag(_flag);
    }

    /// @notice Updates the metadata digest for this group in the name registry
    /// @param _metadataDigest New metadata digest value
    function updateMetadataDigest(bytes32 _metadataDigest) external onlyOwner {
        NAME_REGISTRY.updateMetadataDigest(_metadataDigest);
    }

    /// @notice Registers a short name for this group in the name registry
    function registerShortName() external onlyOwner {
        NAME_REGISTRY.registerShortName();
    }

    /// @notice Registers a short name for this group with a specified nonce
    /// @param _nonce Nonce value to use for short name registration
    function registerShortNameWithNonce(uint256 _nonce) external onlyOwner {
        NAME_REGISTRY.registerShortNameWithNonce(_nonce);
    }

    // View functions

    /// @notice Returns the array of membership condition addresses
    function getMembershipConditions() external view returns (address[] memory) {
        return membershipConditions;
    }

    // Internal functions

    function _setOwner(address _owner) internal {
        owner = _owner;
        emit OwnerUpdated(_owner);
    }

    function _setService(address _service) internal {
        service = _service;
        emit ServiceUpdated(_service);
    }

    function _addMembershipCondition(address _condition) internal {
        if (_condition == address(0)) {
            return;
        }
        uint256 length = membershipConditions.length;
        if (length >= MAX_CONDITIONS) {
            revert MaxConditionsActive();
        }
        for (uint256 i; i < length;) {
            if (membershipConditions[i] == _condition) {
                // avoid double entry of conditions, silently return
                return;
            }
            unchecked {
                ++i;
            }
        }
        membershipConditions.push(_condition);
    }

    function _removeMembershipCondition(address _condition) internal {
        if (_condition == address(0)) {
            return;
        }
        uint256 length = membershipConditions.length;
        for (uint256 i; i < length;) {
            if (membershipConditions[i] == _condition) {
                if (i != length - 1) {
                    // Swap the condition with the last element, if not already last
                    membershipConditions[i] = membershipConditions[length - 1];
                }
                // Remove the last element
                membershipConditions.pop();
                return;
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Internal trust function that trusts a single member
    ///         through the hub and mirrors the mintHandler trust.
    /// @param _trustReceiver Address of member to trust
    /// @param _expiry Timestamp when trust expires. If >= current time,
    ///         establishes trust. If < current time, serves to untrust.
    function _trust(address _trustReceiver, uint96 _expiry) internal {
        HUB.trust(_trustReceiver, _expiry);
        BASE_MINT_HADLER.mirrorTrust(_trustReceiver, _expiry);
    }

    function _checkMembershipConditions(address _avatar) internal returns (bool, address) {
        uint256 length = membershipConditions.length;
        for (uint256 i; i < length;) {
            if (!IMembershipCondition(membershipConditions[i]).passesMembershipCondition(_avatar)) {
                return (false, membershipConditions[i]);
            }
            unchecked {
                ++i;
            }
        }
        // passed all membership conditions,
        // true by default if no conditions set
        return (true, address(0));
    }
}
