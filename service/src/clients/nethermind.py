import requests

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

    def get_trusted_accounts(self, address : str) -> list:
        """Get the current list of trusted accounts for a given address"""
        result = self._make_request("getTrustedAccounts", [address])
        return list(result.values())

    def get_all_v2_humans(self) -> list:
        """Get a list of all v2 human accounts registered in the Hub"""
        # todo: for now there are only 400+ humans, soon improve by caching and then appending new
        return self.get_all_humans_with_pagination(1000)

    def get_all_humans_with_pagination(self, limit: int = 1000) -> list:
        """Get a paginated list of all human accounts registered in the Hub."""
        if limit > 1000:
            raise ValueError("Limit exceeds maximum allowed value of 1000.")

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

        return human_addresses
