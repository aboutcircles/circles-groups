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
        self.screening_url = self._get_env('ALLOWLIST_ENDPOINT')
        self.private_key = self._get_env('PRIVATE_KEY')

        # File paths
        self.baseGroup_abi_path = os.path.join(self.CONFIG_DIR, 'BaseGroupABI.json')
        self.circles_backing_abi_path = os.path.join(self.CONFIG_DIR, 'CirclesBackingABI.json')

        # Slack configuration - only webhook URL, no channel needed
        self.slack_webhook_url = self._get_env('SLACK_WEBHOOK_URL')  # Optional, empty string if not set

        # Service settings
        self.max_block_lag = int(self._get_env('MAX_BLOCK_LAG', '5'))  # Default 5 blocks allowed
        self.retry_interval = int(self._get_env('RETRY_INTERVAL', '300'))  # Default 5 minutes
        self.max_retries = int(self._get_env('MAX_RETRIES', '10'))  # Default 10 retries
        self.deploy_block = int(self._get_env('DEPLOY_BLOCK','39741602'))
        self.factory_address = self._get_env('FACTORY_ADDRESS', '0xeced91232c609a42f6016860e8223b8aecaa7bd0')

        # API settings
        self.api_host = self._get_env('API_HOST', '0.0.0.0')
        self.api_port = int(self._get_env('API_PORT', '8080'))
        self.enable_api = self._get_env('ENABLE_API', 'true').lower() == 'true'

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
            'screening_url': self.screening_url,
            'baseGroup_address': self.baseGroup_address,
            'private_key': self.private_key[:6] + '...' if self.private_key else None,  # Show only part of the private key for security
            'baseGroup_abi_path': self.baseGroup_abi_path,
            'circles_backing_abi_path': self.circles_backing_abi_path,
            'slack_configured': bool(self.slack_webhook_url),
            'api_enabled': self.enable_api,
            'api_port': self.api_port
        }

    @property
    def slack_enabled(self) -> bool:
        """Check if Slack notifications are enabled"""
        return bool(self.slack_webhook_url)

# Create a global settings instance
settings = Settings()
