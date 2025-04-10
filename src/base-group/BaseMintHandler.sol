// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IHub} from "src/base-group/interfaces/IHub.sol";

contract BaseMintHandler is ERC1155Holder {
    // =================================================
    //                       ERRORS
    // =================================================

    /**
     * @notice Thrown when a function is called by an account other than the Hub.
     */
    error OnlyHub();

    /**
     * @notice Thrown when a function is called by an account other than the Group.
     */
    error OnlyGroup();

    error LogicAssertion();

    error RevertGroupId();

    error ReceivedZeroAmount();

    error ConversionOngoing();

    // =================================================
    //                     CONSTANTS
    // =================================================

    /// @dev single transient slot where to store conversion amount in progress: keccak256("CONVERSION_SLOT")
    bytes32 internal constant CONVERSION_SLOT = 0xfb747a744f99e39f75c6fc4a40ae1e72605f4d4a2aa65e5e3d29e889d7f5061b;
    /// @dev single transient slot where to store beneficiary address: keccak256("BENEFICIARY_SLOT")
    bytes32 internal constant BENEFICIARY_SLOT = 0x6136adcd727e05279d0beb0b97407672abc1607384d66aec4a65a09daa5bba68;
    /// @dev single transient slot where to store token type to return: keccak256("TOKEN_TYPE_SLOT")
    bytes32 internal constant TOKEN_TYPE_SLOT = 0xcda71533cdfa11dcfe861dbfa38b956c85d855f8e75c6728c650ac844f4fd47e;

    /// @dev keccak256("TYPE_INFLATIONARY")
    bytes32 public constant TYPE_INFLATIONARY = 0x9d28938b56c0e8aae8dd05e12461cbabf8f699236c3fd7c54c7d3bb9fb443ed2;
    /// @dev keccak256("TYPE_DEMURRAGE")
    bytes32 public constant TYPE_DEMURRAGE = 0xf3f5858942140fd2894eeb8b74cd0ed72d24fc6675d352a2884b1be2f32256fe;

    /// @notice Emitted when a new conversion is initiated
    event ConversionInitiated(address indexed beneficiary, uint256 indexed amount, uint256 indexed tokenType);

    /// @notice Emitted when a conversion is completed and cleared
    event ConversionCleared();

    event ReturnedMintedGroupCircles(address indexed beneficiary, uint256 indexed amount, uint256 indexed tokenType);

    /**
     * @notice The Hub contract that manages trust relationships and other Circles operations.
     */
    IHub public immutable HUB;

    /**
     * @notice The address of the group (or organization) for which this treasury is created.
     */
    address public immutable GROUP;

    uint256 internal immutable GROUP_ID;

    // =================================================
    //                    MODIFIERS
    // =================================================

    /**
     * @notice Ensures the function is only called by the Hub.
     * @dev Reverts if `msg.sender` is not the Hub contract.
     */
    modifier onlyHub() {
        if (msg.sender != address(HUB)) {
            revert OnlyHub();
        }
        _;
    }

    /**
     * @notice Ensures the function is only called by the Group.
     * @dev Reverts if `msg.sender` is not the Group contract.
     */
    modifier onlyGroup() {
        if (msg.sender != address(GROUP)) {
            revert OnlyGroup();
        }
        _;
    }

    // =================================================
    //                    CONSTRUCTOR
    // =================================================

    constructor(address _hub, address _group, string memory _groupName) {
        HUB = IHub(_hub);
        GROUP = _group;
        GROUP_ID = uint256(uint160(_group));

        string memory mintHandlerName = string.concat(_groupName, "-mint-handler");
        HUB.registerOrganization(mintHandlerName, bytes32(0));
    }

    // =================================================
    //                EXTERNAL FUNCTIONS
    // =================================================

    /// @notice Mirror trust relationships from the Group to the Handler.
    ///         This allows the handler to maintain the same trust state
    ///         as the Group for automatic path mints.
    /// @param _backer Address that is trusted by the Group
    /// @param _expiry Expiry time until when trust is valid
    function mirrorTrust(address _backer, uint96 _expiry) external onlyGroup {
        HUB.trust(_backer, _expiry);
    }

    // =================================================
    //         ERC1155 RECEIVER OVERRIDDEN FUNCTIONS
    // =================================================

    function onERC1155Received(address, address _from, uint256 _id, uint256 _value, bytes memory _data)
        public
        override
        onlyHub
        returns (bytes4)
    {
        if (_from == address(0)) {
            // check transient storage to see if we are expecting a return
            (uint256 ongoingConversion, address beneficiary, uint256 tokenType) = _expectingConversionReturn();
            // group CRC were minted here
            // so expect an ongoing conversion from collateral to gCRC
            if (ongoingConversion == _value && _id == GROUP_ID) {
                _clearConversion();
                if (tokenType == 0) {
                    // return the freshly minted gCRC to sender
                    HUB.safeTransferFrom(address(this), beneficiary, GROUP_ID, _value, _data);
                } else {
                    // demurrage or inflationary
                    // wrap ERC1155 into ERC20 TODO: take balanceBefore
                    address token = HUB.wrap(GROUP, _value, uint8(tokenType - 1));
                    ongoingConversion = IERC20(token).balanceOf(address(this));
                    IERC20(token).transfer(beneficiary, _value);
                }
                // emit event for clarity
                emit ReturnedMintedGroupCircles(beneficiary, ongoingConversion, tokenType);
                return this.onERC1155Received.selector;
            } else {
                // unexpected gCRC mint
                revert LogicAssertion();
            }
        }
        // attempt to mint group id using group id as collateral
        if (_id == GROUP_ID) revert LogicAssertion();

        // from is not zero (ie. not minted) && id is not gCRC

        // set our expectation lock (reverts if already ongoing)
        _initiateConversion(_from, _value, _data);

        // assume any token received (that is not gCRC)
        // to be an attempt to mint gCRC
        address[] memory collateralAvatars = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        // safely cast because ids received from hub
        collateralAvatars[0] = address(uint160(_id));
        amounts[0] = _value;
        // initiate groupMint (which will call back, but expectation lock is set)
        HUB.groupMint(GROUP, collateralAvatars, amounts, _data);

        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address _from,
        uint256[] memory _ids,
        uint256[] memory _values,
        bytes memory _data
    ) public override onlyHub returns (bytes4) {
        // Note: arrays length mismatch is handled on HUB.groupMint(group, collateralAvatars, amounts, data); , but
        // TODO: check if it is possible to not reach the revert branch and have infinite totalValue

        // it should be impossible that Circles get minted here (as batch)
        if (_from == address(0)) revert LogicAssertion();

        // sum the _values
        uint256 totalValue;
        for (uint256 i; i < _values.length;) {
            totalValue += _values[i];
            unchecked {
                ++i;
            }
        }
        // Note: this is double check here, as same is done inside _initiateConversion, but i prefer to remove it from there later
        if (totalValue == uint256(0)) revert ReceivedZeroAmount();

        // check transient storage to see if we are expecting a return
        (uint256 ongoingConversion,,) = _expectingConversionReturn();

        // Note: this is double check here, as same is done inside _initiateConversion, tbd where to leave
        // a batch acceptance call must only happen at the start of a mint conversion
        if (ongoingConversion != uint256(0)) revert ConversionOngoing();

        // there is no ongoing conversion registered, so interpret this as
        // a request to group mint

        // revert if ids reference group id directly
        address[] memory collateralAvatars = _castIdsRevertGroupId(_ids);
        // enable the lock
        _initiateConversion(_from, totalValue, _data);
        // attempt group mint
        HUB.groupMint(GROUP, collateralAvatars, _values, _data);

        return this.onERC1155BatchReceived.selector;
    }

    // =================================================
    //                 INTERNAL FUNCTIONS
    // =================================================

    /// @dev Converts ids to avatar addresses and validates batch transfers don't contain group id.
    /// @param _ids Array of token IDs to check and convert
    /// @return collateralAvatars Array of collateral avatar addresses converted from token IDs
    function _castIdsRevertGroupId(uint256[] memory _ids) internal view returns (address[] memory collateralAvatars) {
        collateralAvatars = new address[](_ids.length);
        for (uint256 i; i < _ids.length;) {
            if (_ids[i] == GROUP_ID) {
                revert RevertGroupId();
            }
            // confidently cast to address, as ids are given by hub
            collateralAvatars[i] = address(uint160(_ids[i]));
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Initiates a conversion process by storing the amount in transient storage
    /// @dev Uses transient storage to track ongoing conversions within a transaction
    /// @param _amount Amount to convert - must be non-zero
    function _initiateConversion(address _beneficiary, uint256 _amount, bytes memory _data) internal {
        bytes32 errorReceivedZero = ReceivedZeroAmount.selector;
        bytes32 errorConversionOngoing = ConversionOngoing.selector;
        uint256 tokenType;

        assembly {
            // Revert if amount is zero
            if iszero(_amount) {
                mstore(0, errorReceivedZero)
                revert(0, 0x04)
            }
            // Load any existing conversion amount from transient storage
            switch tload(CONVERSION_SLOT)
            // Store the new conversion amount, and beneficiary in transient storage
            case 0 {
                tstore(CONVERSION_SLOT, _amount)
                tstore(BENEFICIARY_SLOT, _beneficiary)
                if gt(mload(_data), 0x1f) {
                    switch mload(add(_data, 0x20))
                    // TYPE_DEMURRAGE
                    case 0xf3f5858942140fd2894eeb8b74cd0ed72d24fc6675d352a2884b1be2f32256fe {
                        tokenType := 0x01
                        tstore(TOKEN_TYPE_SLOT, tokenType)
                    }
                    // TYPE_INFLATIONARY
                    case 0x9d28938b56c0e8aae8dd05e12461cbabf8f699236c3fd7c54c7d3bb9fb443ed2 {
                        tokenType := 0x02
                        tstore(TOKEN_TYPE_SLOT, tokenType)
                    }
                }
            }
            // Revert if there is already an ongoing conversion
            default {
                mstore(0, errorConversionOngoing)
                revert(0, 0x04)
            }
        }

        emit ConversionInitiated(_beneficiary, _amount, tokenType);
    }

    /// @dev Reads the current conversion amount and beneficiary from transient storage
    /// @return ongoingConversion The amount of the ongoing conversion, or 0 if none is active
    /// @return beneficiary The address of the beneficiary for the ongoing conversion
    function _expectingConversionReturn()
        internal
        view
        returns (uint256 ongoingConversion, address beneficiary, uint256 tokenType)
    {
        // Load the current conversion amount and beneficiary
        assembly {
            ongoingConversion := tload(CONVERSION_SLOT)
            beneficiary := tload(BENEFICIARY_SLOT)
            tokenType := tload(TOKEN_TYPE_SLOT)
        }
    }

    /// @dev Clears conversion amount and beneficiary
    function _clearConversion() internal {
        assembly {
            tstore(CONVERSION_SLOT, 0)
            tstore(BENEFICIARY_SLOT, 0)
            tstore(TOKEN_TYPE_SLOT, 0)
        }

        emit ConversionCleared();
    }
}
