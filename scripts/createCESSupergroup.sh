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

# Constants for CESSupergroup creation
SERVICE_ADDRESS="0x0000000000000000000000000000000000000001"
MINT_FEE="0"
FEE_COLLECTION="0x0000000000000000000000000000000000000000"
REDEMPTION_BURN_RATE="0"
OPERATORS="[]"
NAME="TestCESSupergroup-01"
SYMBOL="TEST-CES01"
METADATA_DIGEST="0x0000000000000000000000000000000000000000000000000000000000000000"

echo -e "${BLUE}Creating CESSupergroup...${NC}"

# Load the deployer address
DEPLOYER_ADDRESS=$(cat "./deployments/CESSupergroupDeployer-gnosis.txt")

# Create the CESSupergroup using cast send
SUPERGROUP_ADDRESS=$(cast send \
    --rpc-url ${RPC_URL_GNOSIS} \
    --private-key ${PRIVATE_KEY_GNOSIS} \
    --chain-id 100 \
    $DEPLOYER_ADDRESS \
    "createCESSupergroup(address,uint256,address,uint256,address[],string,string,bytes32)" \
    $SERVICE_ADDRESS \
    $MINT_FEE \
    $FEE_COLLECTION \
    $REDEMPTION_BURN_RATE \
    $OPERATORS \
    $NAME \
    $SYMBOL \
    $METADATA_DIGEST \
    | grep "address" \
    | awk '{print $2}')

if [ -z "$SUPERGROUP_ADDRESS" ]; then
    echo -e "${RED}Error: CESSupergroup creation failed${NC}"
    exit 1
fi

echo -e "${GREEN}CESSupergroup created at:${NC} $SUPERGROUP_ADDRESS"

# Save the CESSupergroup address to a file
echo "$SUPERGROUP_ADDRESS" > "./deployments/CESSupergroup-gnosis.txt"
