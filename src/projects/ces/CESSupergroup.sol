// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.28;

import "src/supergroup/Supergroup.sol";
import "src/projects/ces/CESCoreAddresses.sol";

contract CESSupergroup is Supergroup, CESSupergroupCoreAddresses {
    // State

    /// @notice Service address. The service is limited to trusting (or untrusting) avatars.
    address public service;

    // Modifiers

    /// @notice Only owner or service can call
    modifier onlyOwnerOrService() {
        if (msg.sender != owner && msg.sender != service) {
            revert SupergroupOnlyOwnerOrService();
        }
        _;
    }

    // Constructor

    function setup(
        address _service,
        uint256 _fee,
        address _feeCollection,
        uint256 _redemptionBurnRate,
        address[] calldata _operators,
        string calldata _name,
        string calldata _symbol,
        bytes32 _metadataDigest
    ) external {
        // first call setup on Supergroup
        super.setup(_fee, _feeCollection, _redemptionBurnRate, _operators, _name, _symbol, _metadataDigest);

        if (_service == address(0)) {
            revert SupergroupInvalidCallingParameters();
        }

        // set the service key
        service = _service;
    }

    // External functions

    /// @notice Trust or untrust a batch of Backers.
    /// @param _backers Array of backer addresses to trust/untrust
    /// @param _expiry Trust expiry timestamp. If >= current timestamp, trust backers with active LBPs. If < current timestamp, untrust currently trusted backers
    function trustBatch(address[] calldata _backers, uint96 _expiry) external onlyOwnerOrService {
        uint256 length = _backers.length;
        address backer;
        // current block timestamp is an edge-case, so include it in the active
        // check for active LBP.
        // when expiry is now or a future time, this implies establishing trust
        // so we perform an explicit check on the launchpad whether these addresses
        // have an active LBP
        if (_expiry >= block.timestamp) {
            for (uint256 i = 0; i < length; i++) {
                backer = _backers[i];
                // skip any backers that are not active (yet/anymore)
                if (launchpad.isActiveLBP(backer)) {
                    hub.trust(backer, _expiry);
                }
            }
        } else {
            // hub will update older expiry times to current block.timestamp, so preventatively
            // already update to current timestamp
            _expiry = uint96(block.timestamp);
            // if expiry is explicitly set in the past, then that means to untrust the backers
            // however, hub will set trust to current block.timestamp for expiry, so to avoid that
            // we trust a previously never-trusted backer for one block,
            // first check whether the backer is currently trusted;
            // ie. that meant the group has previously trusted the backer via a valid path
            //     so setting trust to expire after this block is untrusting;
            //     and doing nothing means the expiry for this backer was already 0 or < timestamp
            for (uint256 i = 0; i < length; i++) {
                backer = _backers[i];
                if (hub.isTrusted(address(this), backer)) {
                    hub.trust(backer, _expiry);
                }
            }
        }
    }

    function setService(address _service) external onlyOwner {
        service = _service;
    }
}
