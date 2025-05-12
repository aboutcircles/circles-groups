import unittest
from unittest.mock import MagicMock, patch
import json
from datetime import datetime
from src.utils.slack_notifier import SlackNotifier


class TestSlackNotifier(unittest.TestCase):
    def setUp(self):
        """Set up SlackNotifier for testing."""
        self.webhook_url = "https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXX"
        self.channel = "#test-channel"
        self.username = "Test Bot"

        self.notifier = SlackNotifier(
            webhook_url=self.webhook_url,
            channel=self.channel,
            username=self.username
        )

        # Patch requests.post
        self.post_patcher = patch('src.utils.slack_notifier.requests.post')
        self.mock_post = self.post_patcher.start()
        self.addCleanup(self.post_patcher.stop)

        # Configure mock response
        self.mock_response = MagicMock()
        self.mock_response.status_code = 200
        self.mock_post.return_value = self.mock_response

    def test_initialization(self):
        """Test initialization of the notifier."""
        self.assertEqual(self.notifier.webhook_url, self.webhook_url)
        self.assertEqual(self.notifier.channel, self.channel)
        self.assertEqual(self.notifier.username, self.username)
        self.assertTrue(self.notifier.enabled)

        # Test disabled notifier
        disabled_notifier = SlackNotifier(webhook_url="", channel="#test")
        self.assertFalse(disabled_notifier.enabled)

    def test_send_message_basic(self):
        """Test sending a basic message."""
        result = self.notifier.send_message("Test message")

        # Assertions
        self.assertTrue(result)
        self.mock_post.assert_called_once()

        # Check the payload
        call_args = self.mock_post.call_args
        url, kwargs = call_args[0][0], call_args[1]
        self.assertEqual(url, self.webhook_url)

        # Check the headers
        self.assertEqual(kwargs['headers'], {"Content-Type": "application/json"})

        # Parse the payload
        payload = json.loads(kwargs['data'])
        self.assertEqual(payload['channel'], self.channel)
        self.assertEqual(payload['username'], self.username)
        self.assertEqual(payload['text'], "Test message")

    def test_send_message_with_attachments(self):
        """Test sending a message with attachments."""
        attachments = [
            {
                "fallback": "Attachment fallback",
                "color": "#36a64f",
                "title": "Attachment Title",
                "text": "Attachment text"
            }
        ]

        result = self.notifier.send_message("Message with attachment", attachments=attachments)

        # Assertions
        self.assertTrue(result)

        # Parse the payload
        payload = json.loads(self.mock_post.call_args[1]['data'])
        self.assertIn('attachments', payload)
        self.assertEqual(len(payload['attachments']), 1)
        self.assertEqual(payload['attachments'][0]['title'], "Attachment Title")

    def test_send_message_with_blocks(self):
        """Test sending a message with blocks."""
        blocks = [
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": "Block text"
                }
            }
        ]

        result = self.notifier.send_message("Message with blocks", blocks=blocks)

        # Assertions
        self.assertTrue(result)

        # Parse the payload
        payload = json.loads(self.mock_post.call_args[1]['data'])
        self.assertIn('blocks', payload)
        self.assertEqual(len(payload['blocks']), 1)
        self.assertEqual(payload['blocks'][0]['type'], "section")

    def test_send_message_error(self):
        """Test error handling when sending a message."""
        # Make post raise an exception
        self.mock_post.side_effect = Exception("Test error")

        result = self.notifier.send_message("Test message")

        # Assertions
        self.assertFalse(result)

    def test_send_message_response_error(self):
        """Test handling an error response when sending a message."""
        # Mock a 400 response
        self.mock_response.status_code = 400
        self.mock_response.raise_for_status.side_effect = Exception("Bad Request")

        result = self.notifier.send_message("Test message")

        # Assertions
        self.assertFalse(result)

    def test_disabled_notifier(self):
        """Test that disabled notifier doesn't send messages."""
        disabled_notifier = SlackNotifier(webhook_url="", channel="#test")

        result = disabled_notifier.send_message("Test message")

        # Assertions
        self.assertFalse(result)
        self.mock_post.assert_not_called()

    def test_service_notifications(self):
        """Test service start/stop notifications."""
        methods = [
            ('notify_service_start', "🟢 Circles Trust Management service has started."),
            ('notify_service_stop', "🔴 Circles Trust Management service has stopped.")
        ]

        for method_name, expected_text in methods:
            # Call the method
            method = getattr(self.notifier, method_name)
            result = method()

            # Assertions
            self.assertTrue(result)

            # Get the last call
            last_call = self.mock_post.call_args
            payload = json.loads(last_call[1]['data'])
            self.assertEqual(payload['text'], expected_text)

    def test_order_uid_same_notification(self):
        """Test OrderUidIsTheSame notification."""
        with patch('src.utils.slack_notifier.time.time', return_value=1000.0):
            with patch('src.utils.slack_notifier.datetime') as mock_datetime:
                # Mock datetime.now and datetime.fromtimestamp
                mock_now = MagicMock()
                mock_now.strftime.return_value = "2023-01-01 12:00:00"
                mock_datetime.now.return_value = mock_now

                mock_retry_time = MagicMock()
                mock_retry_time.strftime.return_value = "2023-01-01 12:05:00"
                mock_datetime.fromtimestamp.return_value = mock_retry_time

                # Call the method
                result = self.notifier.notify_order_uid_same(
                    instance_address="0xinstance",
                    backer_address="0xbacker",
                    retry_count=2,
                    next_retry_time=1300.0  # 5 minutes from now
                )

                # Assertions
                self.assertTrue(result)

                # Get the payload
                payload = json.loads(self.mock_post.call_args[1]['data'])
                self.assertIn("Cowswap Order UID Same", payload['text'])
                self.assertIn("blocks", payload)
                self.assertGreater(len(payload['blocks']), 0)

                # Check specific content
                block_text = json.dumps(payload['blocks'])
                self.assertIn("0xinstance", block_text)
                self.assertIn("0xbacker", block_text)
                self.assertIn("OrderUidIsTheSame", block_text)
                self.assertIn("2", block_text)  # retry count
                self.assertIn("5 min", block_text)  # minutes until retry

    def test_specialized_notifications(self):
        """Test other specialized notifications."""
        methods = [
            ('notify_order_uid_resolved', ["0xinstance", "0xbacker", 3]),
            ('notify_lbp_created', ["0xinstance", "0xbacker"]),
            ('notify_lbp_creation_failed', ["0xinstance", "Error message"]),
            ('notify_insufficient_balance', ["0xinstance", "0xbacker"]),
            ('notify_indexer_issue', ["Indexer issue message"]),
        ]

        for method_name, args in methods:
            # Reset mock
            self.mock_post.reset_mock()

            # Call the method
            method = getattr(self.notifier, method_name)
            result = method(*args)

            # Assertions
            self.assertTrue(result)
            self.mock_post.assert_called_once()

            # Get the payload
            payload = json.loads(self.mock_post.call_args[1]['data'])
            if method_name == 'notify_order_uid_resolved':
                self.assertIn("OrderUidIsTheSame resolved", payload['text'])
            elif method_name == 'notify_lbp_created':
                self.assertIn("Successfully created LBP", payload['text'])
            elif method_name == 'notify_lbp_creation_failed':
                self.assertIn("Failed to create LBP", payload['text'])
            elif method_name == 'notify_insufficient_balance':
                self.assertIn("Manual intervention required", payload['text'])
            elif method_name == 'notify_indexer_issue':
                self.assertIn("Potential indexer issue detected", payload['text'])

    def test_health_check_notification(self):
        """Test health check notification."""
        stats = {
            'current_block': 1000,
            'uptime': '1:00:00',
            'lbp_created': 5,
            'backers_trusted': 10,
            'pending_instances': 2,
            'problem_instances': 1
        }

        result = self.notifier.notify_health_check(stats)

        # Assertions
        self.assertTrue(result)

        # Get the payload
        payload = json.loads(self.mock_post.call_args[1]['data'])
        self.assertIn("Trust Management Service Health Report", payload['text'])
        self.assertIn("blocks", payload)

        # Check that stats are included in the blocks
        block_text = json.dumps(payload['blocks'])
        for key, value in stats.items():
            self.assertIn(str(value), block_text)


if __name__ == "__main__":
    unittest.main()
