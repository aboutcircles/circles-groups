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

    def screen_address(self, address: str) -> dict:
        """Screen an address."""
        result = self._make_request(f"screen/{address}")
        return result

    def get_screening_report(self, report_id: str) -> dict:
        """Get a screening report by ID."""
        result = self._make_request(f"reports/{report_id}")
        return result
