// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "circles-contracts-v2/groups/BaseMintPolicy.sol";
import "src/errors/Errors.sol";
import "src/circles/Core.sol";
import "src/core-members-group/ICoreMembersGroup.sol";
import "src/core-members-group/ICMGMintHandler.sol";
import "src/core-members-group/ICMGRedemptionHandler.sol";
import "src/membership-conditions/IMembershipCondition.sol";

contract CoreMembersGroup is MintPolicy, CirclesCoreAddresses, ICoreMembersGroup, ICMGroupErrors {
    // Structs

    /// Stateful struct inherited from upgradeable contracts to minimise code changes
    /// from the archived development version found in /helpers
    struct State {
        address owner;
        address mintHandler;
        address redemptionHandler;
        address service;
        uint256 minimalDeposit;
        address feeCollection;
        // CirclesCore circlesCore;
        IHub hub;
        IStandardTreasury standardTreasury;
        INameRegistryExtended nameRegistry;
        IERC20Lift erc20Lift;
        address[] membershipConditions;
    }

    // Constants

    /// @notice maximum minimal amount for deposit to avoid inefficient redemption bookkeeping.
    uint256 public constant MAX_DEPOSIT_AMOUNT_MINIMUM = 10 ** 15;

    /// @notice The maximum number of membership conditions allowed.
    uint256 public constant MAX_CONDITIONS = 10;

    // State

    /// @notice store the state variables, a pattern adopted to stay close to the
    /// upgradeable CMG version
    State public state;

    // Events

    /// @notice Track service address changes
    /// @param newService New service address.
    event ServiceUpdated(address indexed newService);

    /// @notice Track mintHandler contract changes
    /// @param newMintHandler New mintHandler contract address.
    event MintHandlerUpdated(address indexed newMintHandler);

    /// @notice Track redemptionHandler contract changes
    /// @param newRedemptionHandler New redemptionHandler contract address.
    event RedemptionHandlerUpdated(address indexed newRedemptionHandler);

    /// @notice Event emitted when minimal deposit amount is updated
    /// @param minimalDeposit New minimal deposit value.
    event MinimalDepositUpdated(uint256 minimalDeposit);

    /// @notice Event emitted when owner is set during setup
    /// @param owner New owner address.
    event OwnerSet(address indexed owner);

    /// @notice Event emitted when membership condition is enabled/disabled
    /// @param condition Address of the membership condition contract
    /// @param enabled Whether the condition was enabled or disabled
    event MembershipConditionEnabled(address indexed condition, bool enabled);

    /// @notice Event emitted when fee collection address is updated
    /// @param feeCollection New fee collection address
    event FeeCollectionUpdated(address indexed feeCollection);

    // Modifiers

    /// @notice Only the Circles Hub can call this function
    modifier onlyHub() {
        if (msg.sender != address(state.hub)) {
            revert CMGroupOnlyHub();
        }
        _;
    }

    /// @notice Only the Circles Hub or group Treasury can call this function
    modifier onlyHubOrTreasury() {
        if (msg.sender != address(state.hub) && msg.sender != address(state.standardTreasury)) {
            revert CMGroupOnlyHubOrTreasury();
        }
        _;
    }

    /// @notice Only owner can call
    modifier onlyOwner() {
        if (msg.sender != state.owner) {
            revert CMGroupOnlyOwner();
        }
        _;
    }

    /// @notice Only owner or service can call
    modifier onlyOwnerOrService() {
        if (msg.sender != state.owner && msg.sender != state.service) {
            revert CMGroupOnlyOwnerOrService();
        }
        _;
    }

    // Constructor

    constructor(
        address _owner,
        address _service,
        address _mintHandler,
        address _redemptionHandler,
        address[] memory _initialConditions,
        string memory _name,
        string memory _symbol,
        bytes32 _metadataDigest,
        CirclesCore memory _circlesCore
    ) {
        if (_owner == address(0)) {
            revert CMGroupInvalidCallingParameters();
        }
        _setOwner(_owner);
        _setService(_service);
        _setMintHandler(_mintHandler);
        _setRedemptionHandler(_redemptionHandler);
        // set initial minimal deposit to zero - no minimal deposit
        _setMinimalDeposit(0);

        // // set initial conditions
        for (uint256 i = 0; i < _initialConditions.length; i++) {
            _addMembershipCondition(_initialConditions[i]);
        }

        // set fee collection to be by default the owner
        state.feeCollection = _owner;

        // store the core Circles protocol addresses
        state.hub = _circlesCore.hub;
        state.standardTreasury = _circlesCore.standardTreasury;
        state.nameRegistry = _circlesCore.nameRegistry;

        // register group in hub and set the mint policy to this address
        state.hub.registerGroup(address(this), _name, _symbol, _metadataDigest);

        emit OwnerSet(_owner);
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
        _setService(_service);
    }

    /// @notice Change the owner address. Only the current owner can change ownership.
    /// @param _owner New owner address
    function setOwner(address _owner) external onlyOwner {
        _setOwner(_owner);
        emit OwnerSet(_owner);
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

    /// @notice Change minimal deposit amount for the group
    /// @param _minimalDeposit New minimal deposit amount
    /// @dev Must not exceed MAX_DEPOSIT_AMOUNT_MINIMUM. Only owner can change.
    function setMinimalDeposit(uint256 _minimalDeposit) external onlyOwner {
        if (_minimalDeposit > MAX_DEPOSIT_AMOUNT_MINIMUM) {
            revert CMGroupInvalidCallingParameters();
        }
        _setMinimalDeposit(_minimalDeposit);
    }

    /// @notice Change the fee collection address
    /// @param _feeCollection New fee collection address
    /// @dev The fee collection address must not be zero. Only owner can change.
    function setFeeCollection(address _feeCollection) external onlyOwner {
        if (_feeCollection == address(0)) {
            revert CMGroupInvalidCallingParameters();
        }
        state.feeCollection = _feeCollection;
        emit FeeCollectionUpdated(_feeCollection);
    }

    /// @notice trust allows the owner to explicitly set trust relations
    ///         for the group.
    function trust(address _trustReceiver, uint96 _expiry) external onlyOwner {
        _trust(_trustReceiver, _expiry);
    }

    /// @notice Trust or untrust a batch of core members with membership condition checks.
    /// @param _coreMembers Array of core member addresses to trust/untrust
    /// @param _expiry Trust expiry timestamp. If >= current timestamp, trust core member.
    ///        If < current timestamp, untrust only currently trusted core members (to avoid
    ///        accidentally trusting new core members for a single block).
    function trustBatchWithConditions(address[] memory _coreMembers, uint96 _expiry)
        public
        virtual
        onlyOwnerOrService
    {
        uint256 length = _coreMembers.length;
        address coreMember;
        // current block timestamp is an edge-case,
        // when expiry is now or a future time, this implies establishing trust
        // so we perform an explicit check on the launchpad whether these addresses
        // have an active LBP
        if (_expiry >= block.timestamp) {
            for (uint256 i = 0; i < length; i++) {
                coreMember = _coreMembers[i];
                (bool passed, address failedCondition) = _checkMembershipConditions(coreMember);
                if (!passed) {
                    revert CMGroupMembershipCheckFailed(coreMember, failedCondition);
                }
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
                if (state.hub.isTrusted(address(this), coreMember)) {
                    _trust(coreMember, _expiry);
                }
            }
        }
    }

    /// @notice Policy that registers minting of circles to track membership in group.
    /// @param _collateral Array of collateral token IDs being deposited.
    /// @return Returns true to allow the mint.
    function beforeMintPolicy(
        address, /*_minter*/
        address, /*_group*/
        uint256[] calldata _collateral,
        uint256[] calldata _amounts,
        bytes calldata /*_data*/
    ) external override onlyHub returns (bool) {
        // ensure the amounts are not zero as sanity check
        for (uint256 i = 0; i < _amounts.length; i++) {
            if (_amounts[i] < state.minimalDeposit) {
                // hub already checks no amount is zero in _groupMint,
                // but assert here that each deposit is at least minimally significant
                // to avoid that the group's vault collects dust, which makes the
                // redemption (and redemption bookkeeping) less efficient.
                revert CMGroupInteractionAmountIsBelowMinimum(_collateral[i], _amounts[i], state.minimalDeposit);
            }
        }
        // register deposit with redemption handler
        _registerDeposit(_collateral, _amounts);
        return true;
    }

    /// @notice Policy that validates and processes redemption of Circles tokens
    /// @param _data Encoded redemption data containing collateral IDs and values
    /// @return _ids Array of collateral token IDs to redeem
    /// @return _values Array of amounts for each collateral ID to redeem
    /// @return _burnIds Array of collateral token IDs to burn (empty)
    /// @return _burnValues Array of amounts to burn for each collateral ID (empty)
    function beforeRedeemPolicy(
        address, /*_operator*/
        address, /*_redeemer*/
        address, /*_group*/
        uint256, /*_value*/
        bytes calldata _data
    )
        external
        override
        onlyHubOrTreasury
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

        // register redemption with redemption handler
        _registerRedemption(redemption.redemptionIds, redemption.redemptionValues);

        // standard treasury checks whether the total sums add up to the amount of group Circles redeemed
        // so we can simply decode and pass the request back to treasury.
        // The redemption will fail if it does not contain (sufficient of) these Circles
        return (redemption.redemptionIds, redemption.redemptionValues, _burnIds, _burnValues);
    }

    /// @notice Sets advanced usage flags for this group in the Hub
    /// @param _flag Advanced usage flag value to set
    function setAdvancedUsageFlag(bytes32 _flag) external onlyOwner {
        state.hub.setAdvancedUsageFlag(_flag);
    }

    /// @notice Updates the metadata digest for this group in the name registry
    /// @param _metadataDigest New metadata digest value
    function updateMetadataDigest(bytes32 _metadataDigest) external onlyOwner {
        state.nameRegistry.updateMetadataDigest(_metadataDigest);
    }

    /// @notice Registers a short name for this group in the name registry
    function registerShortName() external onlyOwner {
        state.nameRegistry.registerShortName();
    }

    /// @notice Registers a short name for this group with a specified nonce
    /// @param _nonce Nonce value to use for short name registration
    function registerShortNameWithNonce(uint256 _nonce) external onlyOwner {
        state.nameRegistry.registerShortNameWithNonce(_nonce);
    }

    // View functions

    /// @notice Owner address. This is a copied value of ERC1967 ADMIN_SLOT
    ///         if this group mastercopy is consumed by an ERC1967 proxy.
    ///         For simplicity and readability we duplicate owner with ERC1967 admin,
    ///         even if for the intended deployment they are the same address.
    function owner() external view returns (address) {
        return state.owner;
    }

    /// @notice returns the mintHandler for the CM Group to assist with
    ///         automatic path-mints for the group.
    function mintHandler() external view returns (address) {
        return state.mintHandler;
    }

    /// @notice returns the redemptionHandler for the CM Group to facilitate
    ///         redemptions either direct or over paths.
    function redemptionHandler() external view returns (address) {
        return state.redemptionHandler;
    }

    /// @notice Service address. The service is limited to trusting (or untrusting) avatars.
    function service() external view returns (address) {
        return state.service;
    }

    /// @notice returns the minimal deposit amount for mints. The same minimal
    ///         amount must remain in the vault collateral in order to track
    ///         the id as active collateral for searches for redemption
    function minimalDeposit() external view returns (uint256) {
        return state.minimalDeposit;
    }

    /// @notice Returns the address that receives fees collected by this group
    function feeCollection() external view returns (address) {
        return state.feeCollection;
    }

    /// @notice Returns the array of membership condition addresses
    function getMembershipConditions() external view returns (address[] memory) {
        return state.membershipConditions;
    }

    /// @notice Returns the core Circles protocol addresses
    function getCirclesCore() external view returns (CirclesCore memory) {
        return CirclesCore(state.hub, state.standardTreasury, state.nameRegistry, state.erc20Lift);
    }

    // Internal functions

    function _setOwner(address _owner) internal {
        state.owner = _owner;
    }

    function _setService(address _service) internal {
        state.service = _service;
        emit ServiceUpdated(_service);
    }

    function _setMintHandler(address _mintHandler) internal {
        state.mintHandler = _mintHandler;
        emit MintHandlerUpdated(_mintHandler);
    }

    function _setRedemptionHandler(address _redemptionHandler) internal {
        state.redemptionHandler = _redemptionHandler;
        emit RedemptionHandlerUpdated(_redemptionHandler);
    }

    function _setMinimalDeposit(uint256 _minimalDeposit) internal {
        state.minimalDeposit = _minimalDeposit;
        emit MinimalDepositUpdated(_minimalDeposit);
    }

    function _addMembershipCondition(address _condition) internal {
        if (_condition == address(0)) {
            return;
        }
        if (state.membershipConditions.length >= MAX_CONDITIONS) {
            revert CMGroupMaxConditionsActive(state.membershipConditions.length);
        }
        for (uint256 i = 0; i < state.membershipConditions.length; i++) {
            if (state.membershipConditions[i] == _condition) {
                // avoid double entry of conditions, silently return
                return;
            }
        }
        state.membershipConditions.push(_condition);
    }

    function _removeMembershipCondition(address _condition) internal {
        if (_condition == address(0)) {
            return;
        }
        uint256 length = state.membershipConditions.length;
        for (uint256 i = 0; i < length; i++) {
            if (state.membershipConditions[i] == _condition) {
                if (i != length - 1) {
                    // Swap the condition with the last element, if not already last
                    state.membershipConditions[i] = state.membershipConditions[length - 1];
                }
                // Remove the last element
                state.membershipConditions.pop();
                return;
            }
        }
    }

    /// @notice Internal trust function that trusts a single core member
    ///         through the hub. If mintHandler contract is set,
    ///         also mirrors the trust there.
    /// @param _trustReceiver Address of core member to trust
    /// @param _expiry Timestamp when trust expires. If >= current time,
    ///         establishes trust. If < current time, serves to untrust.
    function _trust(address _trustReceiver, uint96 _expiry) internal {
        state.hub.trust(_trustReceiver, _expiry);
        address mintHandler_ = state.mintHandler;
        if (mintHandler_ != address(0)) {
            ICMGMintHandler(mintHandler_).mirrorTrust(_trustReceiver, _expiry);
        }
    }

    function _checkMembershipConditions(address _avatar) internal returns (bool, address) {
        for (uint256 i = 0; i < state.membershipConditions.length; i++) {
            if (!IMembershipCondition(state.membershipConditions[i]).passesMembershipCondition(_avatar)) {
                return (false, state.membershipConditions[i]);
            }
        }
        // passed all membership conditions,
        // true by default if no conditions set
        return (true, address(0));
    }

    function _registerDeposit(uint256[] memory _collateralIds, uint256[] memory _amounts) internal {
        address redemptionHandler_ = state.redemptionHandler;
        if (redemptionHandler_ != address(0)) {
            ICMGRedemptionHandler(redemptionHandler_).registerDeposit(_collateralIds, _amounts);
        }
    }

    function _registerRedemption(uint256[] memory _collateralIds, uint256[] memory _amounts) internal {
        address redemptionHandler_ = state.redemptionHandler;
        if (redemptionHandler_ != address(0)) {
            ICMGRedemptionHandler(redemptionHandler_).registerRedemption(_collateralIds, _amounts);
        }
    }
}
