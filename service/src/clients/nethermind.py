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
        result = self._make_request("getAllV2Humans", [])
        return list(result.values())
