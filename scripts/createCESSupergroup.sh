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

# Constants for CES group creation
# Check if file exists and is not empty (linux/osx)
if [ -f "./deployments/CESGroup-gnosis.txt" ] && [ -s "./deployments/CESGroup-gnosis.txt" ]; then
    DEPLOYMENT_COUNT=$(wc -l < "./deployments/CESGroup-gnosis.txt")
else
    DEPLOYMENT_COUNT=0
fi
NAME="TestCESGroup-$(printf "%02d" $((DEPLOYMENT_COUNT + 1)))"
SYMBOL="TEST-CES$(printf "%02d" $((DEPLOYMENT_COUNT + 1)))"
SERVICE_ADDRESS="0x0000000000000000000000000000000000000000"
METADATA_DIGEST="0x0000000000000000000000000000000000000000000000000000000000000000"

echo -e "${BLUE}Creating CES Group...${NC}"

# Load the deployer address
DEPLOYER_ADDRESS=$(tail -1 "./deployments/CESDeployer-gnosis.txt")

# Create the CES Group using cast send
GROUP_ADDRESS=$(cast send \
    --rpc-url ${RPC_URL_GNOSIS} \
    --private-key ${PRIVATE_KEY_GNOSIS} \
    --chain-id 100 \
    $DEPLOYER_ADDRESS \
    "createCESGroup(address,string,string,bytes32)" \
    $SERVICE_ADDRESS \
    "$NAME" \
    "$SYMBOL" \
    $METADATA_DIGEST \
    | grep "address" \
    | awk '{print $2}')

if [ -z "$GROUP_ADDRESS" ]; then
    echo -e "${RED}Error: CES Group creation failed${NC}"
    exit 1
fi

echo -e "${GREEN}CES Group created at:${NC} $GROUP_ADDRESS"

# Save the CES Group address to a file
echo "$GROUP_ADDRESS" >> "./deployments/CESGroup-gnosis.txt"
