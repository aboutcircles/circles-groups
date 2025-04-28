import os
from web3 import Web3
from typing import Dict, Any, Optional
from dotenv import load_dotenv

class Settings:
    """Application settings loaded from environment variables"""

    def __init__(self):
        # Load environment variables from .env file
        load_dotenv()
        # Set up base paths
        self.BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        self.CONFIG_DIR = os.path.join(self.BASE_DIR, 'config')
        # RPC endpoints
        self.nethermind_rpc_url = self._get_env('NETHERMIND_RPC_URL')
        # self.lbp_indexer_url = self._get_env('LBP_INDEXER_URL')
        self.screening_url = self._get_env('ALLOWLIST_ENDPOINT')
        self.private_key = self._get_env('PRIVATE_KEY')
        # File paths
        self.baseGroup_abi_path = os.path.join(self.CONFIG_DIR, 'baseGroupABI.json')
        self.circles_backing_abi_path = os.path.join(self.CONFIG_DIR, 'CirclesBackingABI.json')
        self.slack_webhook_url = self._get_env('SLACK_WEBHOOK_URL')
        # # Algorithm settings
        # self.max_trusted = int(self._get_env('MAX_TRUSTED', '10000'))
        # self.change_threshold = int(self._get_env('CHANGE_THRESHOLD', '100'))
        # # Append-only flag: prevents untrusting previously trusted humans unless they are blacklisted
        # self.append_only = bool(self._get_env('APPEND_ONLY', 'true'))

        # # Service settings
        # self.update_interval = int(self._get_env('UPDATE_INTERVAL', '1800'))  # 30 minutes
        # self.update_max_offset = int(self._get_env('UPDATE_MAX_OFFSET', '300'))  # 5 minutes

        # Base Group address
        baseGroup_address = self._get_env('BASEGROUP_ADDRESS')
        if not Web3.is_address(baseGroup_address):
            raise ValueError(f"Invalid Ethereum address: {baseGroup_address}")

        self.baseGroup_address = Web3.to_checksum_address(baseGroup_address)

    def _get_env(self, key: str, default: Optional[str] = None) -> str:
        """Get environment variable with optional default"""
        value = os.getenv(key)
        if value is not None:
            return value

        if default is not None:
            return default

        # Raise an exception if neither value nor default is provided
        raise ValueError(f"Environment variable '{key}' not set and no default value provided.")

    def as_dict(self) -> Dict[str, Any]:
        """Return settings as a dictionary"""
        return {
            'nethermind_rpc_url': self.nethermind_rpc_url,
            'database_url': self.screening_url,
            'baseGroup_address': self.baseGroup_address,
            'private_key': self.private_key,
            'baseGroup_abi_path': self.baseGroup_abi_path,
            'circles_backing_abi_path': self.circles_backing_abi_path
        }

# Create a global settings instance
settings = Settings()
