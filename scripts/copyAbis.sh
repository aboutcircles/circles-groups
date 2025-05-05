#!/bin/bash

# copyAbis.sh, start in root

# Build contracts first
forge build --extra-output abi

# Go to script directory
cd cmg-interact

# Create abis directory if it doesn't exist
mkdir -p abis

# Copy specific contract ABIs from forge output to abis dir
cp ../out/CoreMembersGroup.sol/CoreMembersGroup.json abis/CoreMembersGroup.json
cp ../out/CMGroupDeployer.sol/CMGroupDeployer.json abis/CMGroupDeployer.json
cp ../out/CMGMintHandler.sol/CMGMintHandler.json abis/CMGMintHandler.json
cp ../out/CMGRedemptionHandler.sol/CMGRedemptionHandler.json abis/CMGRedemptionHandler.json
cp ../out/CMGRedemptionOperator.sol/CMGRedemptionOperator.json abis/CMGRedemptionOperator.json
cp ../out/UpgradeableRenounceableProxy.sol/UpgradeableRenounceableProxy.json abis/UpgradeableRenounceableProxy.json
cp ../out/GroupLiquidityProvider.sol/GroupLiquidityProvider.json abis/GroupLiquidityProvider.json
cp ../out/GroupLiquidityProviderDeployer.sol/GroupLiquidityProviderDeployer.json abis/GroupLiquidityProviderDeployer.json
cp ../out/PrimaryGroupRegistry.sol/PrimaryGroupRegistry.json abis/PrimaryGroupRegistry.json
cp ../out/IsHumanCondition.sol/IsHumanCondition.json abis/IsHumanCondition.json
cp ../out/ActiveOneUsdLBPBackerCondition.sol/ActiveOneUsdLBPBackerCondition.json abis/ActiveOneUsdLBPBackerCondition.json
cp ../out/ActiveTenUsdLBPBackerCondition.sol/ActiveTenUsdLBPBackerCondition.json abis/ActiveTenUsdLBPBackerCondition.json
cp ../lib/circles-contracts-v2/out/Hub.sol/Hub.json abis/Hub.json
