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

echo -e "${BLUE}Deploying BaseRedemptionEncoder...${NC}"

# Deploy the encoder contract
ENCODER_ADDRESS=$(forge create \
    src/redemption-operator/BaseRedemptionEncoder.sol:BaseRedemptionEncoder \
    --rpc-url ${RPC_URL_GNOSIS} \
    --private-key ${PRIVATE_KEY_GNOSIS} \
    --broadcast \
    | grep "Deployed to" \
    | awk '{print $3}')

if [ -z "$ENCODER_ADDRESS" ]; then
    echo -e "${RED}Error: Encoder deployment failed${NC}"
    exit 1
fi

echo -e "${GREEN}BaseRedemptionEncoder deployed at:${NC} $ENCODER_ADDRESS"

# Save the encoder address to a file
echo "$ENCODER_ADDRESS" > "./deployments/BaseRedemptionEncoder-gnosis.txt"
