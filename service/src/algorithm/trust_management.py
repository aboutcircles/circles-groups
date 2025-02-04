import time
import json
from typing import Set
from web3 import Web3
from clients.nethermind import NethermindClient
from clients.screening import ScreeningClient
from config.settings import settings

class TrustManagementAlgorithm:
    def __init__(
        self,
        nethermind_client: NethermindClient,
        screening_client: ScreeningClient,
        supergroup_address: str,
        private_key: str,
        supergroup_contract_address: str,
    ):

        self.web3 = Web3(Web3.HTTPProvider(nethermind_client.rpc_url))  # Initialize Web3 instance
        if not self.web3.is_connected():
            raise ConnectionError("Failed to connect to Gnosis Chain node.")

        self.nethermind_client = nethermind_client
        self.screening_client = screening_client
        self.supergroup_address = supergroup_address
        self.private_key = private_key

        # Simple in-memory cache
        self._trusted_accounts = None
        self._last_fetch_time = 0
        self.cache_ttl = 300  # 5 minutes

        # Initialize contract
        self._initialize_contract(supergroup_contract_address)

    def _initialize_contract(self, contract_address: str):
        try:
            with open(settings.supergroup_abi_path, "r") as file:
                contract_abi = json.load(file)

            self.supergroup_contract_address = self.web3.to_checksum_address(contract_address)
            self.supergroup_contract = self.web3.eth.contract(
                address=self.supergroup_contract_address,
                abi=contract_abi
            )
        except Exception as e:
            raise RuntimeError(f"Failed to initialize contract: {str(e)}")

    def load_initial_accounts(self):
        """Initial load of trusted accounts"""
        try:
            accounts = self.nethermind_client.fetch_group_trust_relations(
                self.supergroup_address.lower()
            )
            self._trusted_accounts = set(accounts) if accounts else set()
            self._last_fetch_time = time.time()
            print(f"Initially loaded {len(self._trusted_accounts)} trusted accounts")
        except Exception as e:
            print(f"Error loading initial trusted accounts: {str(e)}")
            self._trusted_accounts = set()

    @property
    def trusted_accounts(self) -> Set[str]:
        """Get trusted accounts with cache handling"""
        current_time = time.time()
        if self._trusted_accounts is None or (current_time - self._last_fetch_time) > self.cache_ttl:
            try:
                accounts = self.nethermind_client.fetch_group_trust_relations(
                    self.supergroup_address.lower()
                )
                self._trusted_accounts = set(accounts) if accounts else set()
                self._last_fetch_time = current_time
                print(f"Refreshed cache: {len(self._trusted_accounts)} trusted accounts")
            except Exception as e:
                print(f"Error fetching trusted accounts: {str(e)}")
                if self._trusted_accounts is None:
                    self._trusted_accounts = set()
        return self._trusted_accounts

    def run_trust_management(self):
            # Step 1: Fetch the list of backers from the completed LBP events
            backers = set(self.nethermind_client.fetch_backers())
            current_trusted = self.trusted_accounts
            # Step 2: Subtract the trusted accounts from the backers list
            new_backers = backers - current_trusted
            if not new_backers:
                print("No new backers found")
                return

            # Step 3: Check each backer against the blacklist service
            blacklist = self.screening_client.check_blacklist(list(new_backers))

            # Step 4: Add valid backers (those not in the blacklist) to the trusted accounts
            valid_backers = new_backers - set(blacklist)

            # Convert to checksum addresses
            checksum_backers: Set[str] = {Web3.to_checksum_address(backer) for backer in valid_backers}

            # Step 5: Call the `trustBatch` function to update on-chain trust relations
            if checksum_backers:
                print(f"Adding {len(checksum_backers)} addresses to trust batch")
                self.call_trust_batch(checksum_backers)  # Convert to Set[str]
                # Update cache after successful trust batch
                self._trusted_accounts = current_trusted | valid_backers
                self._last_fetch_time = time.time()
            else:
                print("No valid backers to trust")

    def call_trust_batch(self, checksum_backers: Set[str]):
        """Call the `trustBatch` function on the supergroup contract."""
        try:
            expiry = 2**96 - 1  # max uint96
            account = self.web3.eth.account.from_key(self.private_key)

            # Build the transaction
            transaction = self.supergroup_contract.functions.trustBatch(
                list(checksum_backers), expiry
            ).build_transaction({
                "from": account.address,
                "nonce": self.web3.eth.get_transaction_count(account.address),
                "gas": 500000,
                "gasPrice": self.web3.eth.gas_price,
            })

            # Sign the transaction
            signed_tx = self.web3.eth.account.sign_transaction(transaction, private_key=self.private_key)

            # Send the transaction
            tx_hash = self.web3.eth.send_raw_transaction(signed_tx.raw_transaction)
            print(f"Transaction sent: {tx_hash.hex()}")

            # Wait for the transaction receipt
            receipt = self.web3.eth.wait_for_transaction_receipt(tx_hash)
            print(f"Transaction confirmed in block {receipt['blockNumber']}")

        except Exception as e:
            print(f"Error calling trustBatch: {e}")

    def flush(self):
        self._trusted_accounts = set()  # Reset the trusted accounts set directly


class PollingService:
    def __init__(self, nethermind_client: NethermindClient, poll_interval: int = 15):
        self.nethermind_client = nethermind_client

        self.web3 = Web3(Web3.HTTPProvider(nethermind_client.rpc_url))
        self.poll_interval = poll_interval

        if not self.web3.is_connected():
            raise ConnectionError("Failed to connect to the blockchain. Check the RPC URL.")

    def start_polling(self, trust_management_algorithm: TrustManagementAlgorithm):
        """Start polling for new blocks and trigger trust management updates."""
        latest_block_number = None

        while True:
            try:
                # Get the latest block number
                current_block_number = self.web3.eth.block_number

                if current_block_number != latest_block_number:
                    latest_block_number = current_block_number
                    print(f"New block detected: {latest_block_number}")

                    # Trigger the trust management update process
                    trust_management_algorithm.run_trust_management()

                # Sleep for the polling interval
                time.sleep(self.poll_interval)

            except Exception as e:
                print(f"Error while polling blocks: {e}")
                time.sleep(self.poll_interval)  # Wait before retrying in case of error
