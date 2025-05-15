import requests
import logging
from typing import Dict, List

logger = logging.getLogger(__name__)

class ScreeningClient:
    def __init__(self, base_url: str):
        self.base_url = base_url
        logger.info(f"Initialized ScreeningClient with base URL: {base_url}")

    def check_blacklist(self, addresses: List[str]) -> List[str]:
        """Check a list of addresses against the blacklist."""
        if not addresses:
            return []

        endpoint = "bot-analytics/classify"
        payload = {"addresses": addresses}

        try:
            response = requests.post(f"{self.base_url}/{endpoint}", json=payload, timeout=30)
            response.raise_for_status()
            data = response.json()

            verdicts = data.get("verdicts", [])
            blocked_addresses = [
                v["address"] for v in verdicts
                if v.get("is_bot") or v.get("category") in ["blocked", "flagged"]
            ]

            return blocked_addresses

        except Exception as e:
            logger.error(f"Error checking blacklist: {e}")
            return []

    def check_health(self) -> Dict:
        """Check the health of the screening service using a dummy blacklist check."""
        health = {
            "connected": False,
            "status": "unhealthy"
        }

        try:
            test_address = ["0x0000000000000000000000000000000000000000"]
            endpoint = f"{self.base_url}/bot-analytics/classify"
            response = requests.post(endpoint, json={"addresses": test_address}, timeout=5)

            if response.status_code == 200:
                data = response.json()
                if isinstance(data, dict) and "verdicts" in data:
                    health["connected"] = True
                    health["status"] = "healthy"
            else:
                logger.warning(f"Screening health check returned non-200 status: {response.status_code}")

        except Exception as e:
            logger.error(f"Screening service health check failed: {e}")

        return health
