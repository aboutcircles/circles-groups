// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "src/circles/Core.sol";
import "src/core-members-group/ICMGRedemptionHandler.sol";
import "src/redemption-operator/CMGRedemptionOperator.sol";
import "src/errors/Errors.sol";

/// @notice GroupLiquidityProvider registers as organization with Hub, trusts
///         only its group, and holds pCRC working capital to provide liquidity.
/// @dev Owner role transferred to group owner upon deployment.
contract GroupLiquidityProvider is CirclesCoreAddresses, ERC1155Holder, Ownable, IGroupLiquidityProviderErrors {
    // State

    /// @notice the group this liquidity provider shields
    address public immutable group;

    /// @notice core Circles protocol addresses
    CirclesCore public circlesCore;

    /// @notice redemption operator used for rebalancing
    CMGRedemptionOperator public immutable redemptionOperator;

    /// @notice token id of the group
    uint256 public immutable groupId;

    // Events

    /// @notice Emitted when liquidity is rebalanced from gCRC back to collateral
    /// @param liquidityProvider Address of the liquidity provider that rebalanced
    /// @param rebalancedAmount Amount rebalanced from gCRC to collateral pCRC
    /// @param remainingBalance Remaining gCRC balance after rebalance
    event LiquidityRebalanced(address indexed liquidityProvider, uint256 rebalancedAmount, uint256 remainingBalance);

    // Constructor

    constructor(
        address _group,
        address _owner,
        string memory _name,
        bytes32 _metadataDigest,
        CirclesCore memory _circlesCore,
        CMGRedemptionOperator _redemptionOperator
    ) Ownable(_owner) {
        if (_group == address(0)) {
            revert GroupLiquidityProviderGroupCannotBeZeroAddress();
        }
        if (_owner == address(0)) {
            revert GroupLiquidityProviderOwnerCannotBeZeroAddress();
        }

        group = _group;
        circlesCore = _circlesCore;
        redemptionOperator = _redemptionOperator;
        groupId = uint256(uint160(_group));

        // register as org with metadata
        circlesCore.hub.registerOrganization(_name, _metadataDigest);

        // trust group indefinitely
        circlesCore.hub.trust(_group, type(uint96).max);

        // approve redemption operator for gCRC
        circlesCore.hub.setApprovalForAll(address(redemptionOperator), true);
    }

    // External functions

    /// @notice Updates metadata digest in the name registry
    /// @param _metadataDigest New metadata digest value
    function updateMetadataDigest(bytes32 _metadataDigest) external onlyOwner {
        circlesCore.nameRegistry.updateMetadataDigest(_metadataDigest);
    }

    /// @notice Registers a short name in the name registry
    function registerShortName() external onlyOwner {
        circlesCore.nameRegistry.registerShortName();
    }

    /// @notice Registers a short name with nonce in the name registry
    function registerShortNameWithNonce(uint256 _nonce) external onlyOwner {
        circlesCore.nameRegistry.registerShortNameWithNonce(_nonce);
    }

    /// @notice Rebalances accumulated gCRC back to pCRC
    /// @dev Anyone can trigger rebalance - will swap gCRC back to its collateral
    /// @dev We rely on the redemption handler's findCollateral which distributes
    ///      nicely over the valid collateral
    function rebalance() external {
        uint256 gCrcBalance = circlesCore.hub.balanceOf(address(this), groupId);
        if (gCrcBalance > 0) {
            // redeem gCRC with found collateral
            redemptionOperator.redeemWithFoundCollateral(group, gCrcBalance, true);

            // check how much was actually redeemed by checking remaining balance
            uint256 remainingBalance = circlesCore.hub.balanceOf(address(this), groupId);
            uint256 rebalancedAmount = gCrcBalance - remainingBalance;

            emit LiquidityRebalanced(address(this), rebalancedAmount, remainingBalance);
        }
    }

    /// @notice Only owner can transfer tokens from this contract
    /// @dev Owner role is transferred to group owner in constructor
    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata data)
        external
        onlyOwner
    {
        if (from != address(this)) {
            revert GroupLiquidityProviderCanOnlyTransferOwnTokens();
        }
        circlesCore.hub.safeTransferFrom(from, to, id, amount, data);
    }

    /// @notice Owner can batch transfer tokens
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) external onlyOwner {
        if (from != address(this)) {
            revert GroupLiquidityProviderCanOnlyTransferOwnTokens();
        }
        circlesCore.hub.safeBatchTransferFrom(from, to, ids, amounts, data);
    }

    /// @notice Override acceptance call to only allow transfers from owner via hub
    function onERC1155Received(address operator, address from, uint256, uint256, bytes memory)
        public
        virtual
        override
        returns (bytes4)
    {
        if (operator != address(circlesCore.hub)) {
            revert GroupLiquidityProviderOnlyAcceptTransfersFromHub();
        }
        if (from != owner()) {
            revert GroupLiquidityProviderOnlyAcceptTransfersFromOwner();
        }
        return this.onERC1155Received.selector;
    }

    /// @notice Override batch acceptance call to only allow transfers from owner via hub
    function onERC1155BatchReceived(address operator, address from, uint256[] memory, uint256[] memory, bytes memory)
        public
        virtual
        override
        returns (bytes4)
    {
        if (operator != address(circlesCore.hub)) {
            revert GroupLiquidityProviderOnlyAcceptTransfersFromHub();
        }
        if (from != owner()) {
            revert GroupLiquidityProviderOnlyAcceptTransfersFromOwner();
        }
        return this.onERC1155BatchReceived.selector;
    }
}
