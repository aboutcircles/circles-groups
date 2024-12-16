import time
import requests
from typing import Set
from web3 import Web3

class NethermindClient:
    def __init__(self, rpc_url: str):
        self.rpc_url = rpc_url

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

    # def get_block_number(self) -> int:
    #     """Get the current block number."""
    #     result = self._make_request("eth_blockNumber", [])
    #     return int(result, 16)

    # def get_transaction(self, transaction_hash: str) -> dict:
    #     """Get a transaction by hash."""
    #     result = self._make_request("eth_getTransactionByHash", [transaction_hash])
    #     return result

    def get_trusted_by_accounts(self, address : str) -> Set[str]:
        """Get the current list of accounts that trust a given address"""
        # todo: add pagination to ensure this is a complete list
        return self._compose_get_trusted_by_accounts(address, 1000)

    def get_all_v2_humans(self) -> Set[str]:
        """Get a list of all v2 human accounts registered in the Hub"""
        # todo: for now there are only 400+ humans, soon improve by caching and then appending new
        return self.get_all_humans_with_pagination(1000)

    def get_all_humans_with_pagination(self, limit: int = 1000) -> Set[str]:
        """Get a paginated list of all human accounts registered in the Hub."""
        if limit > 1000 | limit < 0:
            raise ValueError("Limit exceeds maximum allowed value of 1000, or is negative.")

        # todo: handle caching and pagination

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
                    {
                        "Column": "blockNumber",
                        "SortOrder": "DESC"
                    },
                    {
                        "Column": "transactionIndex",
                        "SortOrder": "DESC"
                    },
                    {
                        "Column": "logIndex",
                        "SortOrder": "DESC"
                    }
                ]
            }
        ]
        result = self._make_request("circles_query", params)

        # Extract the keys and rows from the result
        if 'columns' not in result or 'rows' not in result:
            raise ValueError("Unexpected response structure: result should contain 'columns' and 'rows'.")

        keys = result['columns']
        rows = result['rows']

        try:
            avatar_index = keys.index('avatar')
            print(f"Avatar index found at: {avatar_index}")
        except ValueError as e:
            print("Avatar key not found in keys.")
            raise e

        # Extract just the avatar values
        human_addresses = [row[avatar_index] for row in rows]

        # Validate each address and raise an error if any is not a valid Web3 Ethereum address
        invalid_addresses = [address for address in human_addresses if not Web3.is_address(address)]
        if invalid_addresses:
            raise ValueError(f"Invalid Ethereum addresses found: {invalid_addresses}")

        return set(human_addresses)

    def _compose_get_trusted_by_accounts(self, address: str, limit: int = 1000) -> Set[str]:
        """Get a paginated list of all trusters who trust the given address as trustee."""
        if limit > 1000 | limit < 0:
            raise ValueError("Limit exceeds maximum allowed value of 1000, or is negative.")

        address = address.lower()

        # warning: this is FAULTY if more than one page is needed

        params = [
            {
                "Namespace": "V_CrcV2",
                "Table": "TrustRelations",  # Changed from "Trust" to "TrustRelations"
                "Limit": limit,
                "Columns": [],
                "Filter": [{
                    "Type": "FilterPredicate",
                    "FilterType": "Equals",
                    "Column": "trustee",
                    "Value": address
                }],
                "Order": [
                    {
                        "Column": "blockNumber",
                        "SortOrder": "DESC"
                    },
                    {
                        "Column": "transactionIndex",
                        "SortOrder": "DESC"
                    },
                    {
                        "Column": "logIndex",
                        "SortOrder": "DESC"
                    }
                ]
            }
        ]
        result = self._make_request("circles_query", params)

        # Extract the keys and rows from the result
        if 'columns' not in result or 'rows' not in result:
            raise ValueError("Unexpected response structure: result should contain 'columns' and 'rows'.")

        keys = result['columns']
        rows = result['rows']

        try:
            truster_index = keys.index('truster')
            expiry_index = keys.index('expiryTime')
            print(f"Truster index found at: {truster_index}, Expiry index found at: {expiry_index}")
        except ValueError as e:
            print("Required columns not found in keys.")
            raise e

        # Current timestamp determines whether trust has expired past expiryTime
        current_timestamp = int(time.time())

        # Filter for active trust relationships and extract unique trusters
        active_trusters = set()
        for row in rows:
            truster = row[truster_index].lower()
            expiry_time = int(row[expiry_index])

            if not Web3.is_address(truster):
                raise ValueError(f"Invalid Ethereum address: {truster}")

            # Only include trusters whose trust hasn't expired and who aren't the trustee themselves
            if expiry_time > current_timestamp and truster != address:
                active_trusters.add(truster)

        return set(active_trusters)
