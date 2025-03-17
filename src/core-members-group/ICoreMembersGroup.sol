// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "src/circles/Core.sol";

interface ICoreMembersGroup {
    function setService(address _service) external;
    function setMinimalDeposit(uint256 _minimalDeposit) external;
    function trust(address _trustReceiver, uint96 _expiry) external;
    function trustBatchWithConditions(address[] memory _coreMembers, uint96 _expiry) external;
    function setOwner(address _owner) external;
    function setMembershipCondition(address _condition, bool _enabled) external;
    function setAdvancedUsageFlag(bytes32 _flag) external;
    function updateMetadataDigest(bytes32 _metadataDigest) external;
    function registerShortName() external;
    function registerShortNameWithNonce(uint256 _nonce) external;
    function owner() external view returns (address);
    function mintHandler() external view returns (address);
    function redemptionHandler() external view returns (address);
    function service() external view returns (address);
    function minimalDeposit() external view returns (uint256);
    function setFeeCollection(address _feeCollection) external;
    function feeCollection() external view returns (address);
    function getMembershipConditions() external view returns (address[] memory);
    function getCirclesCore() external view returns (CirclesCoreAddresses.CirclesCore memory);
}
