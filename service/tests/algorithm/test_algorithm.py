import unittest
from unittest.mock import MagicMock, patch, mock_open
import json
from datetime import datetime
from web3 import Web3
from src.algorithm.trust_management import TrustManagementAlgorithm
from src.clients.nethermind import NethermindClient
from src.clients.screening import ScreeningClient
from src.algorithm.lbp_processor import LBPProcessor
from src.utils.slack_notifier import SlackNotifier


class TestTrustManagementAlgorithm(unittest.TestCase):
    def setUp(self):
        """Set up the TrustManagementAlgorithm with mocked dependencies."""
        # Mock dependencies
        self.mock_nethermind_client = MagicMock(spec=NethermindClient)
        self.mock_screening_client = MagicMock(spec=ScreeningClient)
        self.mock_slack_notifier = MagicMock(spec=SlackNotifier)

        # Create a mock web3 object
        self.mock_web3 = MagicMock()
        self.mock_web3.eth.block_number = 1000
        self.mock_web3.is_connected.return_value = True
        self.mock_web3.eth.account.from_key.return_value = MagicMock(address="0xService")
        self.mock_nethermind_client.web3 = self.mock_web3

        # Create a mock contract
        self.mock_contract = MagicMock()
        self.mock_web3.eth.contract.return_value = self.mock_contract

        # Mock settings paths
        self.mock_settings = MagicMock()
        self.mock_settings.baseGroup_abi_path = 'mock_path'

        # Mock the fetch_group_trust_relations method
        self.mock_nethermind_client.fetch_group_trust_relations.return_value = (
            {"0xTrustee1", "0xTrustee2"},
            900
        )

        # Mock settings
        with patch('src.algorithm.trust_management.settings', self.mock_settings):
            # Mock open and json.load for loading the ABI
            with patch('builtins.open', mock_open(read_data='{"abi": "mock"}')):
                with patch('json.load', return_value=[]):
                    # Initialize the algorithm
                    self.algorithm = TrustManagementAlgorithm(
                        nethermind_client=self.mock_nethermind_client,
                        screening_client=self.mock_screening_client,
                        baseGroup_address="0xBaseGroup",
                        private_key="mock_private_key",
                        slack_notifier=self.mock_slack_notifier
                    )

    def test_initialization(self):
        """Test algorithm initialization."""
        # Verify dependencies were initialized correctly
        self.assertEqual(self.algorithm.nethermind_client, self.mock_nethermind_client)
        self.assertEqual(self.algorithm.screening_client, self.mock_screening_client)
        self.assertEqual(self.algorithm.baseGroup_address, "0xBaseGroup")
        self.assertEqual(self.algorithm.private_key, "mock_private_key")
        self.assertEqual(self.algorithm.slack_notifier, self.mock_slack_notifier)

        # Verify state was initialized correctly
        self.assertEqual(self.algorithm._trusted_accounts, {"0xTrustee1", "0xTrustee2"})
        self.assertEqual(self.algorithm._last_trust_block, 900)

        # Verify the LBP processor was initialized
        self.assertIsInstance(self.algorithm.lbp_processor, LBPProcessor)

    def test_run_with_no_new_blocks(self):
        """Test running the algorithm with no new blocks to process."""
        # Set up the test
        self.algorithm._last_processed_block = 1000  # Same as current block

        # Run the algorithm
        self.algorithm.run()

        # Verify no processing occurred
        self.mock_nethermind_client.fetch_backing_status.assert_not_called()
        self.mock_nethermind_client.fetch_group_trust_relations.assert_not_called()

    def test_run_with_new_blocks(self):
        """Test running the algorithm with new blocks to process."""
        # Set up the test
        self.algorithm._last_processed_block = 950  # Earlier than current block (1000)

        # Mock fetch_backing_status to return some results
        self.mock_nethermind_client.fetch_backing_status.return_value = (
            {("0xBacker1", "0xInstance1")},  # fallback_pairs
            {"0xBacker2"},  # completed_backers
            990  # latest_block
        )

        # Create a mock LBP processor
        mock_lbp_processor = MagicMock(spec=LBPProcessor)
        mock_lbp_processor.get_completed_backers.return_value = {"0xBacker3"}
        mock_lbp_processor.get_stats.return_value = {
            'lbp_created': 5,
            'lbp_failed': 2,
            'pending_instances': 3,
            'problem_instances': 1
        }
        self.algorithm.lbp_processor = mock_lbp_processor

        # Run the algorithm
        self.algorithm.run()

        # Verify correct methods were called
        self.mock_nethermind_client.fetch_backing_status.assert_called_once_with(950)
        mock_lbp_processor.process_instance.assert_called_once_with("0xInstance1", "0xBacker1")
        mock_lbp_processor.get_completed_backers.assert_called_once()
        mock_lbp_processor.retry_pending_instances.assert_called_once()

        # Verify completed backers were processed
        # This is mocked in the next test specifically, so we just check if the method would be called

        # Verify last_processed_block was updated
        self.assertEqual(self.algorithm._last_processed_block, 1000)

    def test_process_completed_backers(self):
        """Test processing completed backers."""
        # Set up the test
        completed_backers = {"0xBacker1", "0xBacker2", "0xTrustee1"}  # one already trusted
        self.algorithm._trusted_accounts = {"0xTrustee1", "0xTrustee2"}

        # Mock check_blacklist to filter some addresses
        self.mock_screening_client.check_blacklist.return_value = ["0xBacker2"]  # blacklisted

        # Mock the execution of trust batch
        with patch.object(self.algorithm, '_execute_trust_batch') as mock_execute:
            # Process the backers
            self.algorithm._process_completed_backers(completed_backers)

            # Verify blacklist check
            self.mock_screening_client.check_blacklist.assert_called_once()

            # Verify trust batch execution
            mock_execute.assert_called_once()
            # Check arguments (need to handle the conversion to checksum addresses)
            args = mock_execute.call_args[0][0]
            self.assertEqual(len(args), 1)
            self.assertEqual(Web3.to_checksum_address("0xBacker1"), args[0])

            # Verify stats and trusted_accounts were updated
            self.assertEqual(self.algorithm.stats['backers_trusted'], 1)
            self.assertEqual(self.algorithm.stats['blacklisted_addresses'], 1)
            self.assertIn("0xbacker1", self.algorithm._trusted_accounts)  # note: lowercase

    def test_execute_trust_batch(self):
        """Test executing a trust batch transaction."""
        # Set up test addresses
        addresses = [Web3.to_checksum_address("0xAddress1"), Web3.to_checksum_address("0xAddress2")]

