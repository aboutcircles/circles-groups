#!/bin/bash

# Get script directory and go to project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$(git rev-parse --show-toplevel)"

# Make the abis directory if it doesn't exist
mkdir -p export-abis

# Export clean ABIs for each contract
forge inspect src/core-members-group/CoreMembersGroup.sol:CoreMembersGroup abi > export-abis/CoreMembersGroup.json
forge inspect src/core-members-group/helpers/CMGroupDeployer.sol:CMGroupDeployer abi > export-abis/CMGroupDeployer.json
forge inspect src/core-members-group/CMGMintHandler.sol:CMGMintHandler abi > export-abis/CMGMintHandler.json
forge inspect src/core-members-group/CMGRedemptionHandler.sol:CMGRedemptionHandler abi > export-abis/CMGRedemptionHandler.json
forge inspect src/redemption-operator/CMGRedemptionOperator.sol:CMGRedemptionOperator abi > export-abis/CMGRedemptionOperator.json
forge inspect src/core-members-group/helpers/UpgradeableRenounceableProxy.sol:UpgradeableRenounceableProxy abi > export-abis/UpgradeableRenounceableProxy.json
forge inspect src/liquidity-provider/GroupLiquidityProvider.sol:GroupLiquidityProvider abi > export-abis/GroupLiquidityProvider.json
forge inspect src/liquidity-provider/helpers/GroupLiquidityProviderDeployer.sol:GroupLiquidityProviderDeployer abi > export-abis/GroupLiquidityProviderDeployer.json
forge inspect src/affiliate-group/AffiliateGroupRegistry.sol:AffiliateGroupRegistry abi > export-abis/AffiliateGroupRegistry.json
forge inspect src/membership-conditions/IsHumanCondition.sol:IsHumanCondition abi > export-abis/IsHumanCondition.json
forge inspect src/membership-conditions/ActiveOneUsdLBPBackerCondition.sol:ActiveOneUsdLBPBackerCondition abi > export-abis/ActiveOneUsdLBPBackerCondition.json
forge inspect src/membership-conditions/ActiveTenUsdLBPBackerCondition.sol:ActiveTenUsdLBPBackerCondition abi > export-abis/ActiveTenUsdLBPBackerCondition.json
forge inspect lib/circles-contracts-v2/src/hub/Hub.sol:Hub abi > export-abis/Hub.json
forge inspect src/redemption-operator/BaseRedemptionEncoder.sol:BaseRedemptionEncoder abi > export-abis/BaseRedemptionEncoder.json
