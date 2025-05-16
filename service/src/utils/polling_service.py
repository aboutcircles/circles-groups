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
        slack_notifier: Optional[SlackNotifier] = None,
        grace_period_days: float = 1.0  # Grace period in days
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

        # Calculate grace period in blocks (assuming ~12 second blocks on Gnosis Chain)
        self.MAX_GRACE_PERIOD_BLOCKS = int(grace_period_days * 24 * 60 * 60 / 12)
        logger.info(f"Grace period set to {grace_period_days} days ({self.MAX_GRACE_PERIOD_BLOCKS} blocks)")

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

    def _ensure_connected(self):
        """Ensure RPC connection is active."""
        if self.web3.is_connected():
            return True

        # Try to reconnect
        logger.warning("RPC connection lost. Attempting to reconnect...")
        retry_count = 0
        max_retries = 5

        while not self.web3.is_connected() and retry_count < max_retries:
            retry_count += 1
            logger.info(f"Reconnection attempt {retry_count}/{max_retries}")

            try:
                # Re-initialize web3 connection
                self.web3 = Web3(Web3.HTTPProvider(self.nethermind_client.rpc_url))
                # Update reference in nethermind client
                self.nethermind_client.web3 = self.web3

                if self.web3.is_connected():
                    logger.info("Successfully reconnected to RPC")
                    return True
            except Exception as e:
                logger.error(f"Reconnection attempt failed: {e}")

            # Wait before retrying (with backoff)
            time.sleep(5 * (2 ** min(retry_count - 1, 4)))  # Capped exponential backoff

        logger.error("Failed to reconnect to RPC after multiple attempts")
        return False

    def _run_polling_loop(self):
        """Main polling loop with improved sync and grace period recovery."""
        last_successful_run = time.time()

        while self.running:
            try:
                # Ensure RPC connection
                if not self._ensure_connected():
                    logger.warning("RPC connection unavailable, waiting to retry...")
                    time.sleep(10)  # Wait before retrying
                    continue

                # Get current block number
                current_block_number = self.web3.eth.block_number
                last_processed_block = self.trust_algorithm._last_processed_block

                # Calculate blocks to be processed
                blocks_behind = current_block_number - last_processed_block

                # Check if we're significantly behind (potential RPC downtime)
                if blocks_behind > 20:  # Arbitrary threshold to detect significant lag
                    logger.warning(
                        f"Service is {blocks_behind} blocks behind current chain state. "
                        f"This may indicate prior RPC connectivity issues."
                    )

                    # Check if we're within grace period capacity
                    if blocks_behind <= self.MAX_GRACE_PERIOD_BLOCKS:
                        logger.info(f"Processing backlog within grace period: {blocks_behind} blocks")

                        # Optional: Process in smaller batches if significantly behind
                        if blocks_behind > 100:
                            logger.info("Processing backlog in batches to avoid timeout")

                            # Process all missed blocks by triggering run for each batch
                            self.trust_algorithm.run()

                            # Allow a small pause between runs to avoid overwhelming the node
                            time.sleep(1)
                        else:
                            # Standard processing for smaller backlogs
                            logger.info(f"Processing blocks {last_processed_block+1} to {current_block_number}")
                            self.trust_algorithm.run()
                    else:
                        # Beyond grace period capacity, requires intervention
                        logger.critical(
                            f"Service is too far behind ({blocks_behind} blocks, max grace: {self.MAX_GRACE_PERIOD_BLOCKS}). "
                            f"Manual intervention may be required."
                        )
                        if self.slack_notifier:
                            self.slack_notifier.send_message(
                                f"🚨 CRITICAL: Service is {blocks_behind} blocks behind (more than 1 day). "
                                f"Manual intervention required to prevent missing events."
                            )

                        # Option 1: Skip forward and log the action - better for non-essential services
                        # safe_start_block = current_block_number - self.MAX_GRACE_PERIOD_BLOCKS // 2
                        # logger.warning(f"Skipping forward to block {safe_start_block} due to excessive lag")
                        # self.trust_algorithm._last_processed_block = safe_start_block

                        # Option 2: Continue processing from where we are - may take a long time to catch up
                        logger.warning("Attempting to process large backlog - this may take a long time")
                        self.trust_algorithm.run()

                        # Option 3: Fail loudly - better for financial applications
                        # raise RuntimeError(
                        #     f"Service backlog exceeds grace period: {blocks_behind} blocks behind. "
                        #     f"Manual recovery required."
                        # )

                # Standard case - processing current blocks
                elif current_block_number > last_processed_block:
                    logger.info(f"Processing blocks {last_processed_block+1} to {current_block_number}")
                    self.trust_algorithm.run()

                # Update last successful run timestamp
                last_successful_run = time.time()

                # Health check
                health_check_interval_passed = (datetime.now() - self.last_health_check).total_seconds() > self.health_check_interval
                if health_check_interval_passed:
                    self._send_health_check()
                    self.last_health_check = datetime.now()

                # Sleep before next check
                time.sleep(self.poll_interval)

            except Exception as e:
                logger.error(f"Error in polling loop: {e}", exc_info=True)

                # Calculate downtime
                downtime = time.time() - last_successful_run

                # Alert if downtime is significant
                if downtime > 300 and self.slack_notifier:  # 5 minutes
                    self.slack_notifier.send_message(
                        f"⚠️ Service experiencing issues for {int(downtime/60)} minutes. Error: {str(e)}"
                    )

                # Wait before retrying
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
