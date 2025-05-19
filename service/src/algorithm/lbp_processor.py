import logging
import time
from typing import Dict, Set, Optional
from web3 import Web3
from web3.exceptions import ContractLogicError
from clients.nethermind import NethermindClient
from utils.slack_notifier import SlackNotifier

logger = logging.getLogger(__name__)

class LBPProcessor:
    """Handles the processing of backing instances that need LBP creation."""

    def __init__(
        self,
        nethermind_client: NethermindClient,
        private_key: str,
        slack_notifier: Optional[SlackNotifier] = None,
        retry_interval: int = 300,  # 5 minutes
        max_retries: int = 10
    ):
        self.client = nethermind_client
        self.private_key = private_key
        self.slack = slack_notifier
        self.web3 = nethermind_client.web3
        self.retry_interval = retry_interval
        self.max_retries = max_retries

        # State tracking
        self.pending_instances = {}
        self.problem_instances = {}
        self._completed_backers = set()

        # Statistics
        self.stats = {
            'lbp_created': 0,
            'lbp_failed': 0,
            'reset_succeeded': 0,
            'reset_failed': 0,
            'indexer_issues': 0
        }

    def process_instance(self, instance: str, backer: str) -> bool:
        """
        Process a backing instance that needs LBP creation.
        Returns True if the instance was completed or is being processed.
        """
        instance = instance.lower()
        backer = backer.lower()

        # Skip if already being processed or has problems
        if instance in self.pending_instances or instance in self.problem_instances:
            return True

        # Check if already completed
        if self.client.check_completed_event(instance, backer):
            logger.info(f"✅ Found CirclesBackingCompleted event for {instance}")
            self._add_completed_backer(backer)
            return True

        try:
            # Validate resetCowswapOrder first
            validation_result = self.client.validate_reset_cowswap_order(
                instance_address=instance,
                private_key=self.private_key
            )

            if validation_result["status"] == "valid":
                # Validation successful, execute the transaction
                try:
                    tx_receipt = self.client.execute_cowswap_order(
                        instance_address=instance,
                        private_key=self.private_key
                    )

                    logger.info(f"✅ Successfully reset Cowswap order for {instance}")
                    self.stats['reset_succeeded'] += 1
                    self._schedule_completion_check(instance, backer, tx_receipt.get('tx_hash'))
                    self._notify(f"✅ Successfully reset Cowswap order for {instance}")

                    return True

                except ContractLogicError as e:
                    logger.error(f"❌ Error executing cowswap order: {str(e)}")
                    self._add_problem_instance(instance, backer, f"Execution error: {str(e)}")
                    self._notify(f"❌ Error executing cowswap order: {str(e)}")
                    return False

            elif validation_result["status"] == "order_already_settled":
                logger.info(f"⚠️ Order already settled for {instance}, trying createLBP")
                return self._handle_create_lbp(instance, backer)

            elif validation_result["status"] == "order_uid_same":
                logger.warning(f"⏱️ OrderUidIsTheSame for {instance} - scheduling retry")
                self._schedule_reset_retry(instance, backer)
                self._notify(f"⏱️ OrderUID is the same for {instance}, scheduled retry")
                return True

            else:
                error_message = validation_result.get("message", "Unknown error")
                logger.error(f"❌ Contract error in resetCowswapOrder: {error_message}")
                self._add_problem_instance(instance, backer, f"Contract error: {error_message}")
                self._notify(f"❌ resetCowswapOrder error: {error_message}")
                return False

        except ContractLogicError as e:
            logger.exception(f"🚨 Unhandled error processing instance {instance}: {e}")
            self._add_problem_instance(instance, backer, str(e))
            self._notify(f"🚨 Unhandled error processing instance {instance}: {e}")
            return False

    def _handle_create_lbp(self, instance: str, backer: str) -> bool:
        """Handle LBP creation after OrderAlreadySettled error."""
        try:
            # Validate createLBP first
            validation_result = self.client.validate_create_lbp(
                instance_address=instance,
                private_key=self.private_key
            )

            if validation_result["status"] == "valid":
                # Validation successful, execute the transaction
                try:
                    tx_receipt = self.client.execute_create_lbp(
                        instance_address=instance,
                        private_key=self.private_key
                    )
                    logger.info(f"✅ Successfully created LBP for {instance}")
                    self.stats['lbp_created'] += 1
                    self._schedule_completion_check(instance, backer, tx_receipt.get('tx_hash'))
                    self._notify(f"✅ LBP created for {instance}")
                    return True

                except ContractLogicError as e:
                    logger.error(f"❌ Error executing createLBP: {str(e)}")
                    self.stats['lbp_failed'] += 1
                    self._add_problem_instance(instance, backer, f"Execution error: {str(e)}")
                    self._notify(f"❌ Error executing createLBP: {str(e)}")
                    return False

            elif validation_result["status"] == "lbp_already_created":
                logger.info(f"ℹ️ LBP already created for {instance}, checking for completed event")
                self._schedule_completion_check(instance, backer)
                self._check_for_indexer_issue(instance, backer)
                return True

            elif validation_result["status"] == "insufficient_balance":
                logger.warning(f"❗ Insufficient backing asset balance for {instance}")
                self._add_problem_instance(instance, backer, 'Insufficient backing asset balance')
                if self.slack:
                    self.slack.notify_insufficient_balance(instance, backer)
                return False

            else:
                error_message = validation_result.get("message", "Unknown error")
                logger.error(f"❌ Contract error in createLBP: {error_message}")
                self.stats['lbp_failed'] += 1
                self._add_problem_instance(instance, backer, f"LBP creation error: {error_message}")
                self._notify(f"❌ createLBP error: {error_message}")
                return False

        except ContractLogicError as e:
            logger.exception(f"🚨 Error validating LBP for {instance}: {e}")
            self.stats['lbp_failed'] += 1
            self._add_problem_instance(instance, backer, str(e))
            self._notify(f"🚨 Error creating LBP for {instance}: {e}")
            return False

    def process_pending_instances(self):
        """Process pending instances ready for retry."""
        current_time = time.time()
        current_block = self.web3.eth.block_number

        # Process each pending instance
        for instance, data in list(self.pending_instances.items()):
            backer = data.get('backer', '')
            instance_type = data.get('type', '')
            retry_count = data.get('retry_count', 0)

            # Skip instances that aren't ready yet
            if instance_type == 'check_completion' and current_block < data.get('next_check_block', 0):
                continue
            elif instance_type == 'reset_retry' and current_time < data.get('next_retry_time', 0):
                continue
            elif current_time - data.get('last_attempt', 0) < self.retry_interval:
                continue

            # Check if already completed (may have happened through other means)
            if self.client.check_completed_event(instance, backer):
                logger.info(f"✅ Found CirclesBackingCompleted event for {instance} during retry check")
                self._add_completed_backer(backer)
                del self.pending_instances[instance]
                continue

            # Check for max retries exceeded
            if retry_count >= self.max_retries:
                logger.warning(f"⚠️ Instance {instance} exceeded max retries ({self.max_retries})")
                self._add_problem_instance(
                    instance,
                    backer,
                    f"Exceeded max retries ({self.max_retries}). Last error: {data.get('error', 'Unknown')}"
                )
                del self.pending_instances[instance]
                continue

            # Update attempt time
            self.pending_instances[instance]['last_attempt'] = current_time
            self.pending_instances[instance]['retry_count'] = retry_count + 1

            # Process according to instance type
            try:
                if instance_type == 'check_completion':
                    # Update for next check
                    self.pending_instances[instance]['next_check_block'] = current_block + 2

                    # After several retries, check for indexer issues
                    if retry_count > 5:
                        self._check_for_indexer_issue(instance, backer)

                    # After too many retries, try creating LBP again
                    if retry_count > 10:
                        logger.warning(f"⚠️ Too many completion checks for {instance}, trying createLBP again")
                        self._handle_create_lbp(instance, backer)
                        del self.pending_instances[instance]  # Remove from pending after retry

                elif instance_type == 'reset_retry':
                    # Process retry for resetCowswapOrder
                    self._process_reset_retry(instance, backer, retry_count)

            except Exception as e:
                logger.exception(f"🚨 Error retrying {instance}: {e}")
                self.pending_instances[instance]['error'] = str(e)
                self._notify(f"🚨 Error retrying {instance}: {e}")

    def _process_reset_retry(self, instance: str, backer: str, retry_count: int):
        """Process a retry for resetCowswapOrder."""
        try:
            # Validate resetCowswapOrder first
            validation_result = self.client.validate_reset_cowswap_order(
                instance_address=instance,
                private_key=self.private_key
            )

            if validation_result["status"] == "valid":
                # Validation successful, execute the transaction
                try:
                    tx_receipt = self.client.execute_cowswap_order(
                        instance_address=instance,
                        private_key=self.private_key
                    )

                    logger.info(f"✅ Successfully reset Cowswap order for {instance} on retry")
                    self.stats['reset_succeeded'] += 1
                    self._schedule_completion_check(instance, backer, tx_receipt.get('tx_hash'))
                    self._notify(f"✅ Reset succeeded for {instance} on retry #{retry_count}")

                    # Remove from pending instances
                    del self.pending_instances[instance]

                except ContractLogicError as e:
                    logger.error(f"❌ Error executing cowswap order on retry: {str(e)}")
                    self.stats['reset_failed'] += 1
                    self.pending_instances[instance]['error'] = str(e)
                    self._notify(f"❌ Error executing cowswap order on retry: {str(e)}")

            elif validation_result["status"] == "order_already_settled":
                logger.info(f"⚠️ Order settled for {instance} on retry, trying createLBP")
                if self._handle_create_lbp(instance, backer):
                    # If createLBP was successful or already created, remove from pending
                    del self.pending_instances[instance]

            elif validation_result["status"] == "order_uid_same":
                # Calculate exponential backoff (3, 6, 9... minutes), cap at 30 minutes
                wait_minutes = min(3 * (retry_count + 1), 30)
                next_retry_time = time.time() + (wait_minutes * 60)

                self.pending_instances[instance]['next_retry_time'] = next_retry_time

                logger.info(f"⏱️ OrderUID still same for {instance}, retry #{retry_count+1} in {wait_minutes} minutes")
                self._notify(f"⏱️ OrderUID still same for {instance}, retry #{retry_count+1} in {wait_minutes} minutes")

            else:
                error_message = validation_result.get("message", "Unknown error")
                logger.error(f"❌ Contract error in reset retry: {error_message}")
                self.stats['reset_failed'] += 1
                self.pending_instances[instance]['error'] = error_message
                self._notify(f"❌ Reset retry failed: {error_message}")

        except Exception as e:
            logger.exception(f"🚨 Error in retry reset for {instance}: {e}")
            self.pending_instances[instance]['error'] = str(e)
            self._notify(f"🚨 Error in retry reset for {instance}: {e}")

    def _schedule_completion_check(self, instance: str, backer: str, tx_hash=None):
        """Schedule a check for completed event in the next block."""
        self.pending_instances[instance] = {
            'backer': backer,
            'retry_count': 0,
            'last_attempt': time.time(),
            'type': 'check_completion',
            'next_check_block': self.web3.eth.block_number + 1,
            'timestamp': time.time()
        }
        if tx_hash:
            self.pending_instances[instance]['tx_hash'] = tx_hash

    def _schedule_reset_retry(self, instance: str, backer: str):
        """Schedule a retry for resetCowswapOrder with initial 3-minute delay."""
        next_retry_time = time.time() + (3 * 60)  # 3 minutes

        self.pending_instances[instance] = {
            'backer': backer,
            'retry_count': 1,
            'last_attempt': time.time(),
            'type': 'reset_retry',
            'next_retry_time': next_retry_time,
            'timestamp': time.time()
        }

    def _add_problem_instance(self, instance: str, backer: str, error: str):
        """Add an instance to the problem instances map."""
        self.problem_instances[instance] = {
            'backer': backer,
            'error': error,
            'timestamp': time.time()
        }

    def _add_completed_backer(self, backer: str):
        """Add a backer to the completed backers list."""
        if backer:
            self._completed_backers.add(backer.lower())
            logger.info(f"✅ Added {backer} to completed backers")

    def get_completed_backers(self) -> Set[str]:
        """Get the set of completed backers and clear the internal set."""
        completed = self._completed_backers.copy()
        self._completed_backers.clear()
        return completed

    def _check_for_indexer_issue(self, instance: str, backer: str):
        """Check if there might be an indexer issue with this instance."""
        current_block = self.web3.eth.block_number
        initiated_block = self.client.get_initiated_block(instance)

        if initiated_block and (current_block - initiated_block > 20):
            issue_message = (
                f"⚠️ Potential indexer issue: Instance {instance} initiated at block {initiated_block}, "
                f"now at {current_block} ({current_block - initiated_block} blocks difference)"
            )
            logger.warning(issue_message)
            self.stats['indexer_issues'] += 1

            # Only notify after specific thresholds to avoid spam
            blocks_since = current_block - initiated_block
            if blocks_since in [20, 50, 100, 200, 500, 1000] and self.slack:
                self.slack.notify_indexer_issue(issue_message)

    def _notify(self, message: str):
        """Send a notification to Slack if available."""
        if self.slack:
            self.slack.send_message(message)

    def get_stats(self) -> Dict:
        """Get processor statistics."""
        return {
            'lbp_created': self.stats['lbp_created'],
            'lbp_failed': self.stats['lbp_failed'],
            'reset_succeeded': self.stats['reset_succeeded'],
            'reset_failed': self.stats['reset_failed'],
            'indexer_issues': self.stats['indexer_issues'],
            'pending_instances': len(self.pending_instances),
            'problem_instances': len(self.problem_instances)
        }

    def get_pending_instances(self) -> Dict:
        """Get all pending instances."""
        return self.pending_instances

    def get_problem_instances(self) -> Dict:
        """Get all problem instances."""
        return self.problem_instances

    def reset(self):
        logger.info("🔄 Resetting LBP processor state")
        self.pending_instances = {}
        self.problem_instances = {}
        self._completed_backers = set()

        # Keep historical stats but reset counters for current session
        current_stats = self.stats.copy()
        self.stats = {k: 0 for k in self.stats}
        logger.info(f"🔄 Reset LBP processor. Previous stats: {current_stats}")
