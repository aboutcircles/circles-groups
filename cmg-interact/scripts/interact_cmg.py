import os
from dotenv import load_dotenv
import json
import click
from web3 import Web3

def ensure_abi_files():
    """Helper function to check for and copy required ABI files"""
    required_abis = ["CoreMembersGroup.json", "CMGMintHandler.json", "CMGRedemptionHandler.json"]

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
with open("abis/CoreMembersGroup.json") as f:
    group_data = json.load(f)
    group_abi = group_data["abi"]

with open("abis/CMGMintHandler.json") as f:
    mint_handler_data = json.load(f)
    mint_handler_abi = mint_handler_data["abi"]

with open("abis/CMGRedemptionHandler.json") as f:
    redemption_handler_data = json.load(f)
    redemption_handler_abi = redemption_handler_data["abi"]

# Contract addresses on Gnosis Chain
with open("../deployments/CMGroup-gnosis.txt") as f:
    deployment_logs = json.loads(f.read())
    group_address = deployment_logs[0]["address"]
    GROUP_ADDRESS = Web3.to_checksum_address(group_address)
    print(f"Group address: {GROUP_ADDRESS}")

# Create contract instances
group = w3.eth.contract(address=GROUP_ADDRESS, abi=group_abi)
mint_handler = w3.eth.contract(address=group.functions.mintHandler().call(), abi=mint_handler_abi)
redemption_handler = w3.eth.contract(address=group.functions.redemptionHandler().call(), abi=redemption_handler_abi)

# Helper functions
def get_account():
    private_key = os.getenv("PRIVATE_KEY_GNOSIS")
    account = w3.eth.account.from_key(private_key)
    return account

@click.group()
def cli():
    """Core Members Group Interaction CLI"""
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
def get_handlers():
    """Get mint and redemption handler addresses"""
    mint = group.functions.mintHandler().call()
    redemption = group.functions.redemptionHandler().call()
    click.echo(f"Mint Handler: {mint}")
    click.echo(f"Redemption Handler: {redemption}")

@cli.command()
def get_minimal_deposit():
    """Get minimal deposit amount"""
    amount = group.functions.minimalDeposit().call()
    click.echo(f"Minimal Deposit: {amount}")

@cli.command()
def get_fee_collection():
    """Get fee collection address"""
    addr = group.functions.feeCollection().call()
    click.echo(f"Fee Collection Address: {addr}")

@cli.command()
@click.argument("service_address")
def set_service(service_address):
    """Set service address"""
    account = get_account()

    service_address = Web3.to_checksum_address(service_address)

    txn = group.functions.setService(service_address).build_transaction({
        'from': account.address,
        'nonce': w3.eth.get_transaction_count(account.address),
        'gas': 200000,
        'gasPrice': w3.eth.gas_price
    })

    signed_txn = w3.eth.account.sign_transaction(txn, account.key)
    tx_hash = w3.eth.send_raw_transaction(signed_txn.raw_transaction)
    _ = w3.eth.wait_for_transaction_receipt(tx_hash)

    click.echo(f"Service update transaction hash: {tx_hash.hex()}")

@cli.command()
@click.argument("mint_handler_address")
def set_mint_handler(mint_handler_address):
    """Set mint handler contract address"""
    account = get_account()

    mint_handler_address = Web3.to_checksum_address(mint_handler_address)

    txn = group.functions.setMintHandler(mint_handler_address).build_transaction({
        'from': account.address,
        'nonce': w3.eth.get_transaction_count(account.address),
        'gas': 200000,
        'gasPrice': w3.eth.gas_price
    })

    signed_txn = w3.eth.account.sign_transaction(txn, account.key)
    tx_hash = w3.eth.send_raw_transaction(signed_txn.raw_transaction)
    _ = w3.eth.wait_for_transaction_receipt(tx_hash)

    click.echo(f"Transaction hash: {tx_hash.hex()}")