# Mock web3 transaction functions
        self.mock_web3.eth.get_transaction_count.return_value = 123
        self.mock_web3.eth.gas_price = 20000000000
        self.mock_web3.eth.send_raw_transaction.return_value = b"tx_hash"
        self.mock_web3.eth.wait_for_transaction_receipt.return_value = {"blockNumber": 1001}

# Mock the contract function
        mock_function = MagicMock()
        self.mock_contract.functions.trustBatchWithConditions.return_value = mock_function
        mock_function.build_transaction.return_value = {"mock": "transaction"}

# Execute the trust batch
        # Convert addresses to List[str] type for compatibility
        str_addresses = [str(addr) for addr in addresses]
        self.algorithm._execute_trust_batch(str_addresses)

# Verify the contract call
        self.mock_contract.functions.trustBatchWithConditions.assert_called_once()
        # First arg should be addresses, second arg should be expiry
        args, _ = self.mock_contract.functions.trustBatchWithConditions.call_args
        self.assertEqual(args[0], str_addresses)
        self.assertEqual(args[1], 2**96 - 1)  # Maximum expiry

# Verify transaction was sent
        self.mock_web3.eth.account.sign_transaction.assert_called_once()
        self.mock_web3.eth.send_raw_transaction.assert_called_once()
        self.mock_web3.eth.wait_for_transaction_receipt.assert_called_once()

    def test_check_health(self):
        """Test health check functionality."""
        # Mock block number
        self.mock_web3.eth.block_number = 1000

        # Mock LBP processor stats
        mock_lbp_processor = MagicMock(spec=LBPProcessor)
        mock_lbp_processor.get_stats.return_value = {
            'lbp_created': 5,
            'lbp_failed': 2,
            'pending_instances': 3,
            'problem_instances': 1,
            'reset_succeeded': 4,
            'reset_failed': 1,
            'indexer_issues': 0
        }
        self.algorithm.lbp_processor = mock_lbp_processor

        # Set up some state
        self.algorithm._last_processed_block = 990
        self.algorithm._last_trust_block = 950
        self.algorithm._trusted_accounts = {"0xTrustee1", "0xTrustee2"}
        self.algorithm.stats = {
            'start_time': datetime(2023, 1, 1, 0, 0, 0),
            'backers_trusted': 10,
            'blacklisted_addresses': 3
        }

        # Get health check
        health = self.algorithm.check_health()

        # Verify health data
        self.assertEqual(health['status'], 'healthy')
        self.assertEqual(health['current_block'], 1000)
        self.assertEqual(health['last_processed_block'], 990)
        self.assertEqual(health['last_trust_block'], 950)
        self.assertEqual(health['block_lag'], 10)
        self.assertEqual(health['trusted_accounts_count'], 2)
        self.assertEqual(health['backers_trusted'], 10)
        self.assertEqual(health['blacklisted_addresses'], 3)
        self.assertEqual(health['lbp_created'], 5)
        self.assertEqual(health['lbp_failed'], 2)
        self.assertEqual(health['pending_instances'], 3)
        self.assertEqual(health['problem_instances'], 1)

    def test_flush(self):
        """Test flushing the algorithm state."""
        # Set up some state
        self.algorithm._last_processed_block = 990
        self.algorithm.stats = {
            'start_time': datetime(2023, 1, 1, 0, 0, 0),
            'backers_trusted': 10,
            'blacklisted_addresses': 3
        }

        # Mock fetch_group_trust_relations for the flush
        self.mock_nethermind_client.fetch_group_trust_relations.return_value = (
            {"0xTrustee3", "0xTrustee4"},
            995
        )

        # Create a mock LBP processor
        mock_lbp_processor = MagicMock(spec=LBPProcessor)
        self.algorithm.lbp_processor = mock_lbp_processor

        # Flush the algorithm
        self.algorithm.flush()

        # Verify state was reset
        self.assertEqual(self.algorithm._trusted_accounts, {"0xTrustee3", "0xTrustee4"})
        self.assertEqual(self.algorithm._last_trust_block, 995)
        self.assertEqual(self.algorithm._last_processed_block, 0)

        # Verify stats were reset but start_time was preserved
        self.assertEqual(self.algorithm.stats['start_time'], datetime(2023, 1, 1, 0, 0, 0))
        self.assertEqual(self.algorithm.stats['backers_trusted'], 0)
        self.assertEqual(self.algorithm.stats['blacklisted_addresses'], 0)

        # Verify LBP processor was reset
        mock_lbp_processor.reset.assert_called_once()


if __name__ == "__main__":
    unittest.main()
