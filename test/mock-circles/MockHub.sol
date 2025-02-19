// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "openzeppelin-contracts/contracts/token/ERC1155/ERC1155.sol";
import "circles-contracts-v2/groups/IMintPolicy.sol";
import "test/mock-circles/MockStandardTreasury.sol";

contract MockHub is ERC1155 {
    // Enum

    /// @notice avatar types
    enum AvatarTypes {
        Unregistered,
        Human,
        Organization,
        Group
    }

    // Constants

    /// @notice CRC denomination
    uint256 public constant CRC = 1e18;

    // State

    /// @notice mint policies for groups
    mapping(address => IMintPolicy) public mintPolicies;
    /// @notice standard treasury
    MockStandardTreasury public standardTreasury;
    /// @notice registrations of avatars and their type
    mapping(address => AvatarTypes) public registrations;
    /// @notice simple trust relations
    mapping(address => mapping(address => bool)) public trusts;
    /// @notice treasury mapping for groups
    mapping(address => address) public treasuries;

    // Constructor

    constructor() ERC1155("") {
        standardTreasury = new MockStandardTreasury();
    }

    // Public functions

    function registerHuman(address _human, uint256 _amount) public {
        require(registrations[_human] == AvatarTypes.Unregistered, "human address already registered");
        registrations[_human] = AvatarTypes.Human;
        // allocate amount already upon registration
        _mint(_human, toTokenId(_human), _amount, "");
    }

    function registerGroup(
        address _mint,
        string calldata, /*_name*/
        string calldata, /*_symbol*/
        bytes32 /*_metadataDigest*/
    ) public {
        require(registrations[msg.sender] == AvatarTypes.Unregistered, "group address already registered");
        // store mint policy
        mintPolicies[msg.sender] = IMintPolicy(_mint);
        // register group
        registrations[msg.sender] = AvatarTypes.Group;
        // register standardTreasury for this group
        treasuries[msg.sender] = address(standardTreasury);
    }

    function registerOrganization(string calldata, /*_name*/ bytes32 /*_metadataDigest*/ ) public {
        require(registrations[msg.sender] == AvatarTypes.Unregistered, "organization address already registered");
        registrations[msg.sender] = AvatarTypes.Organization;
    }

    function personalMint(address[] memory _humans, uint256 amount) public {
        for (uint256 i = 0; i < _humans.length; i++) {
            require(registrations[_humans[i]] == AvatarTypes.Human, "not a human");
            _mint(_humans[i], toTokenId(_humans[i]), amount, "");
        }
    }

    function groupMint(
        address _group,
        address[] calldata _collateralAvatars,
        uint256[] calldata _amounts,
        bytes calldata _data
    ) public {
        // check group is registered
        require(isGroup(_group), "not a registered group");

        // check collateral avatars are trusted by group
        for (uint256 i = 0; i < _collateralAvatars.length; i++) {
            require(trusts[_group][_collateralAvatars[i]], "collateral avatar not trusted by group");
        }

        // call on standard treasury to ensureVault and get vault address
        address vault = standardTreasury.ensureVault(_group);

        // convert collateral avatars to collateral ids for policy check
        uint256[] memory collateralIds = new uint256[](_collateralAvatars.length);
        for (uint256 i = 0; i < _collateralAvatars.length; i++) {
            collateralIds[i] = toTokenId(_collateralAvatars[i]);
        }

        // call beforeMintPolicy on group
        require(
            mintPolicies[_group].beforeMintPolicy(msg.sender, _group, collateralIds, _amounts, _data),
            "mint policy rejected"
        );

        // sum total amounts
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < _amounts.length; i++) {
            totalAmount += _amounts[i];
        }

        // mint to caller the group circles (toTokenId(_group))
        _mint(msg.sender, toTokenId(_group), totalAmount, "");

        // batch transfer collateral directly to vault
        // (in Circles v2 beta this goes over Standard Treasury, but here we can simplify)
        _safeBatchTransferFrom(msg.sender, vault, collateralIds, _amounts, _data);
    }

    function burn(uint256 _id, uint256 _amount, bytes memory /*_data*/ ) public {
        // todo: beforeBurn policy hook is not mocked

        _burn(msg.sender, _id, _amount);
    }

    function trust(address _trustee, uint96 _expiry) public {
        trusts[msg.sender][_trustee] = _expiry > block.timestamp;
    }

    // View functions

    function isTrusted(address _truster, address _trustee) public view returns (bool) {
        return trusts[_truster][_trustee];
    }

    function isHuman(address _avatar) public view returns (bool) {
        return registrations[_avatar] == AvatarTypes.Human;
    }

    function isOrganization(address _avatar) public view returns (bool) {
        return registrations[_avatar] == AvatarTypes.Organization;
    }

    function isGroup(address _avatar) public view returns (bool) {
        return registrations[_avatar] == AvatarTypes.Group;
    }

    function toTokenId(address _avatar) public pure returns (uint256) {
        return uint256(uint160(_avatar));
    }
}