@cli.command()
@click.argument("redemption_handler_address")
def set_redemption_handler(redemption_handler_address):
    """Set redemption handler contract address"""
    account = get_account()

    redemption_handler_address = Web3.to_checksum_address(redemption_handler_address)

    txn = group.functions.setRedemptionHandler(redemption_handler_address).build_transaction({
        'from': account.address,
        'nonce': w3.eth.get_transaction_count(account.address),
        'gas': 200000,
        'gasPrice': w3.eth.gas_price
    })

    signed_txn = w3.eth.account.sign_transaction(txn, account.key)
    tx_hash = w3.eth.send_raw_transaction(signed_txn.raw_transaction)
    _ = w3.eth.wait_for_transaction_receipt(tx_hash)

    click.echo(f"Transaction hash: {tx_hash.hex()}")

@cli.command()
@click.argument("minimal_deposit", type=int)
def set_minimal_deposit(minimal_deposit):
    """Set minimal deposit amount"""
    account = get_account()

    txn = group.functions.setMinimalDeposit(minimal_deposit).build_transaction({
        'from': account.address,
        'nonce': w3.eth.get_transaction_count(account.address),
        'gas': 200000,
        'gasPrice': w3.eth.gas_price
    })

    signed_txn = w3.eth.account.sign_transaction(txn, account.key)
    tx_hash = w3.eth.send_raw_transaction(signed_txn.raw_transaction)
    _ = w3.eth.wait_for_transaction_receipt(tx_hash)

    click.echo(f"Transaction hash: {tx_hash.hex()}")

@cli.command()
@click.argument("fee_collection_address")
def set_fee_collection(fee_collection_address):
    """Set fee collection address"""
    account = get_account()

    fee_collection_address = Web3.to_checksum_address(fee_collection_address)

    txn = group.functions.setFeeCollection(fee_collection_address).build_transaction({
        'from': account.address,
        'nonce': w3.eth.get_transaction_count(account.address),
        'gas': 200000,
        'gasPrice': w3.eth.gas_price
    })

    signed_txn = w3.eth.account.sign_transaction(txn, account.key)
    tx_hash = w3.eth.send_raw_transaction(signed_txn.raw_transaction)
    _ = w3.eth.wait_for_transaction_receipt(tx_hash)

    click.echo(f"Transaction hash: {tx_hash.hex()}")

@cli.command()
@click.argument("condition_address")
@click.argument("enabled", type=bool)
def set_membership_condition(condition_address, enabled):
    """Enable/disable membership condition"""
    account = get_account()

    condition_address = Web3.to_checksum_address(condition_address)

    txn = group.functions.setMembershipCondition(condition_address, enabled).build_transaction({
        'from': account.address,
        'nonce': w3.eth.get_transaction_count(account.address),
        'gas': 200000,
        'gasPrice': w3.eth.gas_price
    })

    signed_txn = w3.eth.account.sign_transaction(txn, account.key)
    tx_hash = w3.eth.send_raw_transaction(signed_txn.raw_transaction)
    _ = w3.eth.wait_for_transaction_receipt(tx_hash)

    click.echo(f"Transaction hash: {tx_hash.hex()}")

@cli.command()
@click.argument("trust_receiver")
@click.option('--expiry', '-e', type=int, required=False, help='Optional expiry timestamp')
def trust(trust_receiver, expiry):
    """Trust a single address with expiry"""
    account = get_account()

    if expiry is None:
        expiry = 2**96 - 1  # max uint96

    trust_receiver = Web3.to_checksum_address(trust_receiver)

    txn = group.functions.trust(trust_receiver, expiry).build_transaction({
        'from': account.address,
        'nonce': w3.eth.get_transaction_count(account.address),
        'gas': 200000,
        'gasPrice': w3.eth.gas_price
    })

    signed_txn = w3.eth.account.sign_transaction(txn, account.key)
    tx_hash = w3.eth.send_raw_transaction(signed_txn.raw_transaction)
    _ = w3.eth.wait_for_transaction_receipt(tx_hash)

    click.echo(f"Transaction hash: {tx_hash.hex()}")

