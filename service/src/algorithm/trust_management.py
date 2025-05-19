import json
import logging
import requests
from datetime import datetime
from web3 import Web3
from typing import Set, Dict, Any, List, Optional
from clients.nethermind import NethermindClient
from clients.screening import ScreeningClient
from algorithm.lbp_processor import LBPProcessor
from utils.slack_notifier import SlackNotifier
from config.settings import settings
from utils.state import StateManager
from web3.exceptions import ContractLogicError

logger = logging.getLogger(__name__)

class TrustManagementAlgorithm:
    def __init__(
            self,
            nethermind_client: NethermindClient,
            screening_client: ScreeningClient,
            baseGroup_address: str,
            private_key: str,
            slack_notifier: Optional[SlackNotifier] = None,
            retry_interval: int = 300,
            max_retries: int = 10
        ):
            # Initialize core dependencies and connections
            self.nethermind_client = nethermind_client
            self.screening_client = screening_client
            self.baseGroup_address = Web3.to_checksum_address(baseGroup_address)
            self.private_key = private_key
            self.slack_notifier = slack_notifier
            self.factory_address = settings.factory_address

            # Create state manager using last 8 chars of baseGroup address for unique ID
            group_id = baseGroup_address[-8:].lower()
            self.state_manager = StateManager(f"trust_state_{group_id}.json")

            # Initialize Web3 connection
            self.web3 = nethermind_client.web3
            if not self.web3.is_connected():
                logger.error("Failed to connect to blockchain node")
                raise ConnectionError("Failed to connect to blockchain node")

            # Set default values for block tracking
            self._last_processed_block = settings.deploy_block
            self._last_trust_block = settings.deploy_block
            self._trusted_accounts = set()

            try:
                # Load contract ABI and initialize contract instance
                with open(settings.baseGroup_abi_path, "r") as file:
                    contract_abi = json.load(file)
                self.baseGroup_contract = self.web3.eth.contract(
                    address=self.baseGroup_address,
                    abi=contract_abi
                )
                logger.info(f"Base Group contract initialized at {self.baseGroup_address}")
            except Exception as e:
                logger.error(f"Failed to initialize contract: {str(e)}")
                raise RuntimeError(f"Failed to initialize contract: {str(e)}")

            # Initialize LBP processor for handling liquidity backing
            self.lbp_processor = LBPProcessor(
                nethermind_client=self.nethermind_client,
                private_key=self.private_key,
                slack_notifier=self.slack_notifier,
                retry_interval=retry_interval,
                max_retries=max_retries
            )

            try:
                # Trying to load last processed block from saved state
                saved_state = self.state_manager.load()
                if saved_state and 'last_processed_block' in saved_state:
                    self._last_processed_block = saved_state['last_processed_block']
                    logger.info(f"Resuming from saved block: {self._last_processed_block}")

                # Get trusted accounts directly from blockchain
                self._trusted_accounts, trust_block = self.nethermind_client.fetch_group_trust_relations(self.baseGroup_address)
                self._last_trust_block = trust_block

                # Get current block for history limit calculation
                current_block = self.web3.eth.block_number

                # Limit to ~1 day of history to prevent excessive processing
                MAX_HISTORICAL_BLOCKS = 7200

                # Choose most recent starting point: saved block or deploy block
                candidate_block = max(self._last_processed_block, settings.deploy_block)

                # Apply maximum history constraint if needed
                if current_block - candidate_block > MAX_HISTORICAL_BLOCKS:
                    old_block = candidate_block
                    candidate_block = current_block - MAX_HISTORICAL_BLOCKS
                    logger.warning(f"Limiting historical processing: {old_block} → {candidate_block}")

                self._last_processed_block = candidate_block

                # Saving initial state
                self._save_state()
                logger.info(f"Starting block processing from block: {self._last_processed_block}")

            except Exception as e:
                # Fall back to safe defaults on error
                logger.error(f"Error initializing: {str(e)}")
                self._trusted_accounts = set()
                self._last_trust_block = settings.deploy_block
                self._last_processed_block = settings.deploy_block
                logger.info(f"Using fallback initialization from deployment block: {settings.deploy_block}")

            # Stats for monitoring
            self.stats = {
                'start_time': datetime.now(),
                'backers_trusted': 0,
                'blacklisted_addresses': 0
            }

    def _save_state(self):
        # Persist algorithm state to disk
        state = {
            'last_processed_block': self._last_processed_block,
            'last_trust_block': self._last_trust_block,
            'timestamp': datetime.now().isoformat()
        }

        if self.state_manager.save(state):
            logger.debug(f"Saved state with last processed block: {self._last_processed_block}")
        else:
            logger.warning("Failed to save algorithm state")

    def run(self):
        # Main execution function for processing new blocks
        current_block = self.web3.eth.block_number

        # Skip if no new blocks to process
        if current_block <= self._last_processed_block:
            logger.debug(f"No new blocks to process. Current: {current_block}, Last: {self._last_processed_block}")
            return

        logger.info(f"Processing blocks from {self._last_processed_block} to {current_block}")

        try:
            # Fetch new backing instances initiated since last processed block
            fallback_pairs, completed_backers, latest_block = self.nethermind_client.fetch_backing_status(
                from_block=self._last_processed_block
            )

            # Process instances needing LBP creation or reset
            if fallback_pairs:
                for backer, instance in fallback_pairs:
                    self.lbp_processor.process_instance(instance, backer)

            # Get any newly completed backers from the processor
            processor_completed_backers = self.lbp_processor.get_completed_backers()
            if processor_completed_backers:
                completed_backers.update(processor_completed_backers)

            # Trust backers who completed backing process
            if completed_backers:
                self._process_completed_backers(completed_backers)

            # Check on pending instances
            self.lbp_processor.process_pending_instances()

            # Update last processed block - use event block or current block
            if latest_block > self._last_processed_block:
                self._last_processed_block = latest_block
            else:
                self._last_processed_block = current_block

            # Update stats from LBP processor
            processor_stats = self.lbp_processor.get_stats()
            self.stats.update({
                'lbp_created': processor_stats['lbp_created'],
                'lbp_failed': processor_stats['lbp_failed'],
                'pending_instances': processor_stats['pending_instances'],
                'problem_instances': processor_stats['problem_instances']
            })

            logger.info(f"Updated last processed block to {self._last_processed_block}")
            # Save state after successful processing
            self._save_state()

        except Exception as e:
            logger.error(f"Error in trust management run: {e}", exc_info=True)

    def _process_completed_backers(self, completed_backers: Set[str]):
        # Add completed backers to trusted accounts list
        logger.info(f"Processing {len(completed_backers)} completed backers")

        # Normalize addresses to lowercase
        completed_backers = {backer.lower() for backer in completed_backers}

        # Find backers not yet trusted
        new_backers = completed_backers - self._trusted_accounts
        if not new_backers:
            logger.info("No new backers to process, all are already trusted")
            return

        logger.info(f"Found {len(new_backers)} new backers to potentially trust")

        # Screen against blacklist for security
        blacklisted = set(self.screening_client.check_blacklist(list(new_backers)))
        if blacklisted:
            logger.warning(f"Filtered out {len(blacklisted)} blacklisted addresses")
            self.stats['blacklisted_addresses'] += len(blacklisted)
            new_backers -= blacklisted

        if not new_backers:
            logger.info("No eligible backers remaining after blacklist screening")
            return

        try:
            logger.info(f"Adding {len(new_backers)} backers to trust batch")

            # Convert to checksum addresses for contract call
            checksum_backers: List[str] = [Web3.to_checksum_address(addr) for addr in new_backers]

            # Call contract to add trust relations
            self._execute_trust_batch(checksum_backers)

            # Update stats and local state
            self.stats['backers_trusted'] += len(new_backers)
            self._trusted_accounts.update(new_backers)

            # Update last trust block to current block
            self._last_trust_block = self.web3.eth.block_number

            # Save state after trust update
            self._save_state()

            logger.info(f"Successfully added {len(new_backers)} new backers to trusted accounts")

        except Exception as e:
            logger.error(f"Failed to execute trust batch: {e}", exc_info=True)

    def _execute_trust_batch(self, addresses: List[str]):
        # Execute trustBatch transaction on the contract
        try:
            # Maximum trust expiry (effectively never expires)
            expiry = 2**96 - 1

            # Get account from private key
            account = self.web3.eth.account.from_key(self.private_key)

            # Build transaction with appropriate gas limits
            transaction = self.baseGroup_contract.functions.trustBatchWithConditions(
                addresses, expiry
            ).build_transaction({
                "from": account.address,
                "nonce": self.web3.eth.get_transaction_count(account.address),
                "gas": 1000000,
                "gasPrice": self.web3.eth.gas_price,
            })

            # Sign and submit transaction
            signed_tx = self.web3.eth.account.sign_transaction(transaction, private_key=self.private_key)
            tx_hash = self.web3.eth.send_raw_transaction(signed_tx.raw_transaction)
            logger.info(f"Trust batch transaction sent: {tx_hash.hex()}")

            # Wait for transaction confirmation
            receipt = self.web3.eth.wait_for_transaction_receipt(tx_hash)
            logger.info(f"Trust batch transaction confirmed in block {receipt['blockNumber']}")

            return receipt

        except ContractLogicError as e:
            logger.error(f"Error executing trust batch: {e}", exc_info=True)
            raise Exception(f"Trust batch transaction failed: {str(e)}")

    def check_health(self) -> Dict[str, Any]:
       # Check overall health including RPC, indexer and chain status
       gnosis_web3 = Web3(Web3.HTTPProvider("https://rpc.gnosischain.com"))

       health = {
           "status": "unhealthy",
           "rpc_connected": False,
           "gnosis_chain_connected": False,
           "indexer_connected": False,
           "current_block": -1,
           "gnosis_head_block": -1,
           "latest_indexed_block": -1,
           "last_processed_block": self._last_processed_block,
           "last_trust_block": self._last_trust_block,
           "block_lag": -1,
           "indexer_vs_head_lag": -1,
           "uptime": str(datetime.now() - self.stats['start_time']).split('.')[0],
           "trusted_accounts_count": len(self._trusted_accounts)
       }

       # Add state file age information
       state_age = self.state_manager.get_state_age()
       if state_age is not None:
           health["state_file_age_minutes"] = round(state_age / 60, 1)

       try:
           # Check Circles RPC connection
           if self.web3.is_connected():
               health["rpc_connected"] = True
               health["current_block"] = self.web3.eth.block_number
       except Exception as e:
           logger.error(f"Circles RPC connection failed: {e}")

       try:
           # Check Gnosis Chain RPC connection
           if gnosis_web3.is_connected():
               health["gnosis_chain_connected"] = True
               health["gnosis_head_block"] = gnosis_web3.eth.block_number
       except Exception as e:
           logger.error(f"Gnosis Chain RPC connection failed: {e}")

       try:
           # Check indexer using System.Block table
           query = {
               "jsonrpc": "2.0",
               "id": 1,
               "method": "circles_query",
               "params": [{
                   "Namespace": "System",
                   "Table": "Block",
                   "Columns": ["blockNumber"],
                   "Order": [{"Column": "blockNumber", "SortOrder": "DESC"}],
                   "Limit": 1
               }]
           }
           response = requests.post(self.nethermind_client.rpc_url, json=query, timeout=10)
           result = response.json().get("result", {})

           if result.get('rows'):
               health["indexer_connected"] = True
               health["latest_indexed_block"] = int(result['rows'][0][0])
       except Exception as e:
           logger.error(f"Indexer connection failed: {e}")

       # Calculate lag and determine overall health status
       if health["indexer_connected"]:
           if health["rpc_connected"]:
               health["block_lag"] = health["current_block"] - health["latest_indexed_block"]
           if health["gnosis_chain_connected"]:
               health["indexer_vs_head_lag"] = health["gnosis_head_block"] - health["latest_indexed_block"]

           lag = health["indexer_vs_head_lag"]
           if lag <= 5:
               health["status"] = "healthy"
           elif lag <= 10:
               health["status"] = "degraded"
           else:
               health["status"] = "unhealthy"

       return health

    def flush(self):
        # Reset algorithm state completely by fetching fresh data
        logger.info("Flushing TrustManagementAlgorithm state")

        try:
            # Refetch trusted accounts from blockchain
            self._trusted_accounts, self._last_trust_block = self.nethermind_client.fetch_group_trust_relations(self.baseGroup_address)
            self._last_processed_block = self._last_trust_block

            # Reset stats but keep the original start time
            start_time = self.stats['start_time']
            self.stats = {
                'start_time': start_time,
                'backers_trusted': 0,
                'blacklisted_addresses': 0
            }

            # Reset the LBP processor state
            self.lbp_processor.reset()

            # Save the refreshed state
            self._save_state()

            logger.info(f"State flushed and reinitialized with {len(self._trusted_accounts)} trusted accounts")

        except Exception as e:
            logger.error(f"Error flushing state: {e}", exc_info=True)

    def reset(self):
        # Legacy method for backward compatibility
        return self.flush()
