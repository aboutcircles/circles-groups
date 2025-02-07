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

# set constructor params
CMG_ADDRESS="0xc164522ebc7e6a8b4b08878cf9e330cfebf4850a"
OWNER_ADDRESS="0x0e50fc4e7d629bC5EdD69B6DDDb3c22C6E60704b"
GROUP_NAME="TestCMGLBP01"

if [ -z "$CMG_ADDRESS" ]; then
    echo -e "${RED}Error: CMG_ADDRESS not found in declarations${NC}"
    exit 1
fi

if [ -z "$OWNER_ADDRESS" ]; then
    echo -e "${RED}Error: OWNER_ADDRESS not found in declarations${NC}"
    exit 1
fi

if [ -z "$GROUP_NAME" ]; then
    echo -e "${RED}Error: GROUP_NAME not found in declarations${NC}"
    exit 1
fi

# Create deployments directory if it doesn't exist
mkdir -p deployments

echo -e "${BLUE}Deploying CMGRedemptionHandler...${NC}"

# Deploy the handler contract
HANDLER_ADDRESS=$(forge create \
    src/core-members-group/CMGRedemptionHandler.sol:CMGRedemptionHandler \
    --rpc-url ${RPC_URL_GNOSIS} \
    --private-key ${PRIVATE_KEY_GNOSIS} \
    --broadcast \
    --constructor-args ${CMG_ADDRESS} ${OWNER_ADDRESS} "${GROUP_NAME}" \
    | grep "Deployed to" \
    | awk '{print $3}')

if [ -z "$HANDLER_ADDRESS" ]; then
    echo -e "${RED}Error: Handler deployment failed${NC}"
    exit 1
fi

echo -e "${GREEN}CMGRedemptionHandler deployed at:${NC} $HANDLER_ADDRESS"

# Save the handler address to a file
echo "$HANDLER_ADDRESS" > "./deployments/CMGRedemptionHandler-gnosis.txt"
