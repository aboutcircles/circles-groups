from typing import Optional
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
CONTRACT_ADDRESS = "0x..."

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

    txn = contract.functions.setAuthorizedOperator(operator, authorized).build_transaction({
        'from': account.address,
        'nonce': w3.eth.get_transaction_count(account.address),
        'gas': 200000,
        'gasPrice': w3.eth.gas_price
    })

    signed_txn = w3.eth.account.sign_transaction(txn, account.key)
    tx_hash = w3.eth.send_raw_transaction(signed_txn.rawTransaction)
    tx_receipt = w3.eth.wait_for_transaction_receipt(tx_hash)

    click.echo(f"Transaction hash: {tx_hash.hex()}")

@cli.command()
@click.argument("service_address")
def set_service(service_address):
    """Set service address"""
    account = get_account()

    txn = contract.functions.setService(service_address).build_transaction({
        'from': account.address,
        'nonce': w3.eth.get_transaction_count(account.address),
        'gas': 200000,
        'gasPrice': w3.eth.gas_price
    })

    signed_txn = w3.eth.account.sign_transaction(txn, account.key)
    tx_hash = w3.eth.send_raw_transaction(signed_txn.rawTransaction)
    tx_receipt = w3.eth.wait_for_transaction_receipt(tx_hash)

    click.echo(f"Transaction hash: {tx_hash.hex()}")

@cli.command()
@click.argument("backers", nargs=-1)
@click.argument("expiry", type=int)
def trust_batch(backers, expiry):
    """Trust batch of addresses with expiry"""
    account = get_account()

    txn = contract.functions.trustBatch(list(backers), expiry).build_transaction({
        'from': account.address,
        'nonce': w3.eth.get_transaction_count(account.address),
        'gas': 500000,
        'gasPrice': w3.eth.gas_price
    })

    signed_txn = w3.eth.account.sign_transaction(txn, account.key)
    tx_hash = w3.eth.send_raw_transaction(signed_txn.rawTransaction)
    tx_receipt = w3.eth.wait_for_transaction_receipt(tx_hash)

    click.echo(f"Transaction hash: {tx_hash.hex()}")

if __name__ == "__main__":
    cli()
