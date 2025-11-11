interface IHub {
    struct FlowEdge {
        uint16 streamSinkId;
        uint192 amount;
    }

    struct Stream {
        uint16 sourceCoordinate;
        uint16[] flowEdgeIds;
        bytes data;
    }

    function operateFlowMatrix(
        address[] calldata _flowVertices,
        FlowEdge[] calldata _flow,
        Stream[] calldata _streams,
        bytes calldata _packedCoordinates
    ) external;
    /// @notice returns the value of tokens of token type `id` owned by `account` at current day.
    function balanceOf(address account, uint256 id) external view returns (uint256);
    /// @notice burns ERC1155 amount of id owned by caller.
    function burn(uint256 id, uint256 amount, bytes calldata data) external;
    /// @notice transfers a `value` amount of tokens of type `id` from `from` to `to`.
    function safeTransferFrom(address from, address to, uint256 id, uint256 value, bytes memory data) external;
    /// @notice register group with Circles hub
    function registerCustomGroup(
        address mint,
        address treasury,
        string calldata name,
        string calldata symbol,
        bytes32 metadataDigest
    ) external;
    /// @notice register organization with Circles hub
    function registerOrganization(string calldata name, bytes32 metadataDigest) external;
    /// @notice trust sets the trust of the caller for the receiver with an expiry time.
    function trust(address trustReceiver, uint96 expiry) external;
    /// @notice isTrusted returns true if the expiry time of the trust relation is in the future
    function isTrusted(address truster, address trustee) external returns (bool);
    /// @notice groupMint allows the holder of collateral to directly group mint
    function groupMint(
        address group,
        address[] calldata collateralAvatars,
        uint256[] calldata amounts,
        bytes calldata data
    ) external;
    /// @notice wraps ERC1155 token into ERC20 token
    function wrap(address avatar, uint256 amount, uint8 circlesType) external returns (address);
    function isHuman(address avatar) external view returns (bool);
    function setApprovalForAll(address _operator, bool _approved) external;
    function trustMarkers(address, address) external view returns (address, uint96);
}
