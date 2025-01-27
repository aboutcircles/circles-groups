// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "src/projects/ces/helpers/UpgradeableRenounceableProxy.sol";
import "src/projects/ces/CESSupergroup.sol";
import "src/operator/SupergroupOperator/SupergroupOperator.sol";

contract CESSupergroupDeployer {
    // Constants

    // /// @dev Callprefix to setup function of CESSupergroup
    // ///  function setup(address _service, uint256 _fee, address _feeCollection,
    // ///      uint256 _redemptionBurnRate, address[] calldata _operators,
    // ///      string calldata _name, string calldata _symbol, bytes32 _metadataDigest) external
    // bytes4 private constant SUPERGROUP_SETUP_CALLPREFIX =
    //     bytes4(keccak256("setup(address,uint256,address,uint256,address[],string,string,bytes32)"));

    // State variables

    /// @notice address of the deployed mastercopy for the CES Supergroup
    CESSupergroup public masterCopyCESSupergroup;

    // Constructor

    constructor() {
        // deploy a master copy for CES Supergroup
        masterCopyCESSupergroup = new CESSupergroup();
    }

    // External functions

    /// @notice Create CES Supergroup for caller
    function createCESSupergroup(
        address _service,
        uint256 _mintFee,
        address _feeCollection,
        uint256 _redemptionBurnRate,
        address[] calldata _operators,
        string calldata _name,
        string calldata _symbol,
        bytes32 _metadataDigest
    ) external returns (address) {
        // create a proxy with the i
        bytes memory data = abi.encodeWithSignature(
            "setup(address,address,uint256,address,uint256,address[],string,string,bytes32)",
            msg.sender,
            _service,
            _mintFee,
            _feeCollection,
            _redemptionBurnRate,
            _operators,
            _name,
            _symbol,
            _metadataDigest
        );

        UpgradeableRenounceableProxy proxy =
            new UpgradeableRenounceableProxy(msg.sender, address(masterCopyCESSupergroup), data);

        return address(proxy);
    }
}
