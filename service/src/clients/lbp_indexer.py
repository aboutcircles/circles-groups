import requests

class LBPIndexerClient:
    def __init__(self, base_url: str):
        self.base_url = base_url

    def _make_request(self, endpoint: str) -> dict:
        """Make a GET request to the LBP Indexer API."""
        url = f"{self.base_url}/{endpoint}"
        response = requests.get(url)
        response.raise_for_status()
        return response.json()

    def get_pools(self) -> list:
        """Get a list of pools."""
        result = self._make_request("pools")
        return list(result.values())

    def get_pool_details(self, pool_id: str) -> dict:
        """Get details for a specific pool."""
        result = self._make_request(f"pools/{pool_id}")
        return result
