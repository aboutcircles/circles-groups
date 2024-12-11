import requests

class ScreeningClient:
    def __init__(self, base_url: str):
        self.base_url = base_url

    def _make_request(self, endpoint: str) -> dict:
        """Make a GET request to the Screening API."""
        url = f"{self.base_url}/{endpoint}"
        response = requests.get(url)
        response.raise_for_status()
        return response.json()

    def get_blacklisted_accounts(self) -> list:
        """Get the list of blacklisted accounts."""
        result = self._make_request("getBlacklisted")
        return list(result.values())
