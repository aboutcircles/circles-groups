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
CMG_ADDRESS="0xf96131552f5e3ed60f359511ccf6c57662f7f937"
OWNER_ADDRESS="0x52007f2BFb658C9aC7dd60DBA637A29349b7c483"
HUB_ADDRESS="0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8"
TREASURY_ADDRESS="0x08F90aB73A515308f03A718257ff9887ED330C6e"
NAME_REGISTRY_ADDRESS="0xA27566fD89162cC3D40Cb59c87AAaA49B85F3474"

if [ -z "$CMG_ADDRESS" ]; then
    echo -e "${RED}Error: CMG_ADDRESS not found in declarations${NC}"
    exit 1
fi

if [ -z "$OWNER_ADDRESS" ]; then
    echo -e "${RED}Error: OWNER_ADDRESS not found in declarations${NC}"
    exit 1
fi

# Create CirclesCore struct encoding
CIRCLES_CORE_ENCODING="($HUB_ADDRESS,$TREASURY_ADDRESS,$NAME_REGISTRY_ADDRESS)"

# Create deployments directory if it doesn't exist
mkdir -p deployments

echo -e "${BLUE}Deploying CMGRedemptionHandler...${NC}"

# Deploy the handler contract
HANDLER_ADDRESS=$(forge create \
    src/core-members-group/CMGRedemptionHandler.sol:CMGRedemptionHandler \
    --rpc-url ${RPC_URL_GNOSIS} \
    --private-key ${PRIVATE_KEY_GNOSIS} \
    --broadcast \
    --constructor-args ${CMG_ADDRESS} ${OWNER_ADDRESS} ${CIRCLES_CORE_ENCODING} \
    | grep "Deployed to" \
    | awk '{print $3}')

if [ -z "$HANDLER_ADDRESS" ]; then
    echo -e "${RED}Error: Handler deployment failed${NC}"
    exit 1
fi

echo -e "${GREEN}CMGRedemptionHandler deployed at:${NC} $HANDLER_ADDRESS"

# Save the handler address to a file
echo "$HANDLER_ADDRESS" > "./deployments/CMGRedemptionHandler-gnosis.txt"
