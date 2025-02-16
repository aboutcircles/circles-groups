import requests
import json
from typing import Set
from web3 import Web3
import time
from src.config.settings import settings
from web3.exceptions import ContractLogicError

class NethermindClient:
    def __init__(self, rpc_url: str):
        self.rpc_url = rpc_url
        self.web3 = Web3(Web3.HTTPProvider(rpc_url))
        self._cache = {
            'trusted_by': {},  # Address -> set of trustees
            'last_processed_block': 0
        }

        # Load ABI from JSON file
        try:
            with open(settings.circles_backing_abi_path, "r") as file:
                self.abi = json.load(file)
        except FileNotFoundError:
            raise Exception("CirclesBackingABI.json file not found")



    def flush(self):
        self._cache = {
            'trusted_by': {},
            'last_processed_block': 0
        }

    def reset(self):
        self.flush()

    def _make_request(self, method: str, params: list) -> dict:
        """Make a JSON-RPC request to the Nethermind node."""
        payload = {
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
            "id": 1
        }
        response = requests.post(self.rpc_url, json=payload)
        response.raise_for_status()
        return response.json().get('result')

    def fetch_backing_status(self) -> tuple[set[tuple[str, str, int]], set[str], int]:
            """
            Fetch both initiated and completed backings.
            Returns:
                - Set of (backer, instance) pairs needing CreateLBP
                - Set of completed backer addresses
                - Latest block number
            """
            # Query CirclesBackingInitiated events
            initiated_query = {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "circles_query",
                "params": [{
                    "Namespace": "CrcV2",
                    "Table": "CirclesBackingInitiated",
                    "Columns": [
                        "backer",
                        "circlesBackingInstance",
                        "blockNumber",
                        "timestamp"
                    ],
                    "Filter": [],
                    "Order": [{"Column": "blockNumber", "SortOrder": "DESC"}],
                    "Limit": 1000
                    #Add pagination and higher limit handling
                }]
            }

            # Query CirclesBackingCompleted events
            completed_query = {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "circles_query",
                "params": [{
                    "Namespace": "CrcV2",
                    "Table": "CirclesBackingCompleted",
                    "Columns": [
                        "backer",
                        "circlesBackingInstance",
                        "blockNumber"
                    ],
                    "Filter": [],
                    "Order": [{"Column": "blockNumber", "SortOrder": "DESC"}],
                    "Limit": 1000
                    #Add pagination and higher limit handling
                }]
            }

            initiated_response = requests.post(self.rpc_url, json=initiated_query)
            completed_response = requests.post(self.rpc_url, json=completed_query)

            initiated_result = initiated_response.json().get("result", {})
            completed_result = completed_response.json().get("result", {})

            # Process initiated events
            initiated_pairs = set()
            latest_block = self._cache['last_processed_block']

            if initiated_result.get('rows'):
                initiated_cols = initiated_result['columns']
                backer_idx = initiated_cols.index('backer')
                instance_idx = initiated_cols.index('circlesBackingInstance')
                block_idx = initiated_cols.index('blockNumber')
                timestamp_idx = initiated_cols.index('timestamp')

                for row in initiated_result['rows']:
                    backer = row[backer_idx].lower()
                    instance = row[instance_idx].lower()
                    timestamp = int(row[timestamp_idx])
                    initiated_pairs.add((backer, instance, timestamp))
                    latest_block = max(latest_block, int(row[block_idx]))

            # Process completed events
            completed_pairs = set()
            completed_backers = set()

            if completed_result.get('rows'):
                completed_cols = completed_result['columns']
                backer_idx = completed_cols.index('backer')
                instance_idx = completed_cols.index('circlesBackingInstance')
                block_idx = completed_cols.index('blockNumber')

                for row in completed_result['rows']:
                    backer = row[backer_idx].lower()
                    instance = row[instance_idx].lower()
                    completed_pairs.add((backer, instance))
                    completed_backers.add(backer)
                    latest_block = max(latest_block, int(row[block_idx]))

            # Find pairs needing CreateLBP
            fallback_pairs = {(backer, instance, timestamp)
                                 for backer, instance, timestamp in initiated_pairs
                                 if (backer, instance) not in completed_pairs}

            return fallback_pairs, completed_backers, latest_block

    def validate_create_lbp(self, backer_address: str, instance_address: str, initiated_timestamp: int, private_key: str) -> bool:
        """
        Validate if CreateLBP can be called
        Returns True if:
        - createLBP can be called successfully
        - LBP already exists (AlreadyCreated error)

        Args:
            backer_address: Address of the backer from fetch_backing_status
            instance_address: Address of the backing instance from fetch_backing_status
            initiated_timestamp: Timestamp when backing was initiated
            private_key: Private key for transaction signing
        """
        def send_slack_notification(error_type: str, details: str = ""):
            try:

                message = (
                    f"*LBP Creation Error*\n"
                    f"Error Type: `{error_type}`\n"
                    f"Backer Address: `{backer_address}`\n"
                    f"Instance Address: `{instance_address}`\n"
                )

                payload = {"text": message}
                response = requests.post(
                    settings.slack_webhook_url,
                    data=json.dumps(payload),
                    headers={'Content-Type': 'application/json'}
                )
                response.raise_for_status()
                print(f"Slack notification sent for {error_type}")
            except Exception as e:
                print(f"Failed to send Slack notification: {str(e)}")

        try:
            checksum_instance = self.web3.to_checksum_address(instance_address)
            checksum_backer = self.web3.to_checksum_address(backer_address)
            account = self.web3.eth.account.from_key(private_key)

            print(f"Instance address: {checksum_instance}")
            print(f"Backer address: {checksum_backer}")
            print(f"Executor address: {account.address}")

            contract = self.web3.eth.contract(
                address=checksum_instance,
                abi=self.abi
            )

            try:
                contract.functions.createLBP().call({'from': account.address})
                return True

            except ContractLogicError as e:
                error_message = str(e)
                print(f"Contract Logic Error: {error_message}")

                if "AlreadyCreated" in error_message:
                    print("LBP already exists - proceeding with normal flow")
                    return True

                elif "InsufficientBackingAssetBalance" in error_message:
                    print("Insufficient backing balance detected")
                    send_slack_notification(
                        "Insufficient Backing Balance",
                        "Action Required: Check actual balances in contract"
                    )
                    return False

                elif "OrderNotFilledYet" in error_message:
                    current_time = int(time.time())
                    minutes_elapsed = (current_time - initiated_timestamp) // 60

                    print(f"Cowswap order not filled yet. Waiting time: {minutes_elapsed} minutes")

                    if minutes_elapsed >= 20:
                        send_slack_notification(
                            "Order Not Filled - Long Wait",
                            "⚠️ Order pending for over 20 minutes!\nAction Required: Please investigate Cowswap status."
                        )
                    else:
                        send_slack_notification(
                            "Order Not Filled",
                            f"Order still processing for {minutes_elapsed}."
                        )
                    return False

                # Handle any other contract errors
                send_slack_notification("Unknown Contract Error", f"Error: {error_message}")
                return False

        except Exception as e:
            error_msg = str(e)
            print(f"Contract call failed with error: {error_msg}")
            send_slack_notification("Contract Setup Error", f"Failed to setup or call contract: {error_msg}")
            return False

    def execute_create_lbp(self, instance_address: str, private_key: str) -> dict:
        """Execute CreateLBP on a circles backing instance"""
        try:
            # Convert instance address to checksum
            checksum_instance = self.web3.to_checksum_address(instance_address)
            account = self.web3.eth.account.from_key(private_key)

            print(f"Checksum instance address: {checksum_instance}")
            print(f"Account address: {account.address}")

            contract = self.web3.eth.contract(
                address=checksum_instance,
                abi=self.abi
            )

            transaction = contract.functions.createLBP().build_transaction({
                "from": account.address,  # Account address is already checksum
                "nonce": self.web3.eth.get_transaction_count(account.address),
                "gas": 6000000,
                "gasPrice": self.web3.eth.gas_price,
            })

            signed_tx = self.web3.eth.account.sign_transaction(transaction, private_key)
            tx_hash = self.web3.eth.send_raw_transaction(signed_tx.raw_transaction)
            receipt = self.web3.eth.wait_for_transaction_receipt(tx_hash)
            return dict(receipt)
        except ValueError as ve:
            print(f"Address validation error: {str(ve)}")
            raise
        except Exception as e:
            print(f"Execution failed with error: {str(e)}")
            raise

    def fetch_group_trust_relations(self, supergroup_address: str, last_processed_block: int = 0) -> tuple[set[str], int]:
        """Fetch trust relations for a supergroup with block tracking."""
        if supergroup_address in self._cache['trusted_by'] and last_processed_block == self._cache['last_processed_block']:
            return self._cache['trusted_by'][supergroup_address], self._cache['last_processed_block']

        query = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "circles_query",
            "params": [
                {
                    "Namespace": "V_CrcV2",
                    "Table": "TrustRelations",
                    "Columns": ["trustee", "blockNumber"],
                    "Filter": [
                        {
                            "Type": "FilterPredicate",
                            "FilterType": "Equals",
                            "Column": "truster",
                            "Value": supergroup_address.lower()
                        }
                    ],
                    "Order": [
                        {"Column": "blockNumber", "SortOrder": "DESC"}
                    ],
                    "Limit": 1000
                }
            ]
        }

        response = requests.post(self.rpc_url, json=query)
        response.raise_for_status()

        result = response.json().get("result", {})
        if 'columns' not in result or 'rows' not in result:
            raise ValueError("Unexpected response structure")

        keys = result['columns']
        rows = result['rows']

        try:
            trustee_index = keys.index('trustee')
            block_number_index = keys.index('blockNumber')
        except ValueError:
            return set(), last_processed_block

        trustees = set()
        latest_block = last_processed_block

        for row in rows:
            trustees.add(row[trustee_index])
            block_number = int(row[block_number_index])
            latest_block = max(latest_block, block_number)

        # Update cache
        self._cache['trusted_by'][supergroup_address] = trustees
        self._cache['last_processed_block'] = latest_block

        if trustees:
            print(f"Found {trustees} trustees for supergroup {supergroup_address}")

        return trustees, latest_block

    def get_all_v2_humans(self) -> Set[str]:
        """Get a list of all v2 human accounts registered in the Hub."""
        return self.get_all_humans_with_pagination(1000)

    def get_all_humans_with_pagination(self, limit: int = 1000) -> Set[str]:
        """Get a paginated list of all human accounts registered in the Hub."""
        if limit > 1000 or limit < 0:
            raise ValueError("Limit exceeds maximum allowed value of 1000, or is negative.")

        params = [
            {
                "Namespace": "V_CrcV2",
                "Table": "Avatars",
                "Limit": limit,
                "Columns": [],
                "Filter": [{
                    "Type": "FilterPredicate",
                    "FilterType": "Equals",
                    "Column": "type",
                    "Value": "CrcV2_RegisterHuman"
                }],
                "Order": [
                    {"Column": "blockNumber", "SortOrder": "DESC"},
                    {"Column": "transactionIndex", "SortOrder": "DESC"},
                    {"Column": "logIndex", "SortOrder": "DESC"}
                ]
            }
        ]
        result = self._make_request("circles_query", params)

        if 'columns' not in result or 'rows' not in result:
            raise ValueError("Unexpected response structure: result should contain 'columns' and 'rows'.")

        keys = result['columns']
        rows = result['rows']

        try:
            avatar_index = keys.index('avatar')
        except ValueError:
            raise ValueError("Avatar key not found in response columns.")

        human_addresses = [row[avatar_index] for row in rows]
        invalid_addresses = [address for address in human_addresses if not Web3.is_address(address)]

        if invalid_addresses:
            raise ValueError(f"Invalid Ethereum addresses found: {invalid_addresses}")

        return set(human_addresses)
