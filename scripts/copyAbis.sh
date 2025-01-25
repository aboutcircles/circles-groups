#!/bin/bash

# copyAbis.sh, start in root

# Build contracts first
forge build --extra-output abi

# Go to script directory
cd ces-interact

# Create abis directory if it doesn't exist
mkdir -p abis

# Copy specific contract ABIs from forge output to abis dir
cp ../out/CESSupergroup.sol/CESSupergroup.json abis/CESSupergroup.json
