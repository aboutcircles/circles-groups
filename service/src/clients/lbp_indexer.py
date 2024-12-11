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

    def is_crc_sufficiently_backed(self, account: str) -> bool:
        """Check if the CRC of an account is sufficiently backed."""
        result = self._make_request(f"lbp/{account}")
        depth_dollars = result.get('depth_dollars', 0)
        depth_crc = result.get('depth_crc', 0)
        price = result.get('price', 0)
        return depth_dollars >= 100 and depth_crc >= 48 and price >= 0.01

    def get_backers(self, account: str) -> list:
        """Get the backers for a given account."""
        result = self._make_request(f"lbp/backers/{account}")
        return list(result.values())
