import requests
import json
import logging
from typing import Set, Tuple, Dict, List, Optional
from web3 import Web3
from src.config.settings import settings

logger = logging.getLogger(__name__)

class NethermindClient:
    def __init__(self, rpc_url: str, factory_address: Optional[str] = None ):
        """
        Initialize the NethermindClient.

        Args:
            rpc_url: The URL of the Nethermind RPC endpoint
            factory_address: Optional factory address, will use settings if not provided
        """
        self.rpc_url = rpc_url
        self.web3 = Web3(Web3.HTTPProvider(rpc_url))
        if not self.web3.is_connected():
            raise ConnectionError(f"Failed to connect to node at {rpc_url}")

        # Set factory address, falling back to settings if needed
        if factory_address is None:
            # Use the already imported settings instead of re-importing
            factory_address = settings.factory_address

        # Ensure factory address is properly formatted (lowercase for queries)
        self.factory_address = factory_address.lower() if factory_address else ""

        if self.factory_address:
            logger.info(f"NethermindClient initialized with factory address: {self.factory_address}")
        else:
            logger.warning("NethermindClient initialized without factory address")

        # Initialize cache
        self._cache = {
            'trusted_accounts': set(),
            'last_processed_block': 0
        }

        # Initialize abi property
        self.abi = None

    def fetch_backing_status(self, from_block: int = 0):
        """
        Fetch the status of circles backing instances.

        Args:
            from_block: Optional starting block to filter by

        Returns:
            Tuple containing (list of backer/instance pairs needing LBP,
                             set of completed backers,
                             latest block processed)
        """
        logger.info(f"Fetching backing status from block {from_block}")

        # Base filter conditions
        base_filter = [] if from_block == 0 else [
            {
                "Type": "FilterPredicate",
                "FilterType": "GreaterThan",
                "Column": "blockNumber",
                "Value": str(from_block)
            }
        ]

        # Add emitter filter for factory address
        emitter_filter = {
            "Type": "FilterPredicate",
            "FilterType": "Equals",
            "Column": "emitter",
            "Value": self.factory_address
        }

        # Create complete filter with emitter
        initiated_filter = base_filter.copy()
        initiated_filter.append(emitter_filter)

        # Query CirclesBackingInitiated events with emitter filter
        initiated_query = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "circles_query",
            "params": [{
                "Namespace": "CrcV2",
                "Table": "CirclesBackingInitiated",
                "Columns": ["backer", "circlesBackingInstance", "blockNumber"],
                "Filter": initiated_filter,
                "Order": [{"Column": "blockNumber", "SortOrder": "DESC"}],
                "Limit": 1000
            }]
        }

        # Add emitter filter to completed query too
        completed_filter = base_filter.copy()
        completed_filter.append(emitter_filter)

        # Query CirclesBackingCompleted events with emitter filter
        completed_query = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "circles_query",
            "params": [{
                "Namespace": "CrcV2",
                "Table": "CirclesBackingCompleted",
                "Columns": ["backer", "circlesBackingInstance", "blockNumber"],
                "Filter": completed_filter,
                "Order": [{"Column": "blockNumber", "SortOrder": "DESC"}],
                "Limit": 1000
            }]
        }

        try:
            # Get initiated backings
            initiated_response = requests.post(self.rpc_url, json=initiated_query, timeout=30)
            initiated_result = initiated_response.json().get("result", {})

            # Get completed backings
            completed_response = requests.post(self.rpc_url, json=completed_query, timeout=30)
            completed_result = completed_response.json().get("result", {})

            # Process results
            initiated_instances = set()
            completed_instances = set()
            latest_block = from_block

            # Process initiated backings
            if 'columns' in initiated_result and 'rows' in initiated_result:
                backer_index = initiated_result['columns'].index('backer')
                instance_index = initiated_result['columns'].index('circlesBackingInstance')
                block_index = initiated_result['columns'].index('blockNumber')

                for row in initiated_result['rows']:
                    backer = row[backer_index].lower()
                    instance = row[instance_index].lower()
                    block_num = int(row[block_index])

                    initiated_instances.add((backer, instance))
                    latest_block = max(latest_block, block_num)

            # Process completed backings
            completed_backers = set()
            if 'columns' in completed_result and 'rows' in completed_result:
                backer_index = completed_result['columns'].index('backer')
                instance_index = completed_result['columns'].index('circlesBackingInstance')
                block_index = completed_result['columns'].index('blockNumber')

                for row in completed_result['rows']:
                    backer = row[backer_index].lower()
                    instance = row[instance_index].lower()
                    block_num = int(row[block_index])

                    completed_instances.add((backer, instance))
                    completed_backers.add(backer)
                    latest_block = max(latest_block, block_num)

            # Find instances needing LBP (initiated but not completed)
            needs_lbp = [
                (backer, instance) for (backer, instance) in initiated_instances
                if (backer, instance) not in completed_instances
            ]

            logger.info(f"Found {len(needs_lbp)} backing instances needing CreateLBP")
            logger.info(f"Found {len(completed_backers)} completed backers")
            logger.info(f"Latest block processed: {latest_block}")

            return needs_lbp, completed_backers, latest_block

        except Exception as e:
            logger.error(f"Error fetching backing status: {e}")
            return [], set(), from_block

    def fetch_group_trust_relations(self, group_address: str) -> Tuple[Set[str], int]:
        """
        Fetch all trusted accounts for a group and the last block where a trust
        relation was created in a single call.

        Args:
            group_address: The address of the group

        Returns:
            Tuple containing (set of trusted addresses, last trust block)
        """
        group_address = group_address.lower()
        logger.info(f"Fetching trust relations for {group_address}")

        try:
            # Build filter for the group's trust relations
            filter_conditions = [
                {
                    "Type": "FilterPredicate",
                    "FilterType": "Equals",
                    "Column": "truster",
                    "Value": group_address
                }
            ]

            # Query for trustee addresses and block numbers
            query = {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "circles_query",
                "params": [
                    {
                        "Namespace": "V_CrcV2",
                        "Table": "TrustRelations",
                        "Columns": ["trustee", "blockNumber"],
                        "Filter": filter_conditions,
                        "Limit": 10000
                    }
                ]
            }

            response = requests.post(self.rpc_url, json=query, timeout=30)
            result = response.json().get("result", {})

            if 'columns' not in result or 'rows' not in result:
                return set(), 0

            trustees = set()
            last_block = 0

            trustee_index = result['columns'].index('trustee')
            block_index = result['columns'].index('blockNumber')

            for row in result['rows']:
                trustees.add(row[trustee_index].lower())
                block_num = int(row[block_index])
                last_block = max(last_block, block_num)

            logger.info(f"Found {len(trustees)} trusted accounts, last trust block: {last_block}")
            return trustees, last_block

        except Exception as e:
            logger.error(f"Error fetching trust relations: {e}")
            return set(), 0

    def validate_reset_cowswap_order(self, instance_address: str, private_key: str) -> Dict:
        """Validate if resetCowswapOrder can be called using eth_call."""
        try:
            checksum_instance = self.web3.to_checksum_address(instance_address)
            account = self.web3.eth.account.from_key(private_key)

            # Get ABI if not already set
            if self.abi is None:
                from config.settings import settings
                with open(settings.circles_backing_abi_path, "r") as f:
                    self.abi = json.load(f)

            contract = self.web3.eth.contract(address=checksum_instance, abi=self.abi)

            try:
                contract.functions.resetCowswapOrder().call({'from': account.address})
                return {"status": "valid"}
            except Exception as e:
                error_msg = str(e)

                if "OrderAlreadySettled" in error_msg:
                    return {"status": "order_already_settled"}

                elif "OrderUidIsTheSame" in error_msg:
                    return {"status": "order_uid_same"}

                else:
                    return {"status": "validation_error", "error": error_msg}

        except Exception as e:
            return {"status": "exception", "error": str(e)}

    def validate_create_lbp(self, instance_address: str, private_key: str) -> Dict:
        """Validate if CreateLBP can be called via eth_call."""
        try:
            checksum_instance = self.web3.to_checksum_address(instance_address)
            account = self.web3.eth.account.from_key(private_key)

            # Use provided ABI or fallback to an ABI loaded elsewhere
            if self.abi is None:
                from config.settings import settings
                with open(settings.circles_backing_abi_path, "r") as f:
                    abi = json.load(f)
                    # Also set the instance ABI for future use
                    self.abi = abi

            contract = self.web3.eth.contract(address=checksum_instance, abi=abi)

            try:
                contract.functions.createLBP().call({'from': account.address})
                return {"status": "valid"}
            except Exception as e:
                error_msg = str(e)

                if "AlreadyCreated" in error_msg:
                    return {"status": "already_created"}

                elif "InsufficientBackingAssetBalance" in error_msg:
                    return {"status": "insufficient_balance"}

                else:
                    return {"status": "validation_error", "error": error_msg}

        except Exception as e:
            return {"status": "exception", "error": str(e)}

    def check_completed_event(self, instance_address: str, backer_address: str) -> bool:
        """Check if CirclesBackingCompleted event exists for the given instance."""
        instance_address = instance_address.lower()
        backer_address = backer_address.lower()

        try:
            completed_query = {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "circles_query",
                "params": [{
                    "Namespace": "CrcV2",
                    "Table": "CirclesBackingCompleted",
                    "Columns": ["backer", "circlesBackingInstance"],
                    "Filter": [
                        {
                            "Type": "FilterPredicate",
                            "FilterType": "Equals",
                            "Column": "circlesBackingInstance",
                            "Value": instance_address
                        },
                        {
                            "Type": "FilterPredicate",
                            "FilterType": "Equals",
                            "Column": "backer",
                            "Value": backer_address
                        }
                    ],
                    "Limit": 1
                }]
            }

            response = requests.post(self.rpc_url, json=completed_query, timeout=30)
            result = response.json().get("result", {})

            return bool(result.get('rows') and len(result['rows']) > 0)

        except Exception as e:
            logger.error(f"Error checking completed event: {e}")
            return False

    def get_initiated_block(self, instance_address: str) -> Optional[int]:
        """Get the block number when a backing was initiated."""
        instance_address = instance_address.lower()

        try:
            query = {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "circles_query",
                "params": [{
                    "Namespace": "CrcV2",
                    "Table": "CirclesBackingInitiated",
                    "Columns": ["blockNumber"],
                    "Filter": [
                        {
                            "Type": "FilterPredicate",
                            "FilterType": "Equals",
                            "Column": "circlesBackingInstance",
                            "Value": instance_address
                        }
                    ],
                    "Limit": 1
                }]
            }

            response = requests.post(self.rpc_url, json=query, timeout=30)
            result = response.json().get("result", {})

            if result.get('rows') and len(result['rows']) > 0:
                cols = result['columns']
                block_idx = cols.index('blockNumber')
                return int(result['rows'][0][block_idx])

            return None

        except Exception as e:
            logger.error(f"Error getting initiated block for {instance_address}: {e}")
            return None

    def execute_create_lbp(self, instance_address: str, private_key: str) -> Dict:
        """Execute CreateLBP on a circles backing instance"""
        try:
            checksum_instance = self.web3.to_checksum_address(instance_address)
            account = self.web3.eth.account.from_key(private_key)

            # Get ABI if not already set
            if self.abi is None:
                from config.settings import settings
                with open(settings.circles_backing_abi_path, "r") as f:
                    self.abi = json.load(f)

            contract = self.web3.eth.contract(address=checksum_instance, abi=self.abi)

            transaction = contract.functions.createLBP().build_transaction({
                "from": account.address,
                "nonce": self.web3.eth.get_transaction_count(account.address),
                "gas": 6000000,
                "gasPrice": self.web3.eth.gas_price,
            })

            signed_tx = self.web3.eth.account.sign_transaction(transaction, private_key)
            tx_hash = self.web3.eth.send_raw_transaction(signed_tx.raw_transaction)

            receipt = self.web3.eth.wait_for_transaction_receipt(tx_hash)

            return {
                "status": "success",
                "receipt": dict(receipt),
                "tx_hash": tx_hash.hex()
            }

        except Exception as e:
            return {"status": "error", "error": str(e)}

    def execute_cowswap_order(self, instance_address: str, private_key: str) -> Dict:
        """Execute resetCowswapOrder on a backing instance."""
        try:
            checksum_instance = self.web3.to_checksum_address(instance_address)
            account = self.web3.eth.account.from_key(private_key)

            # Get ABI if not already set
            if self.abi is None:
                from config.settings import settings
                with open(settings.circles_backing_abi_path, "r") as f:
                    self.abi = json.load(f)

            contract = self.web3.eth.contract(address=checksum_instance, abi=self.abi)

            transaction = contract.functions.resetCowswapOrder().build_transaction({
                "from": account.address,
                "nonce": self.web3.eth.get_transaction_count(account.address),
                "gas": 300000,
                "gasPrice": self.web3.eth.gas_price,
            })

            signed_tx = self.web3.eth.account.sign_transaction(transaction, private_key)
            tx_hash = self.web3.eth.send_raw_transaction(signed_tx.raw_transaction)
            receipt = self.web3.eth.wait_for_transaction_receipt(tx_hash)

            return {"status": "success", "receipt": dict(receipt)}

        except Exception as e:
            error_msg = str(e)
            if "OrderAlreadySettled" in error_msg:
                return {"status": "order_already_settled"}
            elif "OrderUidIsTheSame" in error_msg:
                return {"status": "order_uid_same"}
            else:
                return {"status": "error", "error": error_msg}

    def check_health(self) -> Dict:
        """Check the health of the RPC connection and indexer."""
        health = {
            "rpc_connected": False,
            "indexer_connected": False,
            "current_block": 0,
            "latest_indexed_block": 0,
            "status": "unhealthy"
        }

        # Check RPC connection
        try:
            health["rpc_connected"] = self.web3.is_connected()
            if health["rpc_connected"]:
                health["current_block"] = self.web3.eth.block_number
        except:
            return health

        # Check indexer connection
        try:
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

            response = requests.post(self.rpc_url, json=query, timeout=10)
            result = response.json().get("result", {})

            if result.get('rows') and len(result['rows']) > 0:
                health["indexer_connected"] = True
                health["latest_indexed_block"] = int(result['rows'][0][0])

                block_lag = health["current_block"] - health["latest_indexed_block"]
                health["block_lag"] = block_lag

                if block_lag <= 5:
                    health["status"] = "healthy"
                else:
                    health["status"] = "degraded"
        except:
            pass

        return health
