import requests

class ScreeningClient:
    def __init__(self, base_url: str):
        self.base_url = base_url

    def _make_request(self, endpoint: str, method: str = "GET", data: dict | None = None) -> dict:
        """Make a request to the Screening API."""
        url = f"{self.base_url}/{endpoint}"
        try:
            if method == "GET":
                response = requests.get(url)
            elif method == "POST":
                response = requests.post(url, json=data)
            else:
                raise ValueError("Unsupported HTTP method")

            response.raise_for_status()
            return response.json()
        except requests.RequestException as e:
            print(f"Request failed: {e}")
            return {}

    def check_blacklist(self, addresses: list) -> list:
        """Check a list of addresses against the blacklist."""
        endpoint = "bot-analytics/classify"
        payload = {"addresses": addresses}

        response = self._make_request(endpoint, method="POST", data=payload)
        verdicts = response.get("verdicts", [])
        return [v["address"] for v in verdicts if v.get("is_bot") or v.get("category") in ["blocked", "flagged"]]
