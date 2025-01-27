import unittest
from unittest.mock import MagicMock, patch
from src.algorithm.trust_management import TrustManagementAlgorithm
from src.config.settings import settings
from src.clients.nethermind import NethermindClient
from src.clients.screening import ScreeningClient

class TestTrustManagementAlgorithm(unittest.TestCase):
    def setUp(self):
        """Set up the TrustManagementAlgorithm with mocked dependencies."""
        # Mock dependencies
        self.mock_nethermind_client = MagicMock()
        self.mock_screening_client = MagicMock()
        self.mock_web3 = MagicMock()

        # Mock contract and transaction signing
        self.mock_contract = MagicMock()
        self.mock_web3.eth.contract.return_value = self.mock_contract
        self.mock_web3.eth.get_transaction_count.return_value = 1
        self.mock_web3.eth.send_raw_transaction.return_value = b"mock_tx_hash"
        self.mock_web3.eth.wait_for_transaction_receipt.return_value = MagicMock(blockNumber=123)

        # Initialize TrustManagementAlgorithm
        self.trust_algo = TrustManagementAlgorithm(
            nethermind_client=self.mock_nethermind_client,
            screening_client=self.mock_screening_client,
            supergroup_address="0xSupergroupAddress",
            web3=self.mock_web3,
            private_key="mock_private_key",
            supergroup_contract_address="0xContractAddress",
            supergroup_contract_abi=[]
        )
        self.trust_algo.initialize()

    def test_initialize_trusted_accounts(self):
        """Test if trusted accounts are initialized correctly."""
        # Mock fetch_group_trust_relations response
        self.mock_nethermind_client.fetch_group_trust_relations.return_value = [
            "0xTrustedAccount1", "0xTrustedAccount2"
        ]

        # Initialize trusted accounts
        self.trust_algo.initialize()

        # Verify the trusted accounts
        self.assertEqual(self.trust_algo.trusted_accounts, {"0xTrustedAccount1", "0xTrustedAccount2"})

    def test_run_trust_management_with_valid_backers(self):
        """Test the trust management process with valid backers."""
        # Mock responses
        self.mock_nethermind_client.fetch_group_trust_relations.return_value = ["0xTrustedAccount1"]
        self.mock_nethermind_client.fetch_backers.return_value = ["0xNewBacker", "0xTrustedAccount1"]
        self.mock_screening_client.check_blacklist.return_value = ["0xBlacklistedAddress"]

        # Initialize and run the algorithm
        self.trust_algo.initialize()
        self.trust_algo.run_trust_management()

        # Verify trusted accounts are updated
        self.assertIn("0xNewBacker", self.trust_algo.trusted_accounts)
        self.mock_contract.functions.trustBatch.assert_called_once()

    def test_run_trust_management_with_no_valid_backers(self):
        """Test the trust management process when no valid backers are found."""
        # Mock responses
        self.mock_nethermind_client.fetch_group_trust_relations.return_value = ["0xTrustedAccount1"]
        self.mock_nethermind_client.fetch_backers.return_value = ["0xBlacklistedBacker"]
        self.mock_screening_client.check_blacklist.return_value = ["0xBlacklistedBacker"]

        # Initialize and run the algorithm
        self.trust_algo.initialize()
        self.trust_algo.run_trust_management()

        # Verify no update is made
        self.mock_contract.functions.trustBatch.assert_not_called()

    def test_call_trust_batch(self):
        """Test the call_trust_batch method for valid backers."""
        valid_backers = {"0xValidBacker1", "0xValidBacker2"}

        # Call trustBatch
        self.trust_algo.call_trust_batch(valid_backers)

        # Verify the contract call
        self.mock_contract.functions.trustBatch.assert_called_once_with(
            list(valid_backers),  # Backers
            unittest.mock.ANY  # Expiry timestamp
        )
        self.mock_web3.eth.send_raw_transaction.assert_called_once()

    def test_flush_trusted_accounts(self):
        """Test flushing the trusted accounts."""
        # Add trusted accounts
        self.trust_algo.trusted_accounts = {"0xTrustedAccount1", "0xTrustedAccount2"}

        # Flush the trusted accounts
        self.trust_algo.flush()

        # Verify trusted accounts are reset
        self.assertEqual(len(self.trust_algo.trusted_accounts), 0)

    @patch("time.sleep", return_value=None)
    def test_polling_service(self, mock_sleep):
        """Test the PollingService integration with trust management."""
        from TrustManagementAlgorithm import PollingService

        # Mock the polling service
        polling_service = PollingService(rpc_url="http://mock-rpc-url", poll_interval=1)
        polling_service.web3 = self.mock_web3

        # Mock the block number
        self.mock_web3.eth.block_number = 10

        # Run polling
        with patch.object(self.trust_algo, "run_trust_management") as mock_run_trust_management:
            polling_service.start_polling(self.trust_algo)

            # Verify the trust management is triggered
            mock_run_trust_management.assert_called()

if __name__ == "__main__":
    unittest.main()
