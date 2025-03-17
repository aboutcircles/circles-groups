// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "openzeppelin-contracts/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "circles-contracts-v2/hub/TypeDefinitions.sol";
import "circles-contracts-v2/groups/IMintPolicy.sol";
import "test/mock-circles/MockHub.sol";
import "test/mock-circles/MockVault.sol";

contract MockStandardTreasury is TypeDefinitions, ERC1155Holder {
    // State

    /// @notice hub
    MockHub public hub;

    /// @notice vaults for groups
    mapping(address => MockVault) public vaults;

    // Constructor
    constructor() {
        hub = MockHub(msg.sender);
    }

    function ensureVault(address _group) public returns (address) {
        require(hub.isGroup(_group), "not a group");
        if (address(vaults[_group]) == address(0)) {
            vaults[_group] = new MockVault(hub);
        }
        return address(vaults[_group]);
    }

    function onERC1155Received(address _operator, address _from, uint256 _id, uint256 _value, bytes memory _data)
        public
        override
        returns (bytes4)
    {
        // decode metadata
        Metadata memory metadata = abi.decode(_data, (Metadata));

        // only handle group redeem
        require(metadata.metadataType == METADATATYPE_GROUPREDEEM, "invalid metadata type");
        require(metadata.metadata.length == 0, "invalid metadata for redeem");

        // validate circles id maps to a group address
        address group = address(uint160(_id));
        require(uint256(uint160(group)) == _id, "invalid group circles id");
        require(hub.isGroup(group), "not a group");

        // get vault
        MockVault vault = vaults[group];
        require(address(vault) != address(0), "group has no vault");

        IMintPolicy policy = hub.mintPolicies(group);
        // query the mint policy for the redemption values
        uint256[] memory redemptionIds;
        uint256[] memory redemptionValues;
        uint256[] memory burnIds;
        uint256[] memory burnValues;
        (redemptionIds, redemptionValues, burnIds, burnValues) =
            policy.beforeRedeemPolicy(_operator, _from, group, _value, metadata.erc1155UserData);

        // ensure the redemption values sum up to the correct amount
        uint256 sum = 0;
        for (uint256 i = 0; i < redemptionValues.length; i++) {
            sum += redemptionValues[i];
        }
        for (uint256 i = 0; i < burnValues.length; i++) {
            sum += burnValues[i];
        }
        if (sum != _value) {
            revert("invalid redemption values from policy");
        }

        // burn received group circles
        hub.burn(_id, _value, metadata.erc1155UserData);

        // return collateral
        vault.returnCollateral(_from, redemptionIds, redemptionValues, metadata.erc1155UserData);

        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] memory, uint256[] memory, bytes memory)
        public
        pure
        override
        returns (bytes4)
    {
        revert("batch received not supported");
    }
}
