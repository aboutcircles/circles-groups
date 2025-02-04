import time
import json
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
        cache_ttl: int = 300  # 5 minutes default TTL
    ):
        self.web3 = Web3(Web3.HTTPProvider(nethermind_client.rpc_url))
        if not self.web3.is_connected():
            raise ConnectionError("Failed to connect to Gnosis Chain node.")

        self.nethermind_client = nethermind_client
        self.screening_client = screening_client
        self.supergroup_address = supergroup_address.lower()
        self.private_key = private_key
        self.cache_ttl = cache_ttl

        # Initialize on-chain state
        self._trusted_accounts, self._last_trust_block = self.nethermind_client.fetch_group_trust_relations(self.supergroup_address)
        self._backers, self._last_backer_block = self.nethermind_client.fetch_backers()
        print(f"Initialized with {len(self._trusted_accounts)} trusted accounts from block {self._last_trust_block}")
        print(f"Initialized with {len(self._backers)} backers from block {self._last_backer_block}")

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

    def _sync_state(self):
            """Sync local state with current blockchain state"""
            current_block = self.web3.eth.block_number

            # Sync trust relations if behind
            if current_block > self._last_trust_block:
                print(f"Syncing trust relations from block {self._last_trust_block} to {current_block}")
                new_trusted, latest_block = self.nethermind_client.fetch_group_trust_relations(
                    self.supergroup_address,
                    self._last_trust_block
                )
                self._trusted_accounts.update(new_trusted)
                self._last_trust_block = latest_block

            # Sync backers if behind
            if current_block > self._last_backer_block:
                print(f"Syncing backers from block {self._last_backer_block} to {current_block}")
                new_backers, latest_block = self.nethermind_client.fetch_backers()
                self._backers.update(new_backers)
                self._last_backer_block = latest_block

    def run_trust_management(self):
           current_block = self.web3.eth.block_number
           print(f"\nProcessing trust management for block {current_block}")

           # Ensure we're synced with current blockchain state
           self._sync_state()

           # Process new backers
           new_backers = self._backers - self._trusted_accounts
           print(f"Found {len(new_backers)} new backers not yet trusted")

           if not new_backers:
               print("No new backers to process")
               return

           # Screen new backers against blacklist
           blacklisted = set(self.screening_client.check_blacklist(list(new_backers)))
           valid_backers = new_backers - blacklisted

           if blacklisted:
               print(f"Filtered out {len(blacklisted)} blacklisted addresses")

           if not valid_backers:
               print("No valid backers to trust after screening")
               return

           # Trust valid backers - convert to string set for type compatibility
           checksum_backers = {str(Web3.to_checksum_address(backer)) for backer in valid_backers}
           print(f"Adding {len(checksum_backers)} addresses to trust batch")

           try:
               self.call_trust_batch(checksum_backers)
               # Update local state only after successful on-chain transaction
               self._trusted_accounts.update(valid_backers)
               print("Successfully updated on-chain trust relationships")
           except Exception as e:
               print(f"Failed to execute trust batch: {e}")


    def call_trust_batch(self, checksum_backers: set[str]):
        """Execute on-chain trust batch transaction"""
        try:
            expiry = 2**96 - 1  # max uint96
            account = self.web3.eth.account.from_key(self.private_key)

            transaction = self.supergroup_contract.functions.trustBatch(
                list(checksum_backers), expiry
            ).build_transaction({
                "from": account.address,
                "nonce": self.web3.eth.get_transaction_count(account.address),
                "gas": 500000,
                "gasPrice": self.web3.eth.gas_price,
            })

            signed_tx = self.web3.eth.account.sign_transaction(transaction, private_key=self.private_key)
            tx_hash = self.web3.eth.send_raw_transaction(signed_tx.raw_transaction)
            print(f"Trust batch transaction sent: {tx_hash.hex()}")

            receipt = self.web3.eth.wait_for_transaction_receipt(tx_hash)
            print(f"Transaction confirmed in block {receipt['blockNumber']}")

            return receipt
        except Exception as e:
            raise Exception(f"Trust batch transaction failed: {str(e)}")

    def flush(self):
        """Reset the algorithm state"""
        self._trusted_accounts, self._last_trust_block = self.nethermind_client.fetch_group_trust_relations(self.supergroup_address)
        self._backers, self._last_backer_block = self.nethermind_client.fetch_backers()
        print(f"Reset state with {len(self._trusted_accounts)} trusted accounts from block {self._last_trust_block}")
        print(f"Reset state with {len(self._backers)} backers from block {self._last_backer_block}")


class PollingService:
    def __init__(self, nethermind_client: NethermindClient, poll_interval: int = 15):
        self.nethermind_client = nethermind_client
        self.web3 = Web3(Web3.HTTPProvider(nethermind_client.rpc_url))
        self.poll_interval = poll_interval

        if not self.web3.is_connected():
            raise ConnectionError("Failed to connect to the blockchain")

    def start_polling(self, trust_management_algorithm: TrustManagementAlgorithm):
        """Start polling for new blocks"""
        latest_block_number = None

        while True:
            try:
                current_block_number = self.web3.eth.block_number

                if current_block_number != latest_block_number:
                    latest_block_number = current_block_number
                    print(f"\nProcessing new block: {latest_block_number}")
                    trust_management_algorithm.run_trust_management()

                time.sleep(self.poll_interval)
            except Exception as e:
                print(f"Polling error: {e}")
                time.sleep(self.poll_interval)
