#!/bin/bash

# Flatten the source code for verification
echo -e "${BLUE}Flattening source code for verification...${NC}"

# Create a flattened directory if it doesn't exist
mkdir -p flattened

# Flatten the CoreMembersGroup contract
forge fmt --check src/CoreMembersGroup/CoreMembersGroup.sol
forge flatten src/CoreMembersGroup/CoreMembersGroup.sol > flattened/CoreMembersGroup.flat.sol

# Flatten the CESgroup contract
forge fmt --check src/projects/ces/CESgroup.sol
forge flatten src/projects/ces/CESgroup.sol > flattened/CESgroup.flat.sol

# Flatten the CMGroupDeployer contract
forge fmt --check src/CoreMembersGroup/helpers/CMGroupDeployer.sol
forge flatten src/CoreMembersGroup/helpers/CMGroupDeployer.sol > flattened/CMGroupDeployer.flat.sol

# Flatten the CESDeployer contract
forge fmt --check src/projects/ces/CESDeployer.sol
forge flatten src/projects/ces/CESDeployer.sol > flattened/CESDeployer.flat.sol

# Flatten the CMAncillary contract
forge fmt --check src/CoreMembersGroup/CMAncillary.sol
forge flatten src/CoreMembersGroup/CMAncillary.sol > flattened/CMAncillary.flat.sol

# Flatten the UpgradeableRenounceableProxy contract
forge fmt --check src/CoreMembersGroup/helpers/UpgradeableRenounceableProxy.sol
forge flatten src/CoreMembersGroup/helpers/UpgradeableRenounceableProxy.sol > flattened/UpgradeableRenounceableProxy.flat.sol

echo -e "${GREEN}Contract source code flattened for verification!${NC}"
echo -e "${GREEN}Flattened files saved in ./flattened/ directory${NC}"
