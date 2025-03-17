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
cp ../out/UpgradeableRenounceableProxy.sol/UpgradeableRenounceableProxy.json abis/UpgradeableRenounceableProxy.json
cp ../lib/circles-contracts-v2/out/Hub.sol/Hub.json abis/Hub.json
