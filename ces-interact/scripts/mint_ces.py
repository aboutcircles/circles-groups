import os
from dotenv import load_dotenv
import json
import click
from web3 import Web3
from eth_account.messages import encode_defunct
from safe_eth.eth import EthereumClient
from eth_typing import URI

# Load environment variables
load_dotenv()

# Load required environment variables
RPC_URL_GNOSIS = os.getenv("RPC_URL_GNOSIS", 'https://rpc.gnosischain.com')
PRIVATE_KEY = os.getenv("PRIVATE_KEY_GNOSIS", "0x00")
HUMAN_SAFE_ADDRESS = os.getenv("HUMAN_SAFE_ADDRESS", "0x00")
HUMAN_SAFE_OWNER_PRIVATE_KEY = os.getenv("HUMAN_SAFE_OWNER_PRIVATE_KEY", "0x00")

if PRIVATE_KEY == "0x00":
    raise ValueError("PRIVATE_KEY_GNOSIS environment variable is not set")
if HUMAN_SAFE_ADDRESS == "0x00":
    raise ValueError("HUMAN_SAFE_ADDRESS environment variable is not set")
if HUMAN_SAFE_OWNER_PRIVATE_KEY == "0x00":
    raise ValueError("HUMAN_SAFE_OWNER_PRIVATE_KEY environment variable is not set")

# Connect to Gnosis Chain
w3 = Web3(Web3.HTTPProvider(RPC_URL_GNOSIS))
safe_ethereum_client = EthereumClient(URI(RPC_URL_GNOSIS))

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



# SAFE helper functions

def sign_execute_safe_transaction(contract_function, *args):
    """
    Sign and execute a transaction through the SAFE multisig
    """
    safe_address = Web3.to_checksum_address(HUMAN_SAFE_ADDRESS)

    # Build transaction data
    txn_data = contract_function(*args)._encode_transaction_data()

    nonce = w3.eth.get_transaction_count(safe_address, 'latest')

    # Build SafeTx hash
    tx_hash = Web3.solidity_keccak(
        ['address', 'uint256', 'bytes', 'uint8', 'uint256', 'uint256',
         'uint256', 'address', 'address', 'uint256'],
        [CONTRACT_ADDRESS, 0, txn_data, 0, 500000, 0, 0,
         "0x0000000000000000000000000000000000000000",
         "0x0000000000000000000000000000000000000000",
         nonce]
    )

    # Sign transaction hash
    signed_message = w3.eth.account.sign_message(
        encode_defunct(tx_hash),
        private_key=private_key
    )

    # Build transaction
    tx = {
        'to': CONTRACT_ADDRESS,
        'value': 0,
        'data': txn_data,
        'operation': 0,
        'safeTxGas': 500000,
        'baseGas': 0,
        'gasPrice': 0,
        'gasToken': "0x0000000000000000000000000000000000000000",
        'refundReceiver': "0x0000000000000000000000000000000000000000",
        'signatures': signed_message.signature.hex()
    }

    # Execute transaction through Safe
    txn = w3.eth.contract(address=safe_address, abi=contract_abi).functions.execTransaction(
        tx['to'],
        tx['value'],
        tx['data'],
        tx['operation'],
        tx['safeTxGas'],
        tx['baseGas'],
        tx['gasPrice'],
        tx['gasToken'],
        tx['refundReceiver'],
        tx['signatures']
    ).build_transaction({
        'from': safe_address,
        'nonce': nonce,
        'gas': 1000000,
        'gasPrice': w3.eth.gas_price
    })

    # Sign and send raw transaction
    signed_txn = w3.eth.account.sign_transaction(txn, private_key)
    tx_hash = w3.eth.send_raw_transaction(signed_txn.rawTransaction)

    return tx_hash
