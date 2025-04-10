// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IHub} from "src/base-group/interfaces/IHub.sol";

/// @title BaseMintHandler
/// @notice The BaseMintHandler contract manages the conversion of ERC1155 tokens
///         into group Circles (gCRC) or specialized ERC20 tokens (demurrage/inflationary).
/// @dev This contract is intended to be used by a Group alongside the Circles Hub.
///      It holds incoming tokens, initiates a minting procedure in the Hub, and returns the newly minted
///      group Circles to the designated beneficiary. It may also wrap group Circles into specialized
///      ERC20 tokens (demurrage or inflationary), if instructed via `_data`.
///      Key storage for conversion data is managed in transient storage (tstore).
contract BaseMintHandler is ERC1155Holder {
    // =================================================
    //                       ERRORS
    // =================================================

    /// @notice Thrown when a function is called by an account other than the Hub.
    error OnlyHub();

    /// @notice Thrown when a function is called by an account other than the Group.
    error OnlyGroup();

    /// @notice Thrown when an unexpected or invalid logic condition occurs.
    error LogicAssertion();

    /// @notice Thrown when an attempt is made to mint or handle the Group's own ID as collateral.
    error RevertGroupId();

    /// @notice Thrown when a zero amount is received where a non-zero amount is expected.
    error ReceivedZeroAmount();

    /// @notice Thrown when a new conversion is requested while another is still ongoing in transient storage.
    error ConversionOngoing();

    // =================================================
    //                     CONSTANTS
    // =================================================

    /// @dev Single transient slot where to store the amount being converted: keccak256("CONVERSION_SLOT")
    bytes32 internal constant CONVERSION_SLOT = 0xfb747a744f99e39f75c6fc4a40ae1e72605f4d4a2aa65e5e3d29e889d7f5061b;

    /// @dev Single transient slot where to store beneficiary address: keccak256("BENEFICIARY_SLOT")
    bytes32 internal constant BENEFICIARY_SLOT = 0x6136adcd727e05279d0beb0b97407672abc1607384d66aec4a65a09daa5bba68;

    /// @dev Single transient slot where to store token type to return: keccak256("TOKEN_TYPE_SLOT")
    bytes32 internal constant TOKEN_TYPE_SLOT = 0xcda71533cdfa11dcfe861dbfa38b956c85d855f8e75c6728c650ac844f4fd47e;

    /// @dev Token type identifier for inflationary group Circles: keccak256("TYPE_INFLATIONARY")
    bytes32 public constant TYPE_INFLATIONARY = 0x9d28938b56c0e8aae8dd05e12461cbabf8f699236c3fd7c54c7d3bb9fb443ed2;

    /// @dev Token type identifier for demurrage group Circles: keccak256("TYPE_DEMURRAGE")
    bytes32 public constant TYPE_DEMURRAGE = 0xf3f5858942140fd2894eeb8b74cd0ed72d24fc6675d352a2884b1be2f32256fe;

    /// @notice Emitted when a new conversion is initiated in this handler.
    /// @param beneficiary The address for which the minted tokens will be returned.
    /// @param amount The amount being converted (from non-gCRC to gCRC).
    /// @param tokenType The token type identifier. 0 indicates ERC1155 gCRC, 1 indicates ERC20 demurrage, 2 indicates ERC20 inflationary.
    event ConversionInitiated(address indexed beneficiary, uint256 indexed amount, uint256 indexed tokenType);

    /// @notice Emitted when an ongoing conversion in transient storage is completed and cleared.
    event ConversionCleared();

    /// @notice Emitted when minted group Circles are returned (either as gCRC or wrapped as ERC20).
    /// @param beneficiary The address receiving the minted tokens.
    /// @param amount The amount of minted group Circles or the resulting ERC20 balance.
    /// @param tokenType The token type identifier. 0 indicates normal gCRC, 1 indicates demurrage, 2 indicates inflationary.
    event ReturnedMintedGroupCircles(address indexed beneficiary, uint256 indexed amount, uint256 indexed tokenType);

    /// @notice The Hub contract that manages trust relationships and other Circles operations.
    IHub public immutable HUB;

    /// @notice The address of the group for which this mint handler is created.
    address public immutable GROUP;

    /// @dev The numeric ID of this group, derived from the group's address.
    uint256 internal immutable GROUP_ID;

    // =================================================
    //                    MODIFIERS
    // =================================================

    /// @notice Ensures the function is only called by the Hub.
    /// @dev Reverts if `msg.sender` is not the Hub contract.
    modifier onlyHub() {
        if (msg.sender != address(HUB)) {
            revert OnlyHub();
        }
        _;
    }

    /// @notice Ensures the function is only called by the Group.
    /// @dev Reverts if `msg.sender` is not the Group contract.
    modifier onlyGroup() {
        if (msg.sender != address(GROUP)) {
            revert OnlyGroup();
        }
        _;
    }

    // =================================================
    //                    CONSTRUCTOR
    // =================================================

    /**
     * @notice Deploys the BaseMintHandler for a given group and registers it as an organization in the Hub.
     * @param _hub The address of the Circles Hub contract.
     * @param _group The address of the Group contract.
     * @param _groupName The name of the group used for identification in the Hub registry.
     */
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

    /**
     * @notice Mirrors trust relationships from the Group to this handler in the Hub.
     *         This maintains the same trust state as the Group for automatic path mints.
     * @dev Only the Group can call this function.
     * @param _backer The address that the Group trusts.
     * @param _expiry The expiry time (unix timestamp) until which the trust remains valid.
     */
    function mirrorTrust(address _backer, uint96 _expiry) external onlyGroup {
        HUB.trust(_backer, _expiry);
    }

    // =================================================
    //         ERC1155 RECEIVER OVERRIDDEN FUNCTIONS
    // =================================================

    /**
     * @notice Handles the receipt of a single ERC1155 token type.
     * @dev Only the Hub can call this function. If `_from` is address(0), it indicates new gCRC minted by the Hub,
     *      which will be returned to the beneficiary or wrapped based on the transient state.
     * @param _from The address that previously owned the token.
     * @param _id The ID of the token being transferred.
     * @param _value The amount of tokens being transferred.
     * @param _data Additional data. Used to indicate demurrage or inflationary mint if set to known constants.
     * @return The selector to confirm acceptance of the ERC1155 transfer.
     */
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
                    // return the freshly minted gCRC to the beneficiary
                    HUB.safeTransferFrom(address(this), beneficiary, GROUP_ID, _value, _data);
                } else {
                    // demurrage or inflationary
                    // wrap ERC1155 into ERC20 TODO: take balanceBefore
                    address token = HUB.wrap(GROUP, _value, uint8(tokenType - 1));
                    ongoingConversion = IERC20(token).balanceOf(address(this));
                    IERC20(token).transfer(beneficiary, _value);
                }
                emit ReturnedMintedGroupCircles(beneficiary, ongoingConversion, tokenType);
                return this.onERC1155Received.selector;
            } else {
                // unexpected gCRC mint
                revert LogicAssertion();
            }
        }
        // attempt to mint group id using group id as collateral
        if (_id == GROUP_ID) revert LogicAssertion();

        // from is not zero (i.e. not minted) && id is not gCRC

        // set our expectation lock (reverts if already ongoing)
        _initiateConversion(_from, _value, _data);

        // assume any token received (that is not gCRC) to be an attempt to mint gCRC
        address[] memory collateralAvatars = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        // safely cast because ids received from hub
        collateralAvatars[0] = address(uint160(_id));
        amounts[0] = _value;
        // initiate groupMint (which will call back, but expectation lock is set)
        HUB.groupMint(GROUP, collateralAvatars, amounts, _data);

        return this.onERC1155Received.selector;
    }

    /**
     * @notice Handles the receipt of multiple ERC1155 token types at once.
     * @dev Only the Hub can call this function. If `_from` is address(0), it indicates an unexpected batch mint,
     *      which reverts in this contract. Otherwise, it sums up the values and initiates a group mint for the batch.
     * @param _from The address that previously owned the tokens.
     * @param _ids An array containing IDs of each token being transferred.
     * @param _values An array containing amounts of each token being transferred.
     * @param _data Additional data. Used to indicate demurrage or inflationary mint if set to known constants.
     * @return The selector to confirm acceptance of the ERC1155 batch transfer.
     */
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

        (uint256 ongoingConversion,,) = _expectingConversionReturn();
        // Note: this is double check here, as same is done inside _initiateConversion, tbd where to leave
        // a batch acceptance call must only happen at the start of a mint conversion
        if (ongoingConversion != uint256(0)) revert ConversionOngoing();

        // revert if any of the ids reference group id
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

    /**
     * @notice Converts token IDs to avatar addresses and reverts if any token ID equals the group's ID.
     * @dev Used internally by `onERC1155BatchReceived` to ensure we never take the group's own ID as collateral.
     * @param _ids An array of token IDs to check and convert.
     * @return collateralAvatars An array of collateral avatar addresses converted from token IDs.
     */
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

    /**
     * @notice Initiates a conversion process by storing the amount in transient storage.
     *         Also sets the beneficiary address and detects whether demurrage or inflationary mint is requested.
     * @dev Uses assembly to store in transient storage. Reverts if a conversion is already ongoing or amount is zero.
     * @param _beneficiary The address to which the minted tokens will be returned.
     * @param _amount The amount to convert — must be non-zero.
     * @param _data Additional data that may contain an indication of demurrage or inflationary token type.
     */
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
            // Store the new conversion amount, beneficiary and token type in transient storage
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

    /**
     * @notice Reads the current conversion data from transient storage.
     * @return ongoingConversion The amount of the ongoing conversion, or 0 if none is active.
     * @return beneficiary The address of the beneficiary for the ongoing conversion.
     * @return tokenType The requested token type (0 = ERC1155 gCRC, 1 = ERC20 demurrage, 2 = ERC20 inflationary).
     */
    function _expectingConversionReturn()
        internal
        view
        returns (uint256 ongoingConversion, address beneficiary, uint256 tokenType)
    {
        assembly {
            ongoingConversion := tload(CONVERSION_SLOT)
            beneficiary := tload(BENEFICIARY_SLOT)
            tokenType := tload(TOKEN_TYPE_SLOT)
        }
    }

    /**
     * @notice Clears the ongoing conversion from transient storage, indicating the process is complete.
     * @dev Resets all associated conversion data to zero in transient storage.
     */
    function _clearConversion() internal {
        assembly {
            tstore(CONVERSION_SLOT, 0)
            tstore(BENEFICIARY_SLOT, 0)
            tstore(TOKEN_TYPE_SLOT, 0)
        }
        emit ConversionCleared();
    }
}
