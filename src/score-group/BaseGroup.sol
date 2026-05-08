// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import {BaseTreasury} from "src/base-group/BaseTreasury.sol";
import {BaseMintHandler} from "src/base-group/BaseMintHandler.sol";
import {IHub} from "src/base-group/interfaces/IHub.sol";
import {ILiftERC20} from "src/base-group/interfaces/ILiftERC20.sol";
import {INameRegistry} from "src/base-group/interfaces/INameRegistry.sol";
import {IMembershipCondition} from "src/membership-conditions/IMembershipCondition.sol";

/// @title BaseGroup
/// @notice A base contract for Circles Hub v2 group creation and membership management.
/// @dev This contract allows the deployment of a treasury, setup of minting policy/handler,
///      and management of membership conditions for group-based trust relationships.
contract BaseGroup {
    // =================================================
    //                       ERRORS
    // =================================================

    /// @notice Thrown when a function is called by an account other than the Hub.
    error OnlyHub();

    /// @notice Thrown when a function is called by an account other than the owner.
    error OnlyOwner();

    /// @notice Thrown when a function is called by an account other than the owner or service.
    error OnlyOwnerOrService();

    /// @notice Thrown when calling parameters are invalid (e.g., zero addresses).
    error InvalidCallingParameters();

    /// @notice Thrown when the maximum number of membership conditions is reached.
    error MaxConditionsActive();

    /// @notice Thrown when a membership condition check fails for a given member and condition.
    /// @param member The address of the member that failed the check.
    /// @param failedCondition The address of the failing membership condition contract.
    error MembershipCheckFailed(address member, address failedCondition);

    // =================================================
    //                    EVENTS
    // =================================================

    /// @notice Event emitted when the owner is updated.
    /// @param owner New owner address.
    event OwnerUpdated(address indexed owner);

    /// @notice Event emitted when the service address is updated.
    /// @param newService New service address.
    event ServiceUpdated(address indexed newService);

    /// @notice Event emitted when the fee collection address is updated.
    /// @param feeCollection New fee collection address.
    event FeeCollectionUpdated(address indexed feeCollection);

    /// @notice Event emitted when a membership condition is enabled or disabled.
    /// @param condition Address of the membership condition contract.
    /// @param enabled Whether the condition was enabled (true) or disabled (false).
    event MembershipConditionEnabled(address indexed condition, bool enabled);

    // =================================================
    //                     CONSTANTS
    // =================================================

    /// @notice Circles v2 Hub.
    IHub public constant HUB = IHub(address(0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8));

    /// @notice Circles v2 LiftERC20 contract.
    ILiftERC20 public constant LIFT_ERC20 = ILiftERC20(address(0x5F99a795dD2743C36D63511f0D4bc667e6d3cDB5));

    /// @notice Circles v2 Name Registry contract.
    INameRegistry public constant NAME_REGISTRY = INameRegistry(address(0xA27566fD89162cC3D40Cb59c87AAaA49B85F3474));

    /// @notice Address of the base mint policy that applies to newly created groups.
    address public constant BASE_MINT_POLICY = address(0xCDFc5135AEC0aFbf102C108e7f5C8A88C6112842);

    /// @notice The group's treasury contract, deployed during initialization.
    /// @dev Immutable once set in the constructor.
    BaseTreasury public immutable BASE_TREASURY;

    /// @notice The contract that mirrors trust relationships and serves group mints via transitive transfers.
    /// @dev Deployed during group creation.
    BaseMintHandler public immutable BASE_MINT_HANDLER;

    /// @notice The maximum number of membership conditions allowed.
    uint256 public constant MAX_CONDITIONS = 10;

    // =================================================
    //                    STATE
    // =================================================

    /// @notice The owner address of this group.
    /// @dev The owner has privileged access to certain administrative functions.
    address public owner;

    /// @notice The service address with shared privileges for membership management.
    /// @dev Either `owner` or `service` can call certain membership functions.
    address public service;

    /// @notice The fee collection address where any group fees are sent.
    address public feeCollection;

    /// @notice An array of addresses defining membership conditions.
    address[] public membershipConditions;

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

    /// @notice Ensures the function is only called by the Owner or Service.
    /// @dev Reverts if `msg.sender` is neither.
    modifier onlyOwnerOrService() {
        if (msg.sender != owner && msg.sender != service) {
            revert OnlyOwnerOrService();
        }
        _;
    }

    // =================================================
    //                  CONSTRUCTOR
    // =================================================

    /// @notice Deploys a new BaseGroup along with treasury and mint handler, and initializes membership conditions.
    /// @param _owner The address to assign as the owner of the group.
    /// @param _service The address for the service role that shares membership admin privileges with the owner.
    /// @param _feeCollection The address for the fee collection role for this group.
    /// @param _initialConditions An array of membership condition contract addresses to enable immediately.
    /// @param _name The name for the group (also used for treasury/mint handler deployment and registration).
    /// @param _symbol The symbol for the group.
    /// @param _metadataDigest The IPFS or other off-chain data digest used for metadata references (also used for treasury/mint handler).
    constructor(
        address _owner,
        address _service,
        address _feeCollection,
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
        _setFeeCollection(_feeCollection);

        // Set initial membership conditions.
        for (uint256 i; i < _initialConditions.length;) {
            _addMembershipCondition(_initialConditions[i]);
            unchecked {
                ++i;
            }
        }

        // Deploy the treasury for this group.
        BASE_TREASURY = new BaseTreasury(address(HUB), address(NAME_REGISTRY), address(this), _name, _metadataDigest);

        // Register the group in the Hub with the base mint policy and the newly deployed treasury.
        HUB.registerCustomGroup(BASE_MINT_POLICY, address(BASE_TREASURY), _name, _symbol, _metadataDigest);

        // Registers a short name for this group in the Name Registry without a nonce, limited by 250_000 gas.
        try NAME_REGISTRY.registerShortName{gas: 250_000}() {} catch {}

        // Deploy ERC20s for the group via the LIFT_ERC20 contract.
        address demurrage = LIFT_ERC20.ensureERC20(address(this), uint8(0));
        address inflationary = LIFT_ERC20.ensureERC20(address(this), uint8(1));

        // Deploy the base mint handler, which mirrors group trust.
        BASE_MINT_HANDLER = new BaseMintHandler(
            address(HUB), address(NAME_REGISTRY), address(this), demurrage, inflationary, _name, _metadataDigest
        );
    }

    // =================================================
    //               EXTERNAL FUNCTIONS
    // =================================================

    /// @notice Change the owner address. Only the current owner can change ownership.
    /// @param _owner The new owner address to set.
    function setOwner(address _owner) external onlyOwner {
        _setOwner(_owner);
    }

    /// @notice Change the service address, which shares membership admin privileges with the owner.
    /// @param _service The new service address to set.
    /// @dev Only callable by the owner. Reverts if `_service` is the zero address.
    function setService(address _service) external onlyOwner {
        if (_service == address(0)) {
            revert InvalidCallingParameters();
        }
        _setService(_service);
    }

    /// @notice Change the fee collection address for this group.
    /// @param _feeCollection The new fee collection address.
    /// @dev Only the owner can call this. Reverts if `_feeCollection` is the zero address.
    function setFeeCollection(address _feeCollection) external onlyOwner {
        if (_feeCollection == address(0)) {
            revert InvalidCallingParameters();
        }
        _setFeeCollection(_feeCollection);
    }

    /// @notice Enable or disable a membership condition contract.
    /// @param _condition The address of the membership condition contract.
    /// @param _enabled Whether to enable (true) or disable (false) the condition.
    /// @dev Only the owner can call this function.
    function setMembershipCondition(address _condition, bool _enabled) external onlyOwner {
        if (_enabled) {
            _addMembershipCondition(_condition);
        } else {
            _removeMembershipCondition(_condition);
        }
        emit MembershipConditionEnabled(_condition, _enabled);
    }

    /// @notice Explicitly set trust for a single address in this group (with no membership checks).
    /// @param _trustReceiver The address to trust.
    /// @param _expiry The timestamp when trust expires. If >= current timestamp, sets trust; if < current timestamp, untrusts.
    /// @dev Only the owner can call this function.
    function trust(address _trustReceiver, uint96 _expiry) external onlyOwner {
        _trust(_trustReceiver, _expiry);
    }

    /// @notice Trust or untrust a batch of members with membership condition checks (if trusting).
    /// @param _members Array of member addresses to trust or untrust.
    /// @param _expiry If >= current timestamp, new trust is established. If < current timestamp, any currently trusted members will be untrusted.
    /// @dev Only the owner or service can call this function. Reverts if membership conditions fail for any address.
    function trustBatchWithConditions(address[] memory _members, uint96 _expiry) public virtual onlyOwnerOrService {
        bool doTrust = _expiry >= block.timestamp;
        address member;
        for (uint256 i; i < _members.length;) {
            member = _members[i];
            if (doTrust) {
                (bool passed, address failedCondition) = _checkMembershipConditions(member);
                if (!passed) {
                    revert MembershipCheckFailed(member, failedCondition);
                }
                _trust(member, _expiry);
            } else {
                // If expiry is in the past, we only untrust members that are currently trusted.
                if (HUB.isTrusted(address(this), member)) {
                    _trust(member, _expiry);
                }
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Updates the metadata digest for this group and its organizations in the Name Registry.
    /// @param _metadataDigest The new off-chain metadata digest (e.g., IPFS hash).
    /// @dev Only callable by the owner.
    function updateMetadataDigest(bytes32 _metadataDigest) external onlyOwner {
        NAME_REGISTRY.updateMetadataDigest(_metadataDigest);
        BASE_TREASURY.updateMetadataDigest(_metadataDigest);
        BASE_MINT_HANDLER.updateMetadataDigest(_metadataDigest);
    }

    /// @notice Registers a short name for this group in the Name Registry with a specified nonce, if failed during deployment.
    /// @param _nonce A user-provided nonce to handle name collisions or concurrency issues.
    /// @dev Only callable by the owner.
    function registerShortNameWithNonce(uint256 _nonce) external onlyOwner {
        NAME_REGISTRY.registerShortNameWithNonce(_nonce);
    }

    // =================================================
    //                 VIEW FUNCTIONS
    // =================================================

    /// @notice Returns the array of membership condition addresses.
    /// @return An array of addresses corresponding to active membership conditions.
    function getMembershipConditions() external view returns (address[] memory) {
        return membershipConditions;
    }

    // =================================================
    //               INTERNAL FUNCTIONS
    // =================================================

    /// @notice Internal function to set the owner and emit an event.
    /// @param _owner The new owner address.
    function _setOwner(address _owner) internal {
        owner = _owner;
        emit OwnerUpdated(_owner);
    }

    /// @notice Internal function to set the service address and emit an event.
    /// @param _service The new service address.
    function _setService(address _service) internal {
        service = _service;
        emit ServiceUpdated(_service);
    }

    /// @notice Internal function to set the fee collection address and emit an event.
    /// @param _feeCollection The new fee collection address.
    function _setFeeCollection(address _feeCollection) internal {
        feeCollection = _feeCollection;
        emit FeeCollectionUpdated(_feeCollection);
    }

    /// @notice Internal function to add a membership condition, if not already present.
    /// @param _condition The address of the membership condition contract to add.
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
                // Avoid double entry of conditions.
                return;
            }
            unchecked {
                ++i;
            }
        }
        membershipConditions.push(_condition);
    }

    /// @notice Internal function to remove a membership condition, if present.
    /// @param _condition The address of the membership condition contract to remove.
    function _removeMembershipCondition(address _condition) internal {
        if (_condition == address(0)) {
            return;
        }
        uint256 length = membershipConditions.length;
        for (uint256 i; i < length;) {
            if (membershipConditions[i] == _condition) {
                if (i != length - 1) {
                    // Swap the condition with the last element, if not already last.
                    membershipConditions[i] = membershipConditions[length - 1];
                }
                membershipConditions.pop();
                return;
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Internal function that establishes or revokes trust for a single address through the Hub and mirrors that trust in the mint handler.
    /// @param _trustReceiver The address of the member to trust or untrust.
    /// @param _expiry The timestamp when trust expires (if >= current time). If < current time, trust is revoked.
    function _trust(address _trustReceiver, uint96 _expiry) internal {
        HUB.trust(_trustReceiver, _expiry);
        BASE_MINT_HANDLER.mirrorTrust(_trustReceiver, _expiry);
    }

    /// @notice Checks whether an address passes all active membership conditions.
    /// @param _avatar The address to be checked.
    /// @return (bool, address) A tuple where the first element indicates overall pass/fail,
    ///         and the second element is the address of the failing condition, or address(0) if all pass.
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
        return (true, address(0));
    }
}
