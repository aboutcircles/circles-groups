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
        """Check the health of the screening service."""
        health = {
            "connected": False,
            "status": "unhealthy"
        }

        try:
            response = requests.get(f"{self.base_url}/health", timeout=5)
            health["connected"] = response.status_code == 200

            if health["connected"]:
                health["status"] = "healthy"

        except Exception as e:
            logger.error(f"Screening service health check failed: {e}")

        return health
