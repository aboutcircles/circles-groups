import time
import logging
from datetime import datetime, timedelta
from typing import Optional
from web3 import Web3
from algorithm.trust_management import TrustManagementAlgorithm
from clients.nethermind import NethermindClient
from utils.slack_notifier import SlackNotifier

logger = logging.getLogger(__name__)

class PollingService:
    """Service to poll for new blocks and trigger trust management algorithm."""

    def __init__(
        self,
        trust_algorithm: TrustManagementAlgorithm,
        nethermind_client: NethermindClient,
        poll_interval: int = 5,  # seconds
        health_check_interval: int = 3600,  # 1 hour
        slack_notifier: Optional[SlackNotifier] = None
    ):
        self.trust_algorithm = trust_algorithm
        self.nethermind_client = nethermind_client
        self.web3 = nethermind_client.web3
        self.poll_interval = poll_interval
        self.health_check_interval = health_check_interval
        self.slack_notifier = slack_notifier
        self.last_health_check = datetime.now()
        self.running = False
        self.start_time = None

        if not self.web3.is_connected():
            raise ConnectionError("Failed to connect to the blockchain")

        logger.info(f"Initialized PollingService with poll interval of {poll_interval} seconds")

    def start(self):
        """Start the polling service."""
        self.running = True
        self.start_time = datetime.now()
        logger.info("Starting PollingService...")

        # if self.slack_notifier:
        #     self.slack_notifier.notify_service_start()

        try:
            self._run_polling_loop()
        except KeyboardInterrupt:
            logger.info("Polling service stopped by user")
        except Exception as e:
            logger.error(f"Polling service crashed: {e}", exc_info=True)
            if self.slack_notifier:
                self.slack_notifier.send_message(f"🚨 Polling service crashed: {str(e)}")
        finally:
            self.running = False
            if self.slack_notifier:
                self.slack_notifier.notify_service_stop()

    def stop(self):
        """Stop the polling service."""
        logger.info("Stopping PollingService...")
        self.running = False

    def _run_polling_loop(self):
        """Main polling loop."""
        latest_block_number = None

        while self.running:
            try:
                current_block_number = self.web3.eth.block_number

                if current_block_number != latest_block_number:
                    latest_block_number = current_block_number
                    logger.info(f"Processing new block: {latest_block_number}")
                    self.trust_algorithm.run()

                # Send health check if interval has passed
                if (datetime.now() - self.last_health_check).total_seconds() > self.health_check_interval:
                    self._send_health_check()
                    self.last_health_check = datetime.now()

                time.sleep(self.poll_interval)
            except Exception as e:
                logger.error(f"Error in polling loop: {e}", exc_info=True)
                time.sleep(self.poll_interval)

    def _send_health_check(self):
        """Send a health check notification."""
        if not self.slack_notifier:
            return

        if self.start_time is None:
            uptime_str = "unknown"
        else:
            uptime = datetime.now() - self.start_time
            uptime_str = str(uptime).split('.')[0]  # Remove microseconds

        # Get health data from trust algorithm
        health_data = self.trust_algorithm.check_health()

        # Add uptime
        health_data['uptime'] = uptime_str

        # Check RPC and indexer health
        nethermind_health = self.nethermind_client.check_health()
        block_lag = nethermind_health.get('block_lag', 0)

        # Format health message
        if block_lag > 20:
            health_data['indexer_status'] = f"WARNING: Indexer is {block_lag} blocks behind"

        # Send notification
        self.slack_notifier.notify_health_check(health_data)
        logger.info(f"Health check sent. Uptime: {uptime_str}")
