import os
from dotenv import load_dotenv
import json
from web3 import Web3
from flowMatrix import V2Pathfinder

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

# Get address for private key
account = w3.eth.account.from_key(PRIVATE_KEY)
print(f"From address: {account.address}")

def operate_flow_matrix(w3, hub_contract, account, private_key, flow_matrix):
    # Convert flow vertices to checksum addresses
    flow_vertices = [Web3.to_checksum_address(addr) for addr in flow_matrix.flow_vertices]

    # Prepare the transaction
    flow_matrix_tx = hub_contract.functions.operateFlowMatrix(
        flow_vertices,
        [(e.stream_sink_id, e.amount) for e in flow_matrix.flow_edges],
        [(s.source_coordinate, s.flow_edge_ids, s.data) for s in flow_matrix.streams],
        flow_matrix.packed_coordinates
    ).build_transaction({
        'from': account.address,
        'nonce': w3.eth.get_transaction_count(account.address),
        'gas': 500000,
        'gasPrice': w3.eth.gas_price
    })

    # Sign and send the transaction
    signed_tx = w3.eth.account.sign_transaction(flow_matrix_tx, private_key)
    tx_hash = w3.eth.send_raw_transaction(signed_tx.rawTransaction)
    print(f"Transaction sent: {tx_hash.hex()}")

    # Wait for transaction receipt
    tx_receipt = w3.eth.wait_for_transaction_receipt(tx_hash)
    print(f"Transaction confirmed in block {tx_receipt['blockNumber']}")

    return tx_receipt

def ensure_self_approval(w3, hub_contract, account, private_key):
    # Check if account is already self-approved
    is_approved = hub_contract.functions.isApprovedForAll(account.address, account.address).call()

    if not is_approved:
        # Build approval transaction
        approve_tx = hub_contract.functions.setApprovalForAll(account.address, True).build_transaction({
            'from': account.address,
            'nonce': w3.eth.get_transaction_count(account.address),
            'gas': 500000,
            'gasPrice': w3.eth.gas_price
        })

        # Sign and send transaction
        signed_tx = w3.eth.account.sign_transaction(approve_tx, private_key)
        tx_hash = w3.eth.send_raw_transaction(signed_tx.rawTransaction)
        print(f"Self-approval transaction sent: {tx_hash.hex()}")

        # Wait for transaction receipt
        tx_receipt = w3.eth.wait_for_transaction_receipt(tx_hash)
        print(f"Self-approval confirmed in block {tx_receipt['blockNumber']}")

        return tx_receipt

    print("Account already self-approved")
    return None

async def main():
    pathfinder = V2Pathfinder("https://rpc.aboutcircles.com/")

    # Get the flow matrix from the pathfinder
    flow_matrix = await pathfinder.get_args_for_path(
        account.address.lower(),
        CONTRACT_ADDRESS.lower(),
        "1000000000000000000" # 1 CRC
    )

    # Initialize the Hub contract
    hub_contract = w3.eth.contract(address=HUB_ADDRESS, abi=hub_abi)

    # Ensure account has self-approval before operating flow matrix
    ensure_self_approval(w3, hub_contract, account, PRIVATE_KEY)

    # Call the operate flow matrix function
    operate_flow_matrix(w3, hub_contract, account, PRIVATE_KEY, flow_matrix)

if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
