import unittest
from unittest.mock import MagicMock, patch
import time
from web3.exceptions import ContractLogicError
from src.algorithm.lbp_processor import LBPProcessor
from src.clients.nethermind import NethermindClient
from src.utils.slack_notifier import SlackNotifier


class TestLBPProcessor(unittest.TestCase):
    def setUp(self):
        """Initialize test environment with mocked dependencies."""
        # Mock the Nethermind client
        self.mock_nethermind = MagicMock(spec=NethermindClient)
        self.mock_slack = MagicMock(spec=SlackNotifier)

        # Configure mock web3 object
        self.mock_web3 = MagicMock()
        self.mock_web3.eth.block_number = 100
        self.mock_nethermind.web3 = self.mock_web3

        # Create processor with test configuration
        self.processor = LBPProcessor(
            nethermind_client=self.mock_nethermind,
            private_key="test_private_key",
            slack_notifier=self.mock_slack,
            retry_interval=5,
            max_retries=3
        )

    def test_already_completed_instance(self):
        """Verify handling of instances that have already been completed."""
        instance = "0xABCD"
        backer = "0xBACKER"

        # Configure mock to show completion
        self.mock_nethermind.check_completed_event.return_value = True

        # Execute test
        result = self.processor.process_instance(instance, backer)

        # Verify results
        self.assertTrue(result)
        self.mock_nethermind.check_completed_event.assert_called_once_with(
            instance.lower(), backer.lower()
        )
        self.assertIn(backer.lower(), self.processor._completed_backers)

    def test_successful_reset_cowswap_order(self):
        """Test successful resetCowswapOrder execution path."""
        instance = "0xABCD"
        backer = "0xBACKER"

        # Configure mocks
        self.mock_nethermind.check_completed_event.return_value = False
        self.mock_nethermind.eth_call_reset_cowswap_order.return_value = None
        self.mock_nethermind.execute_reset_cowswap_order.return_value = {
            "transactionHash": "0xTRANSACTION_HASH"
        }

        # Execute test
        result = self.processor.process_instance(instance, backer)

        # Verify results
        self.assertTrue(result)
        self.mock_nethermind.eth_call_reset_cowswap_order.assert_called_once_with(
            instance_address=instance.lower()
        )
        self.mock_nethermind.execute_reset_cowswap_order.assert_called_once()
        self.assertIn(instance.lower(), self.processor.pending_instances)
        self.assertEqual(
            self.processor.pending_instances[instance.lower()]['type'],
            'check_completion'
        )
        self.assertEqual(self.processor.stats['reset_succeeded'], 1)

    def test_order_already_settled_fallback_to_lbp(self):
        """Test fallback to LBP creation when order is already settled."""
        instance = "0xABCD"
        backer = "0xBACKER"

        # Configure mocks
        self.mock_nethermind.check_completed_event.return_value = False
        self.mock_nethermind.eth_call_reset_cowswap_order.side_effect = ContractLogicError(
            f"execution reverted: {self.processor.ERROR_ORDER_ALREADY_SETTLED}"
        )
        self.mock_nethermind.eth_call_create_lbp.return_value = None
        self.mock_nethermind.execute_create_lbp.return_value = {
            "transactionHash": "0xTRANSACTION_HASH"
        }

        # Execute test
        result = self.processor.process_instance(instance, backer)

        # Verify results
        self.assertTrue(result)
        self.mock_nethermind.eth_call_create_lbp.assert_called_once()
        self.mock_nethermind.execute_create_lbp.assert_called_once()
        self.assertIn(instance.lower(), self.processor.pending_instances)
        self.assertEqual(self.processor.stats['lbp_created'], 1)

    def test_lbp_already_created(self):
        """Test handling when LBP has already been created."""
        instance = "0xABCD"
        backer = "0xBACKER"

        # Configure mocks
        self.mock_nethermind.check_completed_event.return_value = False
        self.mock_nethermind.eth_call_reset_cowswap_order.side_effect = ContractLogicError(
            f"execution reverted: {self.processor.ERROR_ORDER_ALREADY_SETTLED}"
        )
        self.mock_nethermind.eth_call_create_lbp.side_effect = ContractLogicError(
            f"execution reverted: {self.processor.ERROR_LBP_ALREADY_CREATED}"
        )

        # Execute test
        result = self.processor.process_instance(instance, backer)

        # Verify results
        self.assertTrue(result)
        self.mock_nethermind.eth_call_reset_cowswap_order.assert_called_once()
        self.mock_nethermind.eth_call_create_lbp.assert_called_once()
        self.assertIn(instance.lower(), self.processor.pending_instances)
        self.assertEqual(
            self.processor.pending_instances[instance.lower()]['type'],
            'check_completion'
        )

    def test_insufficient_balance_error(self):
        """Test handling of insufficient balance errors."""
        instance = "0xABCD"
        backer = "0xBACKER"

        # Configure mocks
        self.mock_nethermind.check_completed_event.return_value = False
        self.mock_nethermind.eth_call_reset_cowswap_order.side_effect = ContractLogicError(
            f"execution reverted: {self.processor.ERROR_ORDER_ALREADY_SETTLED}"
        )
        self.mock_nethermind.eth_call_create_lbp.side_effect = ContractLogicError(
            f"execution reverted: {self.processor.ERROR_BACKING_ASSET_INSUFFICIENT}"
        )

        # Execute test
        result = self.processor.process_instance(instance, backer)

        # Verify results
        self.assertFalse(result)
        self.assertIn(instance.lower(), self.processor.problem_instances)
        self.mock_slack.notify_insufficient_balance.assert_called_once()

    def test_order_uid_same_retry_scheduling(self):
        """Test scheduling retry when order UID is the same."""
        instance = "0xABCD"
        backer = "0xBACKER"

        # Configure mocks
        self.mock_nethermind.check_completed_event.return_value = False
        self.mock_nethermind.eth_call_reset_cowswap_order.side_effect = ContractLogicError(
            f"execution reverted: {self.processor.ERROR_ORDER_UID_SAME}"
        )

        # Execute test with mocked time
        with patch('time.time', return_value=1000.0):
            result = self.processor.process_instance(instance, backer)

        # Verify results
        self.assertTrue(result)
        self.mock_nethermind.eth_call_reset_cowswap_order.assert_called_once()
        self.assertIn(instance.lower(), self.processor.pending_instances)
        self.assertEqual(
            self.processor.pending_instances[instance.lower()]['type'],
            'reset_retry'
        )
        self.assertEqual(
            self.processor.pending_instances[instance.lower()]['retry_count'],
            1
        )
        self.assertEqual(
            self.processor.pending_instances[instance.lower()]['next_retry_time'],
            1000.0 + 180  # 3 minutes delay
        )

    def test_pending_completion_check(self):
        """Test processing of pending completion checks."""
        instance = "0xABCD"
        backer = "0xBACKER"

        # Add instance to pending completion checks
        current_time = time.time()
        self.processor.pending_instances[instance] = {
            'backer': backer,
            'retry_count': 0,
            'last_attempt': current_time - 10,
            'type': 'check_completion',
            'next_check_block': 90,  # Less than current block (100)
            'timestamp': current_time - 10
        }

        # Configure mocks
        self.mock_nethermind.check_completed_event.return_value = True

        # Execute test
        self.processor.process_pending_instances()

        # Verify results
        self.mock_nethermind.check_completed_event.assert_called_once()
        self.assertNotIn(instance, self.processor.pending_instances)
        self.assertIn(backer, self.processor._completed_backers)

    def test_pending_reset_retry_success(self):
        """Test processing of pending reset retry that succeeds."""
        instance = "0xABCD"
        backer = "0xBACKER"
        current_time = time.time()

        # Add instance to pending reset retries
        self.processor.pending_instances[instance] = {
            'backer': backer,
            'retry_count': 1,
            'last_attempt': current_time - 10,
            'type': 'reset_retry',
            'next_retry_time': current_time - 5,  # Ready for retry
            'timestamp': current_time - 10
        }

        # Configure mocks
        self.mock_nethermind.eth_call_reset_cowswap_order.return_value = None
        self.mock_nethermind.execute_reset_cowswap_order.return_value = {
            "transactionHash": "0xTRANSACTION_HASH"
        }

        # Execute test
        self.processor.process_pending_instances()

        # Verify results
        self.mock_nethermind.eth_call_reset_cowswap_order.assert_called_once()
        self.mock_nethermind.execute_reset_cowswap_order.assert_called_once()
        self.assertIn(instance, self.processor.pending_instances)
        self.assertEqual(
            self.processor.pending_instances[instance]['type'],
            'check_completion'
        )
        self.assertEqual(self.processor.stats['reset_succeeded'], 1)

    def test_pending_reset_retry_with_order_settled(self):
        """Test processing of pending reset retry with order already settled."""
        instance = "0xABCD"
        backer = "0xBACKER"
        current_time = time.time()

        # Add instance to pending reset retries
        self.processor.pending_instances[instance] = {
            'backer': backer,
            'retry_count': 1,
            'last_attempt': current_time - 10,
            'type': 'reset_retry',
            'next_retry_time': current_time - 5,  # Ready for retry
            'timestamp': current_time - 10
        }

        # Configure mocks
        self.mock_nethermind.eth_call_reset_cowswap_order.side_effect = ContractLogicError(
            f"execution reverted: {self.processor.ERROR_ORDER_ALREADY_SETTLED}"
        )
        self.mock_nethermind.eth_call_create_lbp.return_value = None
        self.mock_nethermind.execute_create_lbp.return_value = {
            "transactionHash": "0xTRANSACTION_HASH"
        }

        # Execute test
        self.processor.process_pending_instances()

        # Verify results
        self.mock_nethermind.validate_reset_cowswap_order.assert_called_once()
        self.mock_nethermind.validate_create_lbp.assert_called_once()
        self.mock_nethermind.execute_create_lbp.assert_called_once()
        self.assertNotIn(instance, self.processor.pending_instances)

    def test_max_retries_exceeded(self):
        """Test handling when max retries are exceeded."""
        instance = "0xABCD"
        backer = "0xBACKER"
        current_time = time.time()

        # Add instance that has reached max retries
        self.processor.pending_instances[instance] = {
            'backer': backer,
            'retry_count': self.processor.max_retries,
            'last_attempt': current_time - 10,
            'type': 'reset_retry',
            'next_retry_time': current_time - 5,
            'error': 'Previous error',
            'timestamp': current_time - 10
        }

        # Execute test
        self.processor.process_pending_instances()

        # Verify results
        self.assertNotIn(instance, self.processor.pending_instances)
        self.assertIn(instance, self.processor.problem_instances)
        self.assertIn('Exceeded max retries', self.processor.problem_instances[instance]['error'])

    def test_get_completed_backers(self):
        """Test retrieval and clearing of completed backers."""
        # Add completed backers
        self.processor._completed_backers = {"0xbacker1", "0xbacker2"}

        # Execute test
        completed = self.processor.get_completed_backers()

        # Verify results
        self.assertEqual(completed, {"0xbacker1", "0xbacker2"})
        self.assertEqual(len(self.processor._completed_backers), 0)  # Should be cleared

    def test_get_stats(self):
        """Test retrieval of processor statistics."""
        # Set up statistics
        self.processor.stats = {
            'lbp_created': 5,
            'lbp_failed': 2,
            'reset_succeeded': 8,
            'reset_failed': 1,
            'indexer_issues': 3
        }
        self.processor.pending_instances = {"0x1": {}, "0x2": {}}
        self.processor.problem_instances = {"0x3": {}}

        # Execute test
        stats = self.processor.get_stats()

        # Verify results
        self.assertEqual(stats['lbp_created'], 5)
        self.assertEqual(stats['lbp_failed'], 2)
        self.assertEqual(stats['reset_succeeded'], 8)
        self.assertEqual(stats['reset_failed'], 1)
        self.assertEqual(stats['indexer_issues'], 3)
        self.assertEqual(stats['pending_instances'], 2)
        self.assertEqual(stats['problem_instances'], 1)

    def test_reset(self):
        """Test resetting of processor state."""
        # Set up state
        self.processor.pending_instances = {"0x1": {}}
        self.processor.problem_instances = {"0x2": {}}
        self.processor._completed_backers = {"0xbacker"}
        self.processor.stats = {
            'lbp_created': 5,
            'lbp_failed': 2,
            'reset_succeeded': 8,
            'reset_failed': 1,
            'indexer_issues': 3
        }

        # Execute test
        self.processor.reset()

        # Verify results
        self.assertEqual(len(self.processor.pending_instances), 0)
        self.assertEqual(len(self.processor.problem_instances), 0)
        self.assertEqual(len(self.processor._completed_backers), 0)
        self.assertEqual(self.processor.stats['lbp_created'], 0)
        self.assertEqual(self.processor.stats['lbp_failed'], 0)
        self.assertEqual(self.processor.stats['reset_succeeded'], 0)
        self.assertEqual(self.processor.stats['reset_failed'], 0)
        self.assertEqual(self.processor.stats['indexer_issues'], 0)


if __name__ == "__main__":
    unittest.main()
