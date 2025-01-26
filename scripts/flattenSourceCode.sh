#!/bin/bash

# Flatten the source code for verification
echo -e "${BLUE}Flattening source code for verification...${NC}"

# Create a flattened directory if it doesn't exist
mkdir -p flattened

# Flatten the CESSupergroupDeployer contract
forge fmt --check src/projects/ces/helpers/CESSupergroupDeployer.sol
forge flatten src/projects/ces/helpers/CESSupergroupDeployer.sol > flattened/CESSupergroupDeployer.flat.sol

# Flatten the CESSupergroup contract
forge fmt --check src/projects/ces/CESSupergroup.sol
forge flatten src/projects/ces/CESSupergroup.sol > flattened/CESSupergroup.flat.sol

# Flatten the UpgradeableRenounceableProxy contract
forge fmt --check src/projects/ces/helpers/UpgradeableRenounceableProxy.sol
forge flatten src/projects/ces/helpers/UpgradeableRenounceableProxy.sol > flattened/UpgradeableRenounceableProxy.flat.sol

echo -e "${GREEN}Contract source code flattened for verification!${NC}"
echo -e "${GREEN}Flattened files saved in ./flattened/ directory${NC}"
