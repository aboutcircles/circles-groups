import time
import requests
from typing import Set
from web3 import Web3
from config.settings import settings

class NethermindClient:
    def __init__(self, rpc_url: str):
        self.rpc_url = rpc_url
        self.cache_trusted_by = {}

    def flush(self):
        self.cache_trusted_by = {}

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


    # Fetch all the backers from the CirclesBackingCompleted table/event
    # Backer -> the address of the user who backed their CRC

   
    def fetch_backers(self) -> list:
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
                        "blockNumber", "timestamp", "transactionIndex", "logIndex",
                        "transactionHash", "backer", "circlesBackingInstance", "lbp"
                    ],
                    "Filter": [],
                    "Order": [],
                    "Limit": 1000 
                }
            ]
        }

        # Make the request
        response = requests.post(self.rpc_url, json=query)
        response.raise_for_status()

        result = response.json().get("result", {})
        if 'columns' not in result or 'rows' not in result:
            raise ValueError("Unexpected response structure: result should contain 'columns' and 'rows'.")

        keys = result['columns']
        rows = result['rows']

        try:
            backer_index = keys.index('backer')
        except ValueError:
            raise ValueError("Backer key not found in response columns.")

        # Extract backers
        return [row[backer_index] for row in rows]


    #Fetch all the trust relations from the TrustRelations table
    #Truster is the address of the user who trusts the trustee, here SuperGroup is the truster
    #Trustee is the address of the user who is trusted by the truster


    def fetch_group_trust_relations(self, supergroup_address: str) -> set:
        """Fetch all trust relations where the SuperGroup is the truster."""
        query = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "circles_query",
            "params": [
                {
                    "Namespace": "V_CrcV2",
                    "Table": "TrustRelations",
                    "Columns": ["truster", "trustee"],
                    "Filter": [],
                    "Order": [],
                    "Limit": 1000
                }
            ]
        }

        # Make the request
        response = requests.post(self.rpc_url, json=query)
        response.raise_for_status()

        result = response.json().get("result", {})
        if 'columns' not in result or 'rows' not in result:
            raise ValueError("Unexpected response structure: result should contain 'columns' and 'rows'.")

            keys = result['columns']
            rows = result['rows']

            try:
                truster_index = keys.index('truster')
                trustee_index = keys.index('trustee')
            except ValueError:
                raise ValueError("Truster or Trustee key not found in response columns.")

            # Extract trust relations, ensuring truster is the super_group_address
            supergroup_address_normalized = settings.supergroup_address.lower()
            
            trustees = {row[trustee_index] for row in rows if row[truster_index] == supergroup_address_normalized}

            if trustees:
                print(f"Trustees trusted by supergroup {supergroup_address_normalized}:")
                for trustee in trustees:
                    print(trustee)
            else:
                print(f"No trustees found for supergroup {supergroup_address_normalized}.")

            return trustees


    #Get all the V2 humans from the Avatars table

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

    