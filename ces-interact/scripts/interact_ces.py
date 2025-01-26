import os
from dotenv import load_dotenv
import json
import click
from web3 import Web3

# Load environment variables
load_dotenv()

# Connect to Gnosis Chain
w3 = Web3(Web3.HTTPProvider(os.getenv("RPC_URL_GNOSIS")))

# Load contract ABI
with open("abis/CESSupergroup.json") as f:
    contract_data = json.load(f)
    contract_abi = contract_data["abi"]

# Contract address on Gnosis Chain
with open("../deployments/CESSupergroup-gnosis.txt") as f:
    logs = json.load(f)
    # Load and convert to checksum address
    CONTRACT_ADDRESS = Web3.to_checksum_address(logs[0]["address"])
    print(f"Contract address: {CONTRACT_ADDRESS}")

# Create contract instance
contract = w3.eth.contract(address=CONTRACT_ADDRESS, abi=contract_abi)

# Helper functions
def get_account():
    private_key = os.getenv("PRIVATE_KEY_GNOSIS")
    account = w3.eth.account.from_key(private_key)
    return account

@click.group()
def cli():
    """CES Supergroup Interaction CLI"""
    pass

@cli.command()
def get_owner():
    """Get contract owner"""
    owner = contract.functions.owner().call()
    click.echo(f"Owner: {owner}")

@cli.command()
def get_service():
    """Get service address"""
    service = contract.functions.service().call()
    click.echo(f"Service: {service}")

@cli.command()
def get_operators():
    """Get list of operators"""
    operators = contract.functions.getOperators().call()
    click.echo("Operators:")
    for op in operators:
        click.echo(op)

@cli.command()
def get_mint_fee():
    """Get current mint fee"""
    fee = contract.functions.mintFee().call()
    click.echo(f"Mint fee: {fee}")

@cli.command()
def get_fee_collection():
    """Get fee collection address"""
    address = contract.functions.feeCollection().call()
    click.echo(f"Fee collection address: {address}")

@cli.command()
def get_redemption_burn_ratio():
    """Get redemption burn ratio"""
    ratio = contract.functions.redemptionBurnRatio().call()
    click.echo(f"Redemption burn ratio: {ratio}")

@cli.command()
def get_require_operator():
    """Get whether operators are required"""
    required = contract.functions.requireOperator().call()
    click.echo(f"Operators required: {required}")

@cli.command()
def get_return_circles_to_sender():
    """Get whether group circles return to sender"""
    returns = contract.functions.returnGroupCirclesToSender().call()
    click.echo(f"Return circles to sender: {returns}")

@cli.command()
@click.argument("address")
def is_authorized_operator(address):
    """Check if address is authorized operator"""
    is_auth = contract.functions.isAuthorizedOperator(address).call()
    click.echo(f"Is authorized: {is_auth}")

@cli.command()
@click.argument("operator")
@click.argument("authorized", type=bool)
def set_authorized_operator(operator, authorized):
    """Set operator authorization"""
    account = get_account()

    operator = Web3.to_checksum_address(operator)

    txn = contract.functions.setAuthorizedOperator(operator, authorized).build_transaction({
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
@click.argument("fee", type=int)
@click.argument("collection_address")
def set_mint_fee(fee, collection_address):
    """Set mint fee and collection address"""
    account = get_account()

    collection_address = Web3.to_checksum_address(collection_address)

    txn = contract.functions.setMintFee(fee, collection_address).build_transaction({
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
@click.argument("ratio", type=int)
def set_redemption_burn(ratio):
    """Set redemption burn ratio"""
    account = get_account()

    txn = contract.functions.setRedemptionBurn(ratio).build_transaction({
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
@click.argument("required", type=bool)
def set_require_operators(required):
    """Set whether operators are required"""
    account = get_account()

    txn = contract.functions.setRequireOperators(required).build_transaction({
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
@click.argument("return_circles", type=bool)
def set_return_circles_to_sender(return_circles):
    """Set whether to return group circles to sender"""
    account = get_account()

    txn = contract.functions.setReturnGroupCirclesToSender(return_circles).build_transaction({
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
@click.argument("service_address")
def set_service(service_address):
    """Set service address"""
    account = get_account()

    service_address = Web3.to_checksum_address(service_address)

    txn = contract.functions.setService(service_address).build_transaction({
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
@click.argument('backers', nargs=-1, required=True)
@click.option('--expiry', '-e', type=int, required=False, help='Optional expiry timestamp')
def trust_batch(backers, expiry):
    """Trust batch of addresses with expiry

    BACKERS: One or more Ethereum addresses to trust, separated by spaces
             e.g. trust_batch 0x123... 0x456... 0x789...

    --expiry: Optional timestamp for trust expiration (defaults to max uint96)
    """
    account = get_account()

    if expiry is None:
        expiry = 2**96 - 1  # max uint96

    backers = [Web3.to_checksum_address(backer) for backer in backers]

    txn = contract.functions.trustBatch(list(backers), expiry).build_transaction({
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
