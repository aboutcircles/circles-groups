#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Load environment variables
if [ -f .env ]; then
    echo -e "${BLUE}Loading environment variables...${NC}"
    source .env
else
    echo -e "${RED}Error: .env file not found${NC}"
    echo "Please copy .env.example to .env and fill in your values"
    exit 1
fi

# Check required environment variables
if [ -z "$PRIVATE_KEY_GNOSIS" ]; then
    echo -e "${RED}Error: PRIVATE_KEY_GNOSIS is not set in .env${NC}"
    exit 1
fi

if [ -z "$RPC_URL_GNOSIS" ]; then
    echo -e "${RED}Error: RPC_URL_GNOSIS is not set in .env${NC}"
    exit 1
fi

# Create deployments directory if it doesn't exist
mkdir -p deployments

# Constants for CMGroup creation
# Check if file exists and is not empty (linux/osx)
if [ -f "./deployments/CMGroup-gnosis.txt" ] && [ -s "./deployments/CMGroup-gnosis.txt" ]; then
    DEPLOYMENT_COUNT=$(wc -l < "./deployments/CMGroup-gnosis.txt")
else
    DEPLOYMENT_COUNT=0
fi
NAME="TestCMGroup-$(printf "%02d" $((DEPLOYMENT_COUNT + 1)))"
SYMBOL="TEST-CM$(printf "%02d" $((DEPLOYMENT_COUNT + 1)))"
SERVICE_ADDRESS="0x0000000000000000000000000000000000000000"
METADATA_DIGEST="0x0000000000000000000000000000000000000000000000000000000000000000"
INITIAL_CONDITIONS="[]" # Empty array for initial conditions

echo -e "${BLUE}Creating CM Group...${NC}"

# Load the deployer address
DEPLOYER_ADDRESS=$(tail -1 "./deployments/CMGDeployer-gnosis.txt")

# Create the CM Group using cast send
GROUP_ADDRESS=$(cast send \
    --rpc-url ${RPC_URL_GNOSIS} \
    --private-key ${PRIVATE_KEY_GNOSIS} \
    --chain-id 100 \
    $DEPLOYER_ADDRESS \
    "createCMGroup(address,address[],string,string,bytes32)" \
    $SERVICE_ADDRESS \
    "$INITIAL_CONDITIONS" \
    "$NAME" \
    "$SYMBOL" \
    $METADATA_DIGEST \
    | grep "address" \
    | awk '{print $2}')

if [ -z "$GROUP_ADDRESS" ]; then
    echo -e "${RED}Error: CM Group creation failed${NC}"
    exit 1
fi

echo -e "${GREEN}CM Group created at:${NC} $GROUP_ADDRESS"

# Save the CM Group address to a file
echo "$GROUP_ADDRESS" >> "./deployments/CMGroup-gnosis.txt"
