#!/bin/bash

# copyAbis.sh, start in root

# Build contracts first
forge build --extra-output abi

# Go to script directory
cd ces-interact

# Create abis directory if it doesn't exist
mkdir -p abis

# Copy specific contract ABIs from forge output to abis dir
cp ../out/core-members-group/CoreMembersGroup.json abis/CoreMembersGroup.json
cp ../out/CESgroup.sol/CESgroup.json abis/CESgroup.json
cp ../out/CMGroupDeployer.sol/CMGroupDeployer.json abis/CMGroupDeployer.json
cp ../lib/circles-contracts-v2/out/Hub.sol/Hub.json abis/Hub.json
