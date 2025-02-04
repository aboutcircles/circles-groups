import requests
from typing import Set
from web3 import Web3

class NethermindClient:
    def __init__(self, rpc_url: str):
        self.rpc_url = rpc_url
        self.web3 = Web3(Web3.HTTPProvider(rpc_url))
        self._cache = {
            'trusted_by': {},  # Address -> set of trustees
            'last_processed_block': 0
        }

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

    #Create a new function to handle fallback, before fetch_backers
       # Query CirclesBackingInitiated event (backers)
       # Subtract CirclesBackingInitiated(backers) - CirclesBackingCompleted(backers)
       # CirclesBackingInitiated -> filter based on different backers addresses
       # if CirclesBacking Initiated ->  circlesBackingInstance address ( eth_call on CreateLBP() )      (only executable when cowswap hasn't called yet)


    def fetch_backers(self) -> tuple[set[str], int]:
        """Fetch all backers from the CirclesBackingCompleted table/event."""
        query = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "circles_query",
            "params": [
                {
                    "Namespace": "CrcV2",
                    "Table": "CirclesBackingCompleted",
                    "Columns": [
                        "blockNumber", "backer"
                    ],
                    "Filter": [],
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
            backer_index = keys.index('backer')
            block_number_index = keys.index('blockNumber')
        except ValueError:
            raise ValueError("Required columns not found in response")

        # Extract backers and latest block
        backers = set()
        latest_block = self._cache['last_processed_block']

        for row in rows:
            backers.add(row[backer_index])
            block_number = int(row[block_number_index])
            latest_block = max(latest_block, block_number)

        self._cache['last_processed_block'] = latest_block
        return backers, latest_block

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
