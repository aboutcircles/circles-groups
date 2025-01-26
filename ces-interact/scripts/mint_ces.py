import os
from dotenv import load_dotenv
import json
import click
from web3 import Web3

# Load environment variables
load_dotenv()

# Load required environment variables
RPC_URL_GNOSIS = os.getenv("RPC_URL_GNOSIS", 'https://rpc.gnosischain.com')
PRIVATE_KEY = os.getenv("PRIVATE_KEY_GNOSIS", "0x00")

if PRIVATE_KEY == "0x00":
    raise ValueError("PRIVATE_KEY_GNOSIS environment variable is not set")

# Connect to Gnosis Chain
w3 = Web3(Web3.HTTPProvider(RPC_URL_GNOSIS))

# Load contract ABIs
with open("abis/CESSupergroup.json") as f:
    contract_data = json.load(f)
    contract_abi = contract_data["abi"]

with open("abis/Hub.json") as f:
    hub_data = json.load(f)
    hub_abi = hub_data["abi"]

# Contract address on Gnosis Chain
with open("../deployments/CESSupergroup-gnosis.txt") as f:
    logs = json.load(f)
    # Load and convert to checksum address
    CONTRACT_ADDRESS = Web3.to_checksum_address(logs[0]["address"])
    print(f"Contract address: {CONTRACT_ADDRESS}")

# Set hub constant address for Circles Hub contract
HUB_ADDRESS = Web3.to_checksum_address("0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8")
print(f"Hub address: {HUB_ADDRESS}")
