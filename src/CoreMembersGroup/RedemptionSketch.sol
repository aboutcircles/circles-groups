// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * Minimal ERC1155 interface needed for this example.
 * In production, use OpenZeppelin's ERC1155 and related libraries.
 */
interface IERC1155 {
    function balanceOf(address account, uint256 id) external view returns (uint256);
    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata data) external;
}

/**
 * Minimal base contract to "mint" and "burn" an ERC1155 group token.
 * For a real system, use OpenZeppelin's ERC1155 implementation.
 */
contract MinimalERC1155 {
    // Mapping: owner => (tokenId => balance)
    mapping(address => mapping(uint256 => uint256)) internal _balances;

    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);

    function balanceOf(address account, uint256 id) public view returns (uint256) {
        return _balances[account][id];
    }

    function _mint(address to, uint256 id, uint256 amount) internal {
        _balances[to][id] += amount;
        emit TransferSingle(msg.sender, address(0), to, id, amount);
    }

    function _burn(address from, uint256 id, uint256 amount) internal {
        require(_balances[from][id] >= amount, "Not enough balance to burn");
        _balances[from][id] -= amount;
        emit TransferSingle(msg.sender, from, address(0), id, amount);
    }
}

/**
 * Example Vault that:
 *  - Accepts deposits of "trusted" ERC1155 collateral from an external contract
 *  - Mints "group tokens" (an ERC1155 token within this contract) 1:1
 *  - Allows round-robin redemption to get *any* underlying collateral
 */
contract GroupVault is MinimalERC1155 {
    IERC1155 public collateralContract; // External ERC1155 contract with collateral tokens
    uint256 public constant GROUP_TOKEN_ID = 1; // The single group token ID minted by this contract

    // Tracks how many units of each collateral ID this vault currently holds
    mapping(uint256 => uint256) public vaultBalance;

    // We keep an array of "active" collateral IDs that have a nonzero balance
    uint256[] public activeIds;

    // This maps collateral ID => index in the `activeIds` array
    mapping(uint256 => uint256) public indexInActiveIds;

    // The round-robin cursor for redemption
    uint256 public cursor;

    // A mapping of "trusted" IDs. In practice, you might want to manage this more elegantly.
    mapping(uint256 => bool) public trusted;

    // ----------------------------------------
    // Events
    // ----------------------------------------
    event Deposit(address indexed depositor, uint256 indexed id, uint256 amount);
    event Redemption(address indexed redeemer, uint256 groupTokenAmount);

    // ----------------------------------------
    // Constructor
    // ----------------------------------------
    constructor(IERC1155 _collateralContract, uint256[] memory _trustedIds) {
        collateralContract = _collateralContract;
        for (uint256 i = 0; i < _trustedIds.length; i++) {
            trusted[_trustedIds[i]] = true;
        }
    }

    // ----------------------------------------
    // Public Functions
    // ----------------------------------------

    /**
     * @notice Deposit a "trusted" collateral token from the external ERC1155 contract.
     *         In return, this contract mints the same amount of GROUP_TOKEN_ID to the caller.
     * @dev    Caller must have setApprovalForAll(this vault) on the collateral contract beforehand.
     */
    function deposit(uint256 collateralId, uint256 amount) external {
        require(trusted[collateralId], "ID not trusted");
        require(amount > 0, "Deposit amount must be > 0");

        // 1. Transfer collateral from user to this vault
        collateralContract.safeTransferFrom(msg.sender, address(this), collateralId, amount, "");

        // 2. Update vaultBalance
        bool wasZeroBefore = (vaultBalance[collateralId] == 0);
        vaultBalance[collateralId] += amount;

        // 3. If vault balance was 0 -> nonzero, add it to activeIds
        if (wasZeroBefore) {
            _addActiveId(collateralId);
        }

        // 4. Mint group tokens to the user
        _mint(msg.sender, GROUP_TOKEN_ID, amount);

        emit Deposit(msg.sender, collateralId, amount);
    }

    /**
     * @notice Redeem `amount` of group tokens to get any available collateral via round-robin.
     * @dev    This vault will burn `amount` of GROUP_TOKEN_ID from the caller.
     */
    function redeem(uint256 amount) external {
        require(amount > 0, "Redeem amount must be > 0");
        require(balanceOf(msg.sender, GROUP_TOKEN_ID) >= amount, "Not enough group tokens");

        // 1. Burn group tokens from caller
        _burn(msg.sender, GROUP_TOKEN_ID, amount);

        uint256 remaining = amount;

        // 2. Round-robin redemption
        //    We'll continue until we've redeemed 'remaining' collateral or run out of active IDs.
        //    In a real system, consider gas limits, so possibly cap how many iterations to do.

        while (remaining > 0 && activeIds.length > 0) {
            // "Wrap" the cursor to stay within array bounds
            cursor = cursor % activeIds.length;

            uint256 currentId = activeIds[cursor];
            uint256 vaultAmt = vaultBalance[currentId];

            // If there's nothing actually left for this ID (shouldn't happen if well-managed),
            // remove from active and continue
            if (vaultAmt == 0) {
                _removeActiveId(currentId);
                continue;
            }

            // Decide how much we will redeem from this ID
            uint256 redeemFromThisId = (vaultAmt <= remaining) ? vaultAmt : remaining;

            // Transfer out collateral to user
            // For a real system, you'd do a safeTransferFrom on the *vault itself*? Actually
            // the vault holds the tokens, so we do "transfer from vault to user".
            // But because the ERC1155 is external, we do: safeTransferFrom(address(this), msg.sender, ...)
            // Many ERC1155s do not let arbitrary addresses call `safeTransferFrom(...)` on them.
            // Possibly you'd use a custom function in your collateral contract or keep track differently.
            // For illustration:
            collateralContract.safeTransferFrom(address(this), msg.sender, currentId, redeemFromThisId, "");

            // Update vault balances
            vaultBalance[currentId] -= redeemFromThisId;

            // If that ID's balance is now 0, remove from active
            if (vaultBalance[currentId] == 0) {
                _removeActiveId(currentId);
            } else {
                // Move the cursor forward
                cursor += 1;
            }

            // Decrease the remaining redemption
            remaining -= redeemFromThisId;
        }

        emit Redemption(msg.sender, amount);
    }

    // ----------------------------------------
    // Internal / Private Helpers
    // ----------------------------------------

    /**
     * @dev Add an ID to the 'activeIds' array and set indexInActiveIds for quick removal.
     */
    function _addActiveId(uint256 id) internal {
        indexInActiveIds[id] = activeIds.length;
        activeIds.push(id);
    }

    /**
     * @dev Remove an ID from 'activeIds' array via swap-and-pop to keep it O(1).
     */
    function _removeActiveId(uint256 id) internal {
        uint256 idx = indexInActiveIds[id];
        uint256 lastIdx = activeIds.length - 1;

        if (idx != lastIdx) {
            // Swap current item with the last
            uint256 lastId = activeIds[lastIdx];
            activeIds[idx] = lastId;
            indexInActiveIds[lastId] = idx;
        }

        // Remove the last element
        activeIds.pop();

        // Cleanup index mapping
        delete indexInActiveIds[id];

        // Because we removed the item at `cursor`, we should not advance cursor
        // in the redemption logic if that item was at or before `cursor`.
        // For simplicity, we won't handle that here. In production, handle carefully!
    }

    // Implementing minimal hooks, to allow this contract to receive ERC1155 tokens safely
    // (In real code, use the OpenZeppelin ERC1155Receiver approach).
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return this.onERC1155BatchReceived.selector;
    }
}