@cli.command()
@click.argument('addresses', nargs=-1, required=True)
@click.option('--expiry', '-e', type=int, required=False, help='Optional expiry timestamp')
def trust_batch(addresses, expiry):
    """Trust batch of addresses with expiry

    ADDRESSES: One or more Ethereum addresses to trust, separated by spaces
              e.g. trust_batch 0x123... 0x456... 0x789...

    --expiry: Optional timestamp for trust expiration (defaults to max uint96)
    """
    account = get_account()

    if expiry is None:
        expiry = 2**96 - 1  # max uint96

    addresses = [Web3.to_checksum_address(addr) for addr in addresses]

    txn = group.functions.trustBatch(list(addresses), expiry).build_transaction({
        'from': account.address,
        'nonce': w3.eth.get_transaction_count(account.address),
        'gas': 5000000,
        'gasPrice': w3.eth.gas_price
    })

    signed_txn = w3.eth.account.sign_transaction(txn, account.key)
    tx_hash = w3.eth.send_raw_transaction(signed_txn.raw_transaction)
    _ = w3.eth.wait_for_transaction_receipt(tx_hash)

    click.echo(f"Transaction hash: {tx_hash.hex()}")

@cli.command()
@click.argument("flag")
def set_advanced_usage_flag(flag):
    """Set advanced usage flag"""
    account = get_account()

    # Convert string to bytes32
    flag_bytes = Web3.to_bytes(hexstr=flag)

    txn = group.functions.setAdvancedUsageFlag(flag_bytes).build_transaction({
        'from': account.address,
        'nonce': w3.eth.get_transaction_count(account.address),
        'gas': 200000,
        'gasPrice': w3.eth.gas_price
    })

    signed_txn = w3.eth.account.sign_transaction(txn, account.key)
    tx_hash = w3.eth.send_raw_transaction(signed_txn.raw_transaction)
    _ = w3.eth.wait_for_transaction_receipt(tx_hash)

    click.echo(f"Transaction hash: {tx_hash.hex()}")

@cli.command()
@click.argument("metadata_digest")
def update_metadata_digest(metadata_digest):
    """Update metadata digest"""
    account = get_account()

    # Convert string to bytes32
    digest_bytes = Web3.to_bytes(hexstr=metadata_digest)

    txn = group.functions.updateMetadataDigest(digest_bytes).build_transaction({
        'from': account.address,
        'nonce': w3.eth.get_transaction_count(account.address),
        'gas': 200000,
        'gasPrice': w3.eth.gas_price
    })

    signed_txn = w3.eth.account.sign_transaction(txn, account.key)
    tx_hash = w3.eth.send_raw_transaction(signed_txn.raw_transaction)
    _ = w3.eth.wait_for_transaction_receipt(tx_hash)

    click.echo(f"Transaction hash: {tx_hash.hex()}")

@cli.command()
def register_short_name():
    """Register short name for all contracts"""
    account = get_account()

    # Register for core group contract
    txn = group.functions.registerShortName().build_transaction({
        'from': account.address,
        'nonce': w3.eth.get_transaction_count(account.address),
        'gas': 200000,
        'gasPrice': w3.eth.gas_price
    })

    signed_txn = w3.eth.account.sign_transaction(txn, account.key)
    tx_hash = w3.eth.send_raw_transaction(signed_txn.raw_transaction)
    _ = w3.eth.wait_for_transaction_receipt(tx_hash)

    click.echo(f"Group contract transaction hash: {tx_hash.hex()}")

    # Register for mint handler contract
    txn = mint_handler.functions.registerShortName().build_transaction({
        'from': account.address,
        'nonce': w3.eth.get_transaction_count(account.address),
        'gas': 200000,
        'gasPrice': w3.eth.gas_price
    })

    signed_txn = w3.eth.account.sign_transaction(txn, account.key)
    tx_hash = w3.eth.send_raw_transaction(signed_txn.raw_transaction)
    _ = w3.eth.wait_for_transaction_receipt(tx_hash)

    click.echo(f"Mint handler transaction hash: {tx_hash.hex()}")

    # Register for redemption handler contract
    txn = redemption_handler.functions.registerShortName().build_transaction({
        'from': account.address,
        'nonce': w3.eth.get_transaction_count(account.address),
        'gas': 200000,
        'gasPrice': w3.eth.gas_price
    })

    signed_txn = w3.eth.account.sign_transaction(txn, account.key)
    tx_hash = w3.eth.send_raw_transaction(signed_txn.raw_transaction)
    _ = w3.eth.wait_for_transaction_receipt(tx_hash)

    click.echo(f"Redemption handler transaction hash: {tx_hash.hex()}")

