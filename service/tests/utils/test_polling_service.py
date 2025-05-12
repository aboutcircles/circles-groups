import unittest
from unittest.mock import MagicMock, patch
import time
from datetime import datetime, timedelta
from web3 import Web3
from src.utils.polling_service import PollingService
from src.algorithm.trust_management import TrustManagementAlgorithm
from src.clients.nethermind import NethermindClient
from src.utils.slack_notifier import SlackNotifier


class TestPollingService(unittest.TestCase):
    def setUp(self):
        """Set up the PollingService with mocked dependencies."""
        # Mock dependencies
        self.mock_trust_algorithm = MagicMock(spec=TrustManagementAlgorithm)
        self.mock_nethermind_client = MagicMock(spec=NethermindClient)
        self.mock_slack_notifier = MagicMock(spec=SlackNotifier)

# Mock web3
        self.mock_web3 = MagicMock()
        self.mock_web3.is_connected.return_value = True
        self.mock_web3.eth.block_number = 1000
        self.mock_nethermind_client.web3 = self.mock_web3

# Create polling service
        self.polling_service = PollingService(
            trust_algorithm=self.mock_trust_algorithm,
            nethermind_client=self.mock_nethermind_client,
            poll_interval=1,  # Fast polling for tests (integer)
            health_check_interval=1,  # Fast health check for tests (integer)
            slack_notifier=self.mock_slack_notifier
        )

    def test_initialization(self):
        """Test initialization of the polling service."""
        self.assertEqual(self.polling_service.trust_algorithm, self.mock_trust_algorithm)
        self.assertEqual(self.polling_service.nethermind_client, self.mock_nethermind_client)
        self.assertEqual(self.polling_service.web3, self.mock_web3)
        self.assertEqual(self.polling_service.poll_interval, 0.1)
        self.assertEqual(self.polling_service.health_check_interval, 0.5)
        self.assertEqual(self.polling_service.slack_notifier, self.mock_slack_notifier)
        self.assertFalse(self.polling_service.running)
        self.assertIsNone(self.polling_service.start_time)

    def test_initialization_web3_not_connected(self):
        """Test initialization when web3 is not connected."""
        # Mock web3 to not be connected
        self.mock_web3.is_connected.return_value = False

        # Should raise ConnectionError
        with self.assertRaises(ConnectionError):
            PollingService(
                trust_algorithm=self.mock_trust_algorithm,
                nethermind_client=self.mock_nethermind_client
            )

    def test_start_stop(self):
        """Test starting and stopping the polling service."""
        # Patch the _run_polling_loop method to prevent actual polling
        with patch.object(self.polling_service, '_run_polling_loop') as mock_run:
            # Start the service
            self.polling_service.start()

            # Assertions
            self.assertTrue(self.polling_service.running)
            self.assertIsNotNone(self.polling_service.start_time)
            self.mock_slack_notifier.notify_service_start.assert_called_once()
            mock_run.assert_called_once()

            # Stop the service
            self.polling_service.stop()

            # Assertions
            self.assertFalse(self.polling_service.running)

    def test_run_polling_loop(self):
        """Test the polling loop with simulated blocks."""
        # Set up mocks
        self.mock_web3.eth.block_number = 1000

        # Start running flag
        self.polling_service.running = True

        # Run the polling loop in a separate thread
        import threading
        thread = threading.Thread(target=self.polling_service._run_polling_loop)
        thread.daemon = True
        thread.start()

        # Wait a bit
        time.sleep(0.2)

        # Simulate a new block
        self.mock_web3.eth.block_number = 1001

        # Wait for the loop to process the new block
        time.sleep(0.2)

        # Stop the service
        self.polling_service.running = False
        thread.join(timeout=1.0)

        # Assertions
        self.mock_trust_algorithm.run.assert_called()

        # Should be called at least once, could be multiple times due to timing
        self.assertGreaterEqual(self.mock_trust_algorithm.run.call_count, 1)

    def test_health_check(self):
        """Test the health check functionality."""
        # Set up the start time for uptime calculation
        self.polling_service.start_time = datetime.now() - timedelta(hours=1)

        # Mock the check_health methods
        self.mock_trust_algorithm.check_health.return_value = {"status": "healthy"}
        self.mock_nethermind_client.check_health.return_value = {"block_lag": 5}

        # Send health check
        self.polling_service._send_health_check()

        # Assertions
        self.mock_trust_algorithm.check_health.assert_called_once()
        self.mock_nethermind_client.check_health.assert_called_once()
        self.mock_slack_notifier.notify_health_check.assert_called_once()

        # Check that uptime was added to the health data
        health_data = self.mock_slack_notifier.notify_health_check.call_args[0][0]
        self.assertIn('uptime', health_data)

        # No indexer warning should be added for small block lag
        self.assertNotIn('indexer_status', health_data)

    def test_health_check_indexer_warning(self):
        """Test health check with indexer warning."""
        # Set up the start time for uptime calculation
        self.polling_service.start_time = datetime.now() - timedelta(hours=1)

        # Mock the check_health methods with a large block lag
        self.mock_trust_algorithm.check_health.return_value = {"status": "healthy"}
        self.mock_nethermind_client.check_health.return_value = {"block_lag": 25}  # > 20, should trigger warning

        # Send health check
        self.polling_service._send_health_check()

        # Assertions
        health_data = self.mock_slack_notifier.notify_health_check.call_args[0][0]
        self.assertIn('indexer_status', health_data)
        self.assertTrue(health_data['indexer_status'].startswith('WARNING'))

    def test_no_slack_notifier(self):
        """Test behavior when no slack notifier is provided."""
        # Create a polling service without slack notifier
        polling_service = PollingService(
            trust_algorithm=self.mock_trust_algorithm,
            nethermind_client=self.mock_nethermind_client,
            slack_notifier=None
        )

        # These should not raise errors
        polling_service._send_health_check()  # Should do nothing

        # Patch the _run_polling_loop method to prevent actual polling
        with patch.object(polling_service, '_run_polling_loop'):
            polling_service.start()  # Should start without notifications
            polling_service.stop()  # Should stop without notifications

    def test_polling_loop_error_handling(self):
        """Test error handling in the polling loop."""
        # Set up mocks to raise exceptions
        self.mock_web3.eth.block_number = 1000
        self.mock_trust_algorithm.run.side_effect = Exception("Test error")

        # Start running flag
        self.polling_service.running = True

        # Patch time.sleep to avoid waiting
        with patch('time.sleep') as mock_sleep:
            # Run one iteration of the loop
            try:
                self.polling_service._run_polling_loop()
            except Exception:
                # The exception should be caught within the method
                self.fail("Exception should be caught in _run_polling_loop")

            # Assertions
            self.mock_trust_algorithm.run.assert_called_once()
            self.mock_slack_notifier.send_message.assert_called_once()
            message = self.mock_slack_notifier.send_message.call_args[0][0]
            self.assertIn("Error in polling loop", message)
            self.assertIn("Test error", message)


if __name__ == "__main__":
    unittest.main()
