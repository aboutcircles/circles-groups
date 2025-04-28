import json
import time
import requests
from typing import List, Dict, Any, Set
from web3 import Web3

from clients.screening import ScreeningClient
from config.settings import settings

class CirclesBackingHandler:
    def __init__(
        self,
        rpc_url: str,
        screening_client: ScreeningClient,
        baseGroup_address: str,
        private_key: str
    ):
        self.rpc_url = rpc_url
        self.web3 = Web3(Web3.HTTPProvider(rpc_url))
        if not self.web3.is_connected():
            raise ConnectionError("Failed to connect to Gnosis Chain node.")

        self.screening_client = screening_client
        self.baseGroup_address = baseGroup_address
        self.private_key = private_key

        # Initialize contract
        self._initialize_contract(self.baseGroup_address)

        # Keep track of already processed events
        self.processed_events = set()

        print(f"CirclesBackingHandler initialized for Base Group: {baseGroup_address}")

    def _initialize_contract(self, baseGroup_address: str):
        """Initialize Base Group contract for trust operations"""
        try:
            with open(settings.baseGroup_abi_path, "r") as file:
                contract_abi = json.load(file)
            # Convert address to checksum format required by Web3
            checksum_address = self.web3.to_checksum_address(baseGroup_address)
            self.baseGroup_contract = self.web3.eth.contract(
                address=checksum_address,
                abi=contract_abi
            )
            print(f"Contract initialized at {baseGroup_address}")
        except Exception as e:
            raise RuntimeError(f"Failed to initialize contract: {str(e)}")

    def fetch_backing_completed_events(self, from_block: int, to_block: int) -> List[Dict[str, Any]]:
        """Fetch CirclesBackingCompleted events directly"""
        query = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "circles_query",
            "params": [{
                "Namespace": "CrcV2",
                "Table": "CirclesBackingCompleted",
                "Columns": [
                    "backer",
                    "circlesBackingInstance",
                    "blockNumber",
                    "transactionHash"
                ],
                "Filter": [
                    {
                             "Type": "FilterPredicate",
                             "Column": "emitter",
                             "FilterType": "Equals",
                             "Value": "0xeced91232c609a42f6016860e8223b8aecaa7bd0"
                    }

                    # {
                    #     "Type": "FilterPredicate",
                    #     "FilterType": "GreaterThanOrEqual",
                    #     "Column": "blockNumber",
                    #     "Value": str(from_block)
                    # },
                    # {
                    #     "Type": "FilterPredicate",
                    #     "FilterType": "LessThanOrEqual",
                    #     "Column": "blockNumber",
                    #     "Value": str(to_block)
                    # }
                ],

                "Order": [],
                "Limit": 1000
            }]
        }

        try:
            response = requests.post(self.rpc_url, json=query)
            response.raise_for_status()
            result = response.json().get("result", {})

            if not result or 'rows' not in result:
                return []

            columns = result['columns']
            backer_idx = columns.index('backer')
            instance_idx = columns.index('circlesBackingInstance')
            block_idx = columns.index('blockNumber')
            tx_hash_idx = columns.index('transactionHash')

            events = []
            for row in result['rows']:
                backer = row[backer_idx].lower()
                instance = row[instance_idx].lower()
                block_number = int(row[block_idx])
                tx_hash = row[tx_hash_idx]

                # Create a unique ID for this event to avoid reprocessing
                event_id = f"{tx_hash}_{backer}_{instance}"

                if event_id not in self.processed_events:
                    events.append({
                        "event_id": event_id,
                        "backer": backer,
                        "instance": instance,
                        "blockNumber": block_number,
                        "transactionHash": tx_hash
                    })

            return events
        except Exception as e:
            print(f"Error fetching CirclesBackingCompleted events: {e}")
            return []

    def process_backing_completed_events(self, from_block: int, to_block: int):
        """Process new CirclesBackingCompleted events"""
        print(f"Processing CirclesBackingCompleted events from block {from_block} to {to_block}")

        # Fetch new events
        events = self.fetch_backing_completed_events(from_block, to_block)

        if not events:
            print("No new CirclesBackingCompleted events found")
            return

        print(f"Found {len(events)} new CirclesBackingCompleted events")

        # Extract all backer addresses
        backer_addresses = [event["backer"] for event in events]

        # Screen backer addresses against blacklist
        blacklisted = self.screening_client.check_blacklist(backer_addresses)

        if blacklisted:
            print(f"Filtered out {len(blacklisted)} blacklisted addresses")
            # Remove blacklisted addresses
            valid_backers = [addr for addr in backer_addresses if addr not in blacklisted]
        else:
            valid_backers = backer_addresses

        if not valid_backers:
            print("No valid backers to trust after screening")
            # Mark events as processed even if we don't process them
            for event in events:
                self.processed_events.add(event["event_id"])
            return

        # Convert to checksum addresses and then back to strings to fix type compatibility
        checksum_backers = [str(self.web3.to_checksum_address(backer)) for backer in valid_backers]

        print(f"Trusting {len(checksum_backers)} addresses...")

        try:
            # Call trustBatch
            receipt = self.trust_batch_with_Conditions(checksum_backers)

            if receipt and receipt.get('status') == 1:
                print(f"Successfully trusted {len(checksum_backers)} addresses")
                # Mark events as processed
                for event in events:
                    self.processed_events.add(event["event_id"])
            else:
                print("Trust batch transaction failed")
        except Exception as e:
            print(f"Error executing trust batch: {e}")

    def trust_batch_with_Conditions(self, addresses: List[str]) -> Dict[str, Any]:
        """
        Execute trustBatch transaction on the Base group contract.
        """
        try:
            if not addresses:
                raise ValueError("No addresses provided for trust batch")

            # Default expiry (practically infinite)
            expiry = 2**96 - 1

            # Get account from private key
            account = self.web3.eth.account.from_key(self.private_key)

            # Build the transaction
            transaction = self.baseGroup_contract.functions.trustBatchWithConditions(
                addresses, expiry
            ).build_transaction({
                "from": account.address,
                "nonce": self.web3.eth.get_transaction_count(account.address),
                "gas": 1000000,
                "gasPrice": self.web3.eth.gas_price,
            })

            print(f"Sending trust batch transaction for {len(addresses)} addresses...")

            # Sign and send the transaction
            signed_tx = self.web3.eth.account.sign_transaction(transaction, private_key=self.private_key)
            tx_hash = self.web3.eth.send_raw_transaction(signed_tx.raw_transaction)
            print(f"Trust batch transaction sent: {tx_hash.hex()}")

            # Wait for the transaction to be mined
            receipt = self.web3.eth.wait_for_transaction_receipt(tx_hash)
            print(f"Transaction confirmed in block {receipt['blockNumber']}")

            return dict(receipt)
        except Exception as e:
            raise Exception(f"Trust batch transaction failed: {str(e)}")

    def run_event_processor(self, poll_interval: int = 15):
        """Main loop to continuously check for new events"""
        deployment_block = 39741602  # Deployment block where indexing should begin
        latest_processed_block = max(deployment_block, self.web3.eth.block_number - 1000)

        print(f"Starting event processor from block {latest_processed_block}")

        while True:
            try:
                current_block = self.web3.eth.block_number

                if current_block > latest_processed_block:
                    print(f"\nProcessing blocks {latest_processed_block + 1} to {current_block}")
                    self.process_backing_completed_events(latest_processed_block + 1, current_block)
                    latest_processed_block = current_block

                time.sleep(poll_interval)
            except Exception as e:
                print(f"Error in event processing loop: {e}")
                time.sleep(poll_interval)
