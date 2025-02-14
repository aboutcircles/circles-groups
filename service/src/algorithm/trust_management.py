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
            cache_ttl: int = 300
        ):
            self.web3 = Web3(Web3.HTTPProvider(nethermind_client.rpc_url))
            if not self.web3.is_connected():
                raise ConnectionError("Failed to connect to Gnosis Chain node.")

            self.nethermind_client = nethermind_client
            self.screening_client = screening_client
            self.supergroup_address = supergroup_address.lower()
            self.private_key = private_key
            self.cache_ttl = cache_ttl

            try:
                # Initialize on-chain state
                self._trusted_accounts, self._last_trust_block = self.nethermind_client.fetch_group_trust_relations(self.supergroup_address)
                self._last_processed_block = 0  # Track last processed block
                print(f"Initialized with {len(self._trusted_accounts)} trusted accounts from block {self._last_trust_block}")
            except AttributeError as e:
                print(f"Error initializing trust relations: {str(e)}")

                self._trusted_accounts = set()
                self._last_trust_block = 0
                self._last_processed_block = 0

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

        if current_block <= self._last_processed_block:
            return

        print(f"\nSyncing state for block {current_block}")

        # Fetch both initiated and completed backings
        fallback_pairs, completed_backers, latest_block = self.nethermind_client.fetch_backing_status()

        # Handle incomplete backings first
        if fallback_pairs:
            self._handle_incomplete_backings(fallback_pairs)

        # Then handle trust relations
        if current_block > self._last_trust_block:
            print(f"Syncing trust relations from block {self._last_trust_block} to {current_block}")
            new_trusted, latest_block = self.nethermind_client.fetch_group_trust_relations(
                self.supergroup_address,
                self._last_trust_block
            )
            self._trusted_accounts.update(new_trusted)
            self._last_trust_block = latest_block

        # Process completed backers
        if completed_backers:
            self._handle_completed_backers(completed_backers)

        self._last_processed_block = current_block


    def _handle_incomplete_backings(self, fallback_pairs: set[tuple[str, str, int]]):
                """Process backings that need CreateLBP calls"""
                print(f"Processing {len(fallback_pairs)} incomplete backings")

                for backer, instance, timestamp in fallback_pairs:
                    print(f"\nProcessing instance: {instance}")

                    try:
                        checksum_instance = self.web3.to_checksum_address(instance)
                        checksum_backer = self.web3.to_checksum_address(backer)

                        # print(f"Original instance address: {instance}")
                        # print(f"Checksum instance address: {checksum_instance}")

                        # Pass private key for both validation and execution
                        if self.nethermind_client.validate_create_lbp(
                            instance_address=checksum_instance,
                            backer_address=checksum_backer,
                            initiated_timestamp=timestamp,
                            private_key=self.private_key
                        ):
                            receipt = self.nethermind_client.execute_create_lbp(
                                instance_address=checksum_instance,
                                private_key=self.private_key
                            )
                            if receipt['status'] == 1:
                                print(f"Successfully executed CreateLBP for instance {checksum_instance}")
                            else:
                                print(f"CreateLBP failed for instance {checksum_instance}")
                        else:
                            print(f"CreateLBP validation failed for instance {checksum_instance}")

                    except Exception as e:
                        print(f"Error processing instance {instance}: {str(e)}")
                        print(f"Error type: {type(e)}")
                        continue


    def _handle_completed_backers(self, completed_backers: set[str]):
        """Process completed backers for trust relationships"""
        # Find new backers not yet trusted
        new_backers = completed_backers - self._trusted_accounts
        if not new_backers:
            print("No new backers to process")
            return

        print(f"Processing {len(new_backers)} new backers")

        # Screen against blacklist
        blacklisted = set(self.screening_client.check_blacklist(list(new_backers)))
        valid_backers = new_backers - blacklisted

        if blacklisted:
            print(f"Filtered out {len(blacklisted)} blacklisted addresses")

        if not valid_backers:
            print("No valid backers to trust after screening")
            return

        # Trust valid backers
        checksum_backers = {str(Web3.to_checksum_address(backer)) for backer in valid_backers}
        print(f"Adding {len(checksum_backers)} addresses to trust batch")

        try:
            self.call_trust_batch(checksum_backers)
            self._trusted_accounts.update(valid_backers)
            print("Successfully updated trust relationships")
        except Exception as e:
            print(f"Failed to execute trust batch: {str(e)}")

    def run_trust_management(self):
        """Main execution function"""
        current_block = self.web3.eth.block_number
        print(f"\nProcessing block {current_block}")

        try:
            self._sync_state()
        except Exception as e:
            print(f"Error in trust management: {str(e)}")

    def call_trust_batch(self, checksum_backers: set[str]):
        """Execute trust batch transaction"""
        try:
            expiry = 2**96 - 1
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
        """Reset algorithm state"""
        self._trusted_accounts, self._last_trust_block = self.nethermind_client.fetch_group_trust_relations(self.supergroup_address)
        self._last_processed_block = 0
        print(f"Reset state with {len(self._trusted_accounts)} trusted accounts from block {self._last_trust_block}")


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
