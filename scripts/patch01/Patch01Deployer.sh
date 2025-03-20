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

# Deploy CoreMembersGroupPatch01
echo -e "${BLUE}Deploying CoreMembersGroupPatch01 to Gnosis Chain...${NC}"

# Using forge create command
PATCH_ADDRESS=$(forge create \
    --rpc-url ${RPC_URL_GNOSIS} \
    --private-key ${PRIVATE_KEY_GNOSIS} \
    --broadcast \
    src/core-members-group/patch01/CoreMembersGroupPatch01.sol:CoreMembersGroup \
    | grep "Deployed to" \
    | awk '{print $3}')

if [ -z "$PATCH_ADDRESS" ]; then
    echo -e "${RED}Error: Deployment failed${NC}"
    exit 1
fi

echo -e "${GREEN}CoreMembersGroupPatch01 deployed to:${NC} $PATCH_ADDRESS"

# Save the deployment address to a file
echo "$PATCH_ADDRESS" >> "./deployments/CoreMembersGroupPatch01-gnosis.txt"

echo -e "${GREEN}Deployment complete!${NC}"
