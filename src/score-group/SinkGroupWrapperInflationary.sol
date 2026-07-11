// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IHub} from "src/score-group/interfaces/IHub.sol";

/**
 * @title SinkGroupWrapperInflationary
 * @notice Helper organization that receives Circles group ERC1155 tokens and wraps them into inflationary ERC20s.
 * @dev
 * The contract registers itself as a Hub organization during construction so it can participate in
 * the Circles Hub trust graph. A group must first be trusted through {trust} before its ERC1155
 * group token can be routed to this wrapper under the Hub's flow rules.
 *
 * When this contract receives a single ERC1155 group token transfer from the Hub, it wraps the
 * received group balance into the group's inflationary ERC20 representation by calling
 * `HUB.wrap(group, amount, 1)`, then transfers the resulting ERC20 balance to the original sender.
 *
 * This contract only implements single-token ERC1155 receipt. Batch receipt is intentionally not
 * implemented by this contract.
 */
contract SinkGroupWrapperInflationary {
    // =================================================
    //                       ERRORS
    // =================================================

    /// @notice Thrown when a function is called by an account other than the Hub.
    error OnlyHub();

    /// @notice Thrown when an operation expects a Hub group but the supplied or derived address is not a group.
    error OnlyGroup();

    /// @notice Thrown when the ERC1155 transfer source is the zero address.
    error InvalidSource();

    /// @notice Thrown when a zero amount is received where a non-zero amount is expected.
    error ReceivedZeroAmount();

    // =================================================
    //                    EVENTS
    // =================================================

    /**
     * @notice Emitted after received group ERC1155 tokens are wrapped into inflationary ERC20s.
     * @param group Group address whose ERC1155 group token was wrapped.
     * @param amount Amount of ERC1155 group tokens received and passed to the Hub wrapper.
     * @param beneficiary Address that receives the resulting inflationary ERC20 balance.
     */
    event GroupWrapped(address indexed group, uint256 indexed amount, address indexed beneficiary);

    // =================================================
    //                     CONSTANTS
    // =================================================

    /// @notice Circles v2 Hub used for organization registration, trust, group checks, and wrapping.
    IHub public constant HUB = IHub(address(0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8));

    // =================================================
    //                    MODIFIERS
    // =================================================

    /**
     * @notice Ensures the function is only called by the Hub.
     * @dev Reverts with {OnlyHub} if `msg.sender` is not the configured Hub address.
     */
    modifier onlyHub() {
        if (msg.sender != address(HUB)) {
            revert OnlyHub();
        }
        _;
    }

    // =================================================
    //                    CONSTRUCTOR
    // =================================================

    /**
     * @notice Deploys the wrapper and registers it as a Hub organization.
     * @dev
     * Registers the organization name `group-inflationary-wrapper` with an empty metadata digest.
     * Registration allows this contract to exist as an avatar on the Circles Hub trust graph.
     */
    constructor() {
        HUB.registerOrganization("group-inflationary-wrapper", bytes32(0));
    }

    // =================================================
    //                EXTERNAL FUNCTIONS
    // =================================================

    /**
     * @notice Trusts a group so its group ERC1155 token can be routed to this wrapper.
     * @dev
     * Reverts with {OnlyGroup} if `_group` is not recognized by the Hub as a group.
     * On success, calls `HUB.trust(_group, type(uint96).max)` from this contract's organization
     * context, granting effectively unbounded trust duration according to the Hub's trust semantics.
     *
     * @param _group Group avatar address to trust.
     */
    function trust(address _group) external {
        if (!HUB.isGroup(_group)) revert OnlyGroup();
        HUB.trust(_group, type(uint96).max);
    }

    // =================================================
    //         ERC1155 RECEIVER FUNCTION
    // =================================================

    /**
     * @notice Receives one group ERC1155 token id, wraps it into an inflationary ERC20, and forwards the ERC20 to the sender.
     * @dev
     * Only callable by the Hub. The token id is interpreted as a group avatar address by truncating it to
     * `address(uint160(_id))`, and the derived address must be recognized by the Hub as a group.
     *
     * The function wraps `_value` units of the received group ERC1155 token through `HUB.wrap(group, _value, uint8(1))`.
     * The wrapper type `1` corresponds to the inflationary ERC20 representation under the Hub's wrapping API.
     * After wrapping, the contract transfers its full resulting balance of that inflationary ERC20 to `_from`.
     *
     * Requirements:
     * - Caller must be the Hub.
     * - `_from` must not be the zero address.
     * - `_value` must be non-zero.
     * - `_id`, interpreted as an address, must correspond to a Hub group.
     *
     * Effects:
     * - Wraps the received ERC1155 group token amount into the group's inflationary ERC20.
     * - Transfers this contract's full balance of the resulting inflationary ERC20 to `_from`.
     * - Emits {GroupWrapped}.
     *
     * @param _from Original source address of the ERC1155 transfer and recipient of the wrapped ERC20 balance.
     * @param _id ERC1155 token id, interpreted as the group address.
     * @param _value Amount of group ERC1155 tokens received and wrapped.
     * @return The ERC1155 receiver selector confirming successful receipt.
     */
    function onERC1155Received(address, address _from, uint256 _id, uint256 _value, bytes memory)
        external
        onlyHub
        returns (bytes4)
    {
        if (_from == address(0)) revert InvalidSource();
        if (_value == 0) revert ReceivedZeroAmount();
        address group = address(uint160(_id));
        if (!HUB.isGroup(group)) revert OnlyGroup();

        address erc20Inflationary = HUB.wrap(group, _value, uint8(1));
        uint256 balanceInflationary = IERC20(erc20Inflationary).balanceOf(address(this));
        IERC20(erc20Inflationary).transfer(_from, balanceInflationary);

        emit GroupWrapped(group, _value, _from);

        return this.onERC1155Received.selector;
    }

    /**
     * @notice Receives multiple group ERC1155 token ids, wraps each into an inflationary ERC20, and forwards the ERC20s to the sender.
     * @dev
     * Only callable by the Hub. Each token id is interpreted as a group avatar address by truncating it to
     * `address(uint160(_ids[i]))`, and each derived address must be recognized by the Hub as a group.
     *
     * For each received group token amount, the function calls `HUB.wrap(group, value, uint8(1))`.
     * The wrapper type `1` corresponds to the inflationary ERC20 representation under the Hub's wrapping API.
     * After each wrap, the contract transfers its full resulting balance of that inflationary ERC20 to `_from`.
     *
     * Requirements:
     * - Caller must be the Hub.
     * - `_from` must not be the zero address.
     * - Each `_values[i]` must be non-zero.
     * - Each `_ids[i]`, interpreted as an address, must correspond to a Hub group.
     *
     * Effects:
     * - Wraps each received ERC1155 group token amount into its group's inflationary ERC20.
     * - Transfers this contract's full balance of each resulting inflationary ERC20 to `_from`.
     * - Emits {GroupWrapped} for each wrapped group token.
     *
     * @param _from Original source address of the ERC1155 batch transfer and recipient of the wrapped ERC20 balances.
     * @param _ids ERC1155 token ids, each interpreted as a group address.
     * @param _values Amounts of group ERC1155 tokens received and wrapped.
     * @return The ERC1155 receiver selector confirming successful batch receipt.
     */
    function onERC1155BatchReceived(
        address,
        address _from,
        uint256[] memory _ids,
        uint256[] memory _values,
        bytes memory
    ) external onlyHub returns (bytes4) {
        if (_from == address(0)) revert InvalidSource();
        for (uint256 i; i < _ids.length;) {
            uint256 value = _values[i];
            if (value == 0) revert ReceivedZeroAmount();
            address group = address(uint160(_ids[i]));
            if (!HUB.isGroup(group)) revert OnlyGroup();

            address erc20Inflationary = HUB.wrap(group, value, uint8(1));
            uint256 balanceInflationary = IERC20(erc20Inflationary).balanceOf(address(this));
            IERC20(erc20Inflationary).transfer(_from, balanceInflationary);

            emit GroupWrapped(group, value, _from);

            unchecked {
                ++i;
            }
        }
        return this.onERC1155BatchReceived.selector;
    }
}
