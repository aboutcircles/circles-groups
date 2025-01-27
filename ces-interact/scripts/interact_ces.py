import os
from dotenv import load_dotenv
import json
import click
from web3 import Web3

def ensure_abi_files():
    """Helper function to check for and copy required ABI files"""
    required_abis = ["CESgroup.json", "CMAncillary.json"]

    if not os.path.exists("abis"):
        os.makedirs("abis")

    # Check if any required ABI is missing
    missing_abis = False
    for abi_file in required_abis:
        abi_path = os.path.join("abis", abi_file)
        if not os.path.exists(abi_path):
            missing_abis = True
            break

    # Run copyAbis.sh if any ABI is missing
    if missing_abis:
        print("Running copyAbis.sh to copy required ABIs...")
        if os.system("../scripts/copyAbis.sh") != 0:
            raise Exception("Failed to run copyAbis.sh")

        # Verify ABIs were copied successfully
        for abi_file in required_abis:
            abi_path = os.path.join("abis", abi_file)
            if not os.path.exists(abi_path):
                raise Exception(f"Failed to copy required ABI file: {abi_file}")

#==================================================================

# Load environment variables
load_dotenv()

# Connect to Gnosis Chain
w3 = Web3(Web3.HTTPProvider(os.getenv("RPC_URL_GNOSIS")))

# Ensure ABI files are available
ensure_abi_files()

# Load contract ABIs
with open("abis/CESgroup.json") as f:
    group_data = json.load(f)
    group_abi = group_data["abi"]

with open("abis/CMAncillary.json") as f:
    ancillary_data = json.load(f)
    ancillary_abi = ancillary_data["abi"]

# Contract addresses on Gnosis Chain
with open("../deployments/CESGroup-gnosis.txt") as f:
    deployment_logs = json.loads(f.read())
    # Get the address from the first log entry
    group_address = deployment_logs[0]["address"]
    GROUP_ADDRESS = Web3.to_checksum_address(group_address)
    print(f"Group address: {GROUP_ADDRESS}")

# Create contract instances
group = w3.eth.contract(address=GROUP_ADDRESS, abi=group_abi)
ancillary = w3.eth.contract(address=group.functions.ancillary().call(), abi=ancillary_abi)

# Helper functions
def get_account():
    private_key = os.getenv("PRIVATE_KEY_GNOSIS")
    account = w3.eth.account.from_key(private_key)
    return account

@click.group()
def cli():
    """CES Group Interaction CLI"""
    pass

@cli.command()
def get_owner():
    """Get contract owner"""
    owner = group.functions.owner().call()
    click.echo(f"Owner: {owner}")

@cli.command()
def get_service():
    """Get service address"""
    service = group.functions.service().call()
    click.echo(f"Service: {service}")

@cli.command()
def get_ancillary():
    """Get ancillary contract address"""
    ancillary_addr = group.functions.ancillary().call()
    click.echo(f"Ancillary: {ancillary_addr}")

@cli.command()
@click.argument("service_address")
def set_service(service_address):
    """Set service address for both contracts"""
    account = get_account()

    service_address = Web3.to_checksum_address(service_address)

    # Set service on group contract
    txn = group.functions.setService(service_address).build_transaction({
        'from': account.address,
        'nonce': w3.eth.get_transaction_count(account.address),
        'gas': 200000,
        'gasPrice': w3.eth.gas_price
    })

    signed_txn = w3.eth.account.sign_transaction(txn, account.key)
    tx_hash = w3.eth.send_raw_transaction(signed_txn.rawTransaction)
    _ = w3.eth.wait_for_transaction_receipt(tx_hash)

    click.echo(f"Group service update transaction hash: {tx_hash.hex()}")

@cli.command()
@click.argument("ancillary_address")
def set_ancillary(ancillary_address):
    """Set ancillary contract address"""
    account = get_account()

    ancillary_address = Web3.to_checksum_address(ancillary_address)

    txn = group.functions.setAncillary(ancillary_address).build_transaction({
        'from': account.address,
        'nonce': w3.eth.get_transaction_count(account.address),
        'gas': 200000,
        'gasPrice': w3.eth.gas_price
    })

    signed_txn = w3.eth.account.sign_transaction(txn, account.key)
    tx_hash = w3.eth.send_raw_transaction(signed_txn.rawTransaction)
    _ = w3.eth.wait_for_transaction_receipt(tx_hash)

    click.echo(f"Transaction hash: {tx_hash.hex()}")

@cli.command()
@click.argument('addresses', nargs=-1, required=True)
def sync_trust(addresses):
    """Sync trust relationships from group to ancillary for given addresses"""
    account = get_account()

    addresses = [Web3.to_checksum_address(addr) for addr in addresses]

    txn = ancillary.functions.syncTrust(list(addresses)).build_transaction({
        'from': account.address,
        'nonce': w3.eth.get_transaction_count(account.address),
        'gas': 500000,
        'gasPrice': w3.eth.gas_price
    })

    signed_txn = w3.eth.account.sign_transaction(txn, account.key)
    tx_hash = w3.eth.send_raw_transaction(signed_txn.rawTransaction)
    _ = w3.eth.wait_for_transaction_receipt(tx_hash)

    click.echo(f"Transaction hash: {tx_hash.hex()}")

@cli.command()
@click.argument('backers', nargs=-1, required=True)
@click.option('--expiry', '-e', type=int, required=False, help='Optional expiry timestamp')
def trust_batch(backers, expiry):
    """Trust batch of addresses with expiry in both group and ancillary

    BACKERS: One or more Ethereum addresses to trust, separated by spaces
             e.g. trust_batch 0x123... 0x456... 0x789...

    --expiry: Optional timestamp for trust expiration (defaults to max uint96)
    """
    account = get_account()

    if expiry is None:
        expiry = 2**96 - 1  # max uint96

    backers = [Web3.to_checksum_address(backer) for backer in backers]

    txn = group.functions.trustBatch(list(backers), expiry).build_transaction({
        'from': account.address,
        'nonce': w3.eth.get_transaction_count(account.address),
        'gas': 500000,
        'gasPrice': w3.eth.gas_price
    })

    signed_txn = w3.eth.account.sign_transaction(txn, account.key)
    tx_hash = w3.eth.send_raw_transaction(signed_txn.rawTransaction)
    _ = w3.eth.wait_for_transaction_receipt(tx_hash)

    click.echo(f"Transaction hash: {tx_hash.hex()}")

if __name__ == "__main__":
    cli()
