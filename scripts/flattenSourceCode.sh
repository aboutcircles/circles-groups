#!/bin/bash

# Flatten the source code for verification
echo -e "${BLUE}Flattening source code for verification...${NC}"

# Create a flattened directory if it doesn't exist
mkdir -p flattened

# Flatten the CoreMembersGroup contract
forge fmt --check src/core-members-group/CoreMembersGroup.sol
forge flatten src/core-members-group/CoreMembersGroup.sol > flattened/CoreMembersGroup.flat.sol


# Flatten the CMGroupDeployer contract
forge fmt --check src/core-members-group/helpers/CMGroupDeployer.sol
forge flatten src/core-members-group/helpers/CMGroupDeployer.sol > flattened/CMGroupDeployer.flat.sol

# Flatten the CMGMintHandler contract
forge fmt --check src/core-members-group/CMGMintHandler.sol
forge flatten src/core-members-group/CMGMintHandler.sol > flattened/CMGMintHandler.flat.sol

# Flatten the CMGRedemptionHandler contract
forge fmt --check src/core-members-group/CMGRedemptionHandler.sol
forge flatten src/core-members-group/CMGRedemptionHandler.sol > flattened/CMGRedemptionHandler.flat.sol


# Flatten the UpgradeableRenounceableProxy contract
forge fmt --check src/core-members-group/helpers/UpgradeableRenounceableProxy.sol
forge flatten src/core-members-group/helpers/UpgradeableRenounceableProxy.sol > flattened/UpgradeableRenounceableProxy.flat.sol

# Flatten the ActiveLBPBacker condition contracts
forge fmt --check src/membership-conditions/ActiveOneUsdLBPBackerCondition.sol
forge flatten src/membership-conditions/ActiveOneUsdLBPBackerCondition.sol > flattened/ActiveOneUsdLBPBackerCondition.flat.sol

forge fmt --check src/membership-conditions/ActiveTenUsdLBPBackerCondition.sol
forge flatten src/membership-conditions/ActiveTenUsdLBPBackerCondition.sol > flattened/ActiveTenUsdLBPBackerCondition.flat.sol

echo -e "${GREEN}Contract source code flattened for verification!${NC}"
echo -e "${GREEN}Flattened files saved in ./flattened/ directory${NC}"
