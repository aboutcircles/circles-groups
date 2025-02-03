// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

interface ICoreMembersGroup {
    function setService(address _service) external;
    function setMintHandler(address _mintHandler) external;
    function setRedemptionHandler(address _redemptionHandler) external;
    function setMinimalDeposit(uint256 _minimalDeposit) external;
    function trust(address _trustReceiver, uint96 _expiry) external;
    function trustBatch(address[] memory _coreMembers, uint96 _expiry) external;
    function setAdvancedUsageFlag(bytes32 _flag) external;
    function updateMetadataDigest(bytes32 _metadataDigest) external;
    function registerShortName() external;
    function registerShortNameWithNonce(uint256 _nonce) external;
    function owner() external view returns (address);
    function mintHandler() external view returns (address);
    function redemptionHandler() external view returns (address);
    function service() external view returns (address);
    function minimalDeposit() external view returns (uint256);
}