@cli.command()
@click.argument("nonce", type=int)
def register_short_name_with_nonce(nonce):
    """Register short name with nonce"""
    account = get_account()

    txn = group.functions.registerShortNameWithNonce(nonce).build_transaction({
        'from': account.address,
        'nonce': w3.eth.get_transaction_count(account.address),
        'gas': 200000,
        'gasPrice': w3.eth.gas_price
    })

    signed_txn = w3.eth.account.sign_transaction(txn, account.key)
    tx_hash = w3.eth.send_raw_transaction(signed_txn.raw_transaction)
    _ = w3.eth.wait_for_transaction_receipt(tx_hash)

    click.echo(f"Transaction hash: {tx_hash.hex()}")

@cli.command()
@click.argument('addresses', nargs=-1, required=True)
def sync_trust(addresses):
    """Sync trust relationships from CM group to mint handler"""
    account = get_account()

    addresses = [Web3.to_checksum_address(addr) for addr in addresses]

    txn = mint_handler.functions.syncTrust(addresses).build_transaction({
        'from': account.address,
        'nonce': w3.eth.get_transaction_count(account.address),
        'gas': 500000,
        'gasPrice': w3.eth.gas_price
    })

    signed_txn = w3.eth.account.sign_transaction(txn, account.key)
    tx_hash = w3.eth.send_raw_transaction(signed_txn.raw_transaction)
    _ = w3.eth.wait_for_transaction_receipt(tx_hash)

    click.echo(f"Transaction hash: {tx_hash.hex()}")

@cli.command()
@click.argument("group_address")
@click.argument("amount", type=int)
@click.option("--partial/--no-partial", default=False, help="Allow partial fills")
def find_collateral(group_address, amount, partial):
    """Find available collateral for redemption"""
    group_address = Web3.to_checksum_address(group_address)

    result = redemption_handler.functions.findCollateral(
        group_address,
        amount,
        partial
    ).call()

    click.echo(f"Found collateral IDs: {result[0]}")
    click.echo(f"Found amounts: {result[1]}")

@cli.command()
@click.argument("group_address")
@click.argument("redemption_ids", nargs=-1, type=int)
@click.argument("redemption_values", nargs=-1, type=int)
def redeem(group_address, redemption_ids, redemption_values):
    """Redeem collateral from group"""
    account = get_account()

    if len(redemption_ids) != len(redemption_values):
        raise click.BadParameter("Number of IDs must match number of values")

    group_address = Web3.to_checksum_address(group_address)

    txn = redemption_handler.functions.redeem(
        group_address,
        list(redemption_ids),
        list(redemption_values)
    ).build_transaction({
        'from': account.address,
        'nonce': w3.eth.get_transaction_count(account.address),
        'gas': 500000,
        'gasPrice': w3.eth.gas_price
    })

    signed_txn = w3.eth.account.sign_transaction(txn, account.key)
    tx_hash = w3.eth.send_raw_transaction(signed_txn.raw_transaction)
    _ = w3.eth.wait_for_transaction_receipt(tx_hash)

    click.echo(f"Transaction hash: {tx_hash.hex()}")

@cli.command()
@click.argument("collateral_ids", nargs=-1, type=int)
def sync_valid_collateral(collateral_ids):
    """Sync status of collateral IDs"""
    account = get_account()

    txn = redemption_handler.functions.syncValidCollateral(list(collateral_ids)).build_transaction({
        'from': account.address,
        'nonce': w3.eth.get_transaction_count(account.address),
        'gas': 500000,
        'gasPrice': w3.eth.gas_price
    })

    signed_txn = w3.eth.account.sign_transaction(txn, account.key)
    tx_hash = w3.eth.send_raw_transaction(signed_txn.raw_transaction)
    _ = w3.eth.wait_for_transaction_receipt(tx_hash)

    click.echo(f"Transaction hash: {tx_hash.hex()}")

if __name__ == "__main__":
    cli()
