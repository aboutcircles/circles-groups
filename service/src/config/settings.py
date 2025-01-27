import os
from web3 import Web3
from typing import Dict, Any, Optional
from dotenv import load_dotenv

class Settings:
    """Application settings loaded from environment variables"""

    def __init__(self):
        # Load environment variables from .env file
        load_dotenv()

        # RPC endpoints
        self.nethermind_rpc_url = self._get_env('NETHERMIND_RPC_URL')
        # self.lbp_indexer_url = self._get_env('LBP_INDEXER_URL')
        self.screening_url = self._get_env('ALLOWLIST_ENDPOINT')
        self.private_key = self._get_env('PRIVATE_KEY')

        # # Algorithm settings
        # self.max_trusted = int(self._get_env('MAX_TRUSTED', '10000'))
        # self.change_threshold = int(self._get_env('CHANGE_THRESHOLD', '100'))
        # # Append-only flag: prevents untrusting previously trusted humans unless they are blacklisted
        # self.append_only = bool(self._get_env('APPEND_ONLY', 'true'))

        # # Service settings
        # self.update_interval = int(self._get_env('UPDATE_INTERVAL', '1800'))  # 30 minutes
        # self.update_max_offset = int(self._get_env('UPDATE_MAX_OFFSET', '300'))  # 5 minutes

        # Supergroup address
        supergroup_address = self._get_env('SUPERGROUP_ADDRESS')
        if not Web3.is_address(supergroup_address):
            raise ValueError(f"Invalid Ethereum address: {supergroup_address}")
        self.supergroup_address = Web3.to_checksum_address(supergroup_address)

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
            'lbp_indexer_url': self.lbp_indexer_url,
            'database_url': self.screening_url,
            'max_trusted': self.max_trusted,
            'change_threshold': self.change_threshold,
            'update_interval': self.update_interval,
            'update_max_offset': self.update_max_offset,
            'append_only': self.append_only,
            'supergroup_address': self.SUPERGROUP_ADDRESS,
            'private_key': self.PRIVATE_KEY
        }

# Create a global settings instance
settings = Settings()
