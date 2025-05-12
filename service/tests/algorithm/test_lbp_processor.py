import unittest
from unittest.mock import MagicMock, patch
import time
from web3.exceptions import ContractLogicError
from src.algorithm.lbp_processor import LBPProcessor
from src.clients.nethermind import NethermindClient
from src.utils.slack_notifier import SlackNotifier


class TestLBPProcessor(unittest.TestCase):
    def setUp(self):
        """Set up the LBPProcessor with mocked dependencies."""
        # Mock dependencies
        self.mock_nethermind_client = MagicMock(spec=NethermindClient)
        self.mock_slack_notifier = MagicMock(spec=SlackNotifier)

        # Create a mock web3 object
        self.mock_web3 = MagicMock()
        self.mock_web3.eth.block_number = 100
        self.mock_nethermind_client.web3 = self.mock_web3

        # Initialize processor
        self.processor = LBPProcessor(
            nethermind_client=self.mock_nethermind_client,
            private_key="mock_private_key",
            slack_notifier=self.mock_slack_notifier,
            retry_interval=5,  # Short interval for tests
            max_retries=3
        )

    def test_process_instance_already_completed(self):
        """Test processing an instance that's already completed."""
        # Setup
        instance_address = "0x1234"
        backer_address = "0xbacker"

        # Mock the check_completed_event method to return True
        self.mock_nethermind_client.check_completed_event.return_value = True

        # Call the method
        result = self.processor.process_instance(instance_address, backer_address)

        # Assertions
        self.assertTrue(result)
        self.mock_nethermind_client.check_completed_event.assert_called_once_with(instance_address.lower(), backer_address.lower())
        self.assertEqual(len(self.processor._completed_backers), 1)
        self.assertIn(backer_address.lower(), self.processor._completed_backers)

    def test_process_instance_successful_reset(self):
        """Test successful processing of resetCowswapOrder."""
        # Setup
        instance_address = "0x1234"
        backer_address = "0xbacker"

        # Mock method responses
        self.mock_nethermind_client.check_completed_event.return_value = False

        # eth_call succeeds (no contract errors)
        self.mock_nethermind_client.eth_call_reset_cowswap_order.return_value = None

        # Successful execution
        self.mock_nethermind_client.execute_reset_cowswap_order.return_value = {
            "transactionHash": "0xhash"
        }

        # Call the method
        result = self.processor.process_instance(instance_address, backer_address)

        # Assertions
        self.assertTrue(result)
        self.mock_nethermind_client.eth_call_reset_cowswap_order.assert_called_once_with(instance_address=instance_address.lower())
        self.mock_nethermind_client.execute_reset_cowswap_order.assert_called_once()

        # Should be scheduled for completion check
        self.assertIn(instance_address.lower(), self.processor.pending_instances)
        self.assertEqual(self.processor.pending_instances[instance_address.lower()]['type'], 'check_completion')
        self.assertEqual(self.processor.stats['reset_succeeded'], 1)

    def test_process_instance_order_already_settled(self):
        """Test processing with OrderAlreadySettled error."""
        # Setup
        instance_address = "0x1234"
        backer_address = "0xbacker"

        # Mock method responses
        self.mock_nethermind_client.check_completed_event.return_value = False

        # eth_call raises OrderAlreadySettled
        self.mock_nethermind_client.eth_call_reset_cowswap_order.side_effect = ContractLogicError(
            f"execution reverted: {self.processor.ERROR_ORDER_ALREADY_SETTLED}"
        )

        # eth_call for createLBP succeeds
        self.mock_nethermind_client.eth_call_create_lbp.return_value = None

        # Successful LBP creation
        self.mock_nethermind_client.execute_create_lbp.return_value = {
            "transactionHash": "0xhash"
        }

        # Call the method
        result = self.processor.process_instance(instance_address, backer_address)

        # Assertions
        self.assertTrue(result)
        self.mock_nethermind_client.eth_call_reset_cowswap_order.assert_called_once()
        self.mock_nethermind_client.eth_call_create_lbp.assert_called_once()
        self.mock_nethermind_client.execute_create_lbp.assert_called_once()

        # Check that the instance was added to pending instances for completion check
        self.assertIn(instance_address.lower(), self.processor.pending_instances)
        self.assertEqual(self.processor.pending_instances[instance_address.lower()]['type'], 'check_completion')
        self.assertEqual(self.processor.stats['lbp_created'], 1)

    def test_process_instance_lbp_already_created(self):
        """Test processing with LBPAlreadyCreated error."""
        # Setup
        instance_address = "0x1234"
        backer_address = "0xbacker"

        # Mock method responses
        self.mock_nethermind_client.check_completed_event.return_value = False

        # eth_call raises OrderAlreadySettled
        self.mock_nethermind_client.eth_call_reset_cowswap_order.side_effect = ContractLogicError(
            f"execution reverted: {self.processor.ERROR_ORDER_ALREADY_SETTLED}"
        )

        # eth_call for createLBP raises LBPAlreadyCreated
        self.mock_nethermind_client.eth_call_create_lbp.side_effect = ContractLogicError(
            f"execution reverted: {self.processor.ERROR_LBP_ALREADY_CREATED}"
        )

        # Call the method
        result = self.processor.process_instance(instance_address, backer_address)

        # Assertions
        self.assertTrue(result)
        self.mock_nethermind_client.eth_call_reset_cowswap_order.assert_called_once()
        self.mock_nethermind_client.eth_call_create_lbp.assert_called_once()

        # Should be scheduled for completion check
        self.assertIn(instance_address.lower(), self.processor.pending_instances)
        self.assertEqual(self.processor.pending_instances[instance_address.lower()]['type'], 'check_completion')

    def test_process_instance_insufficient_balance(self):
        """Test processing with BackingAssetBalanceInsufficient error."""
        # Setup
        instance_address = "0x1234"
        backer_address = "0xbacker"

        # Mock method responses
        self.mock_nethermind_client.check_completed_event.return_value = False

        # eth_call raises OrderAlreadySettled
        self.mock_nethermind_client.eth_call_reset_cowswap_order.side_effect = ContractLogicError(
            f"execution reverted: {self.processor.ERROR_ORDER_ALREADY_SETTLED}"
        )

        # eth_call for createLBP raises BackingAssetBalanceInsufficient
        self.mock_nethermind_client.eth_call_create_lbp.side_effect = ContractLogicError(
            f"execution reverted: {self.processor.ERROR_BACKING_ASSET_INSUFFICIENT}"
        )

        # Call the method
        result = self.processor.process_instance(instance_address, backer_address)

        # Assertions
        self.assertFalse(result)
        self.mock_nethermind_client.eth_call_reset_cowswap_order.assert_called_once()
        self.mock_nethermind_client.eth_call_create_lbp.assert_called_once()

        # Should be added to problem instances
        self.assertIn(instance_address.lower(), self.processor.problem_instances)
        self.mock_slack_notifier.notify_insufficient_balance.assert_called_once()

    def test_process_instance_order_uid_same(self):
        """Test processing with OrderUidIsTheSame error."""
        # Setup
        instance_address = "0x1234"
        backer_address = "0xbacker"

        # Mock method responses
        self.mock_nethermind_client.check_completed_event.return_value = False

        # eth_call raises OrderUidIsTheSame
        self.mock_nethermind_client.eth_call_reset_cowswap_order.side_effect = ContractLogicError(
            f"execution reverted: {self.processor.ERROR_ORDER_UID_SAME}"
        )

        # Mock time.time() to return a predictable value
        with patch('time.time', return_value=1000.0):
            # Call the method
            result = self.processor.process_instance(instance_address, backer_address)

        # Assertions
        self.assertTrue(result)
        self.mock_nethermind_client.eth_call_reset_cowswap_order.assert_called_once()

        # Should be scheduled for reset retry
        self.assertIn(instance_address.lower(), self.processor.pending_instances)
        self.assertEqual(self.processor.pending_instances[instance_address.lower()]['type'], 'reset_retry')
        self.assertEqual(self.processor.pending_instances[instance_address.lower()]['retry_count'], 1)
        self.assertEqual(self.processor.pending_instances[instance_address.lower()]['next_retry_time'], 1000.0 + 180)  # 3 minutes

    def test_process_pending_check_completion(self):
        """Test processing a pending completion check."""
        # Setup
        instance_address = "0x1234"
        backer_address = "0xbacker"

        # Add a pending instance for completion check
        self.processor.pending_instances[instance_address] = {
            'backer': backer_address,
            'retry_count': 0,
            'last_attempt': time.time() - 10,  # 10 seconds ago
            'type': 'check_completion',
            'next_check_block': 90,  # Lower than current block (100)
            'timestamp': time.time() - 10
        }

        # Mock completed event check to return True
        self.mock_nethermind_client.check_completed_event.return_value = True

        # Run process_pending_instances
        self.processor.process_pending_instances()

        # Assertions
        self.mock_nethermind_client.check_completed_event.assert_called_once()

        # Instance should be removed from pending instances
        self.assertNotIn(instance_address, self.processor.pending_instances)

        # Backer should be added to completed backers
        self.assertIn(backer_address, self.processor._completed_backers)

    def test_process_pending_reset_retry(self):
        """Test processing a pending reset retry."""
        # Setup
        instance_address = "0x1234"
        backer_address = "0xbacker"
        current_time = time.time()

        # Add a pending instance for reset retry
        self.processor.pending_instances[instance_address] = {
            'backer': backer_address,
            'retry_count': 1,
            'last_attempt': current_time - 10,  # 10 seconds ago
            'type': 'reset_retry',
            'next_retry_time': current_time - 5,  # 5 seconds ago (ready for retry)
            'timestamp': current_time - 10
        }

        # Mock successful eth_call and execution
        self.mock_nethermind_client.eth_call_reset_cowswap_order.return_value = None
        self.mock_nethermind_client.execute_reset_cowswap_order.return_value = {
            "transactionHash": "0xhash"
        }

        # Run process_pending_instances
        self.processor.process_pending_instances()

        # Assertions
        self.mock_nethermind_client.eth_call_reset_cowswap_order.assert_called_once()
        self.mock_nethermind_client.execute_reset_cowswap_order.assert_called_once()

        # Instance should be scheduled for completion check
        self.assertIn(instance_address, self.processor.pending_instances)
        self.assertEqual(self.processor.pending_instances[instance_address]['type'], 'check_completion')
        self.assertEqual(self.processor.stats['reset_succeeded'], 1)

    def test_process_pending_reset_retry_order_already_settled(self):
        """Test processing a pending reset retry with OrderAlreadySettled error."""
        # Setup
        instance_address = "0x1234"
        backer_address = "0xbacker"
        current_time = time.time()

        # Add a pending instance for reset retry
        self.processor.pending_instances[instance_address] = {
            'backer': backer_address,
            'retry_count': 1,
            'last_attempt': current_time - 10,  # 10 seconds ago
            'type': 'reset_retry',
            'next_retry_time': current_time - 5,  # 5 seconds ago (ready for retry)
            'timestamp': current_time - 10
        }

        # Mock eth_call to raise OrderAlreadySettled
        self.mock_nethermind_client.eth_call_reset_cowswap_order.side_effect = ContractLogicError(
            f"execution reverted: {self.processor.ERROR_ORDER_ALREADY_SETTLED}"
        )

        # Mock successful LBP creation
        self.mock_nethermind_client.eth_call_create_lbp.return_value = None
        self.mock_nethermind_client.execute_create_lbp.return_value = {
            "transactionHash": "0xhash"
        }

        # Run process_pending_instances
        self.processor.process_pending_instances()

        # Assertions
        self.mock_nethermind_client.validate_reset_cowswap_order.assert_called_once()
        self.mock_nethermind_client.validate_create_lbp.assert_called_once()
        self.mock_nethermind_client.execute_create_lbp.assert_called_once()

        # Instance should be removed from pending instances
        self.assertNotIn(instance_address, self.processor.pending_instances)

    def test_process_pending_reset_retry_order_uid_same(self):
        """Test processing a pending reset retry with OrderUidIsTheSame error."""
        # Setup
        instance_address = "0x1234"
        backer_address = "0xbacker"
        current_time = time.time()

        # Add a pending instance for reset retry
        self.processor.pending_instances[instance_address] = {
            'backer': backer_address,
            'retry_count': 1,
            'last_attempt': current_time - 10,  # 10 seconds ago
            'type': 'reset_retry',
            'next_retry_time': current_time - 5,  # 5 seconds ago (ready for retry)
            'timestamp': current_time - 10
        }

        # Mock eth_call to raise OrderUidIsTheSame
        self.mock_nethermind_client.eth_call_reset_cowswap_order.side_effect = ContractLogicError(
            f"execution reverted: {self.processor.ERROR_ORDER_UID_SAME}"
        )

        # Run process_pending_instances
        with patch('time.time', return_value=1000.0):
            self.processor.process_pending_instances()

        # Assertions
        self.mock_nethermind_client.eth_call_reset_cowswap_order.assert_called_once()

        # Should be scheduled for another retry with increased wait time
        self.assertIn(instance_address, self.processor.pending_instances)
        self.assertEqual(self.processor.pending_instances[instance_address]['type'], 'reset_retry')
        self.assertEqual(self.processor.pending_instances[instance_address]['retry_count'], 2)

        # Wait time should now be 6 minutes (3 * (1+1))
        self.assertEqual(self.processor.pending_instances[instance_address]['next_retry_time'], 1000.0 + 360)

    def test_process_pending_max_retries_exceeded(self):
        """Test handling max retries exceeded."""
        # Setup
        instance_address = "0x1234"
        backer_address = "0xbacker"
        current_time = time.time()

        # Add a pending instance that exceeded max retries
        self.processor.pending_instances[instance_address] = {
            'backer': backer_address,
            'retry_count': self.processor.max_retries,  # Already at max retries
            'last_attempt': current_time - 10,
            'type': 'reset_retry',
            'next_retry_time': current_time - 5,
            'error': 'Previous error',
            'timestamp': current_time - 10
        }

        # Run process_pending_instances
        self.processor.process_pending_instances()

        # Assertions
        # Should be moved to problem instances
        self.assertNotIn(instance_address, self.processor.pending_instances)
        self.assertIn(instance_address, self.processor.problem_instances)
        self.assertIn('Exceeded max retries', self.processor.problem_instances[instance_address]['error'])

    def test_get_completed_backers(self):
        """Test getting and clearing completed backers."""
        # Add some completed backers
        self.processor._completed_backers = {"0xbacker1", "0xbacker2"}

        # Get completed backers
        completed = self.processor.get_completed_backers()

        # Assertions
        self.assertEqual(completed, {"0xbacker1", "0xbacker2"})
        self.assertEqual(len(self.processor._completed_backers), 0)  # Should be cleared

    def test_get_stats(self):
        """Test getting processor statistics."""
        # Set up some statistics
        self.processor.stats = {
            'lbp_created': 5,
            'lbp_failed': 2,
            'reset_succeeded': 8,
            'reset_failed': 1,
            'indexer_issues': 3
        }
        self.processor.pending_instances = {"0x1": {}, "0x2": {}}
        self.processor.problem_instances = {"0x3": {}}

        # Get stats
        stats = self.processor.get_stats()

        # Assertions
        self.assertEqual(stats['lbp_created'], 5)
        self.assertEqual(stats['lbp_failed'], 2)
        self.assertEqual(stats['reset_succeeded'], 8)
        self.assertEqual(stats['reset_failed'], 1)
        self.assertEqual(stats['indexer_issues'], 3)
        self.assertEqual(stats['pending_instances'], 2)
        self.assertEqual(stats['problem_instances'], 1)

    def test_reset(self):
        """Test resetting the processor state."""
        # Set up some state
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

        # Reset the processor
        self.processor.reset()

        # Assertions
        self.assertEqual(len(self.processor.pending_instances), 0)
        self.assertEqual(len(self.processor.problem_instances), 0)
        self.assertEqual(len(self.processor._completed_backers), 0)

        # Stats should be reset
        self.assertEqual(self.processor.stats['lbp_created'], 0)
        self.assertEqual(self.processor.stats['lbp_failed'], 0)
        self.assertEqual(self.processor.stats['reset_succeeded'], 0)
        self.assertEqual(self.processor.stats['reset_failed'], 0)
        self.assertEqual(self.processor.stats['indexer_issues'], 0)


if __name__ == "__main__":
    unittest.main()
