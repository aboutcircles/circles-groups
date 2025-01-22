// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "src/supergroup/Supergroup.sol";

contract CESSupergroup is Supergroup {
    // State

    /// @notice Service address. The service is limited to trusting (or untrusting) avatars.
    address public service;
    /// @notice Launchpad enables people to back their personal CRC in an LBP pool.
    ///         This first supergroup will explicitly check the launchpad whether
    ///         a person has backed their Circles. This is a specific opinion on what
    ///         a supergroup can be, so (todo) in later work, factor this out better.
    address public launchpad;

    // Modifiers

    /// @notice Only owner or service can call
    modifier onlyOwnerOrService() {
        if (msg.sender != owner && msg.sender != service) {
            revert SupergroupOnlyOwner();
        }
        _;
    }

    // Constructor

    function setup(
        address _service,
        address _launchpad,
        uint256 _fee,
        address _feeCollection,
        uint256 _redemptionBurnRate
    ) external {
        // first call setup on Supergroup
        super.setup(_fee, _feeCollection, _redemptionBurnRate);

        if (_service == address(0) || _launchpad == address(0)) {
            revert SupergroupInvalidCallingParameters();
        }

        // set the service key
        service = _service;
        // set the launchpad address (immutable in this impl)
        launchpad = _launchpad;
    }

    // External functions

    function setService(address _service) external onlyOwner {
        service = _service;
    }
}
