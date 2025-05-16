import requests
import json
import logging
import time
from datetime import datetime
from typing import Dict, Any, Optional, List

logger = logging.getLogger(__name__)

class SlackNotifier:
    def __init__(self, webhook_url: str, channel: str, username: str = "Circles Trust Bot"):
        self.webhook_url = webhook_url
        self.channel = channel
        self.username = username
        self.enabled = bool(webhook_url)

    def send_message(self, text: str, attachments: Optional[List[Dict[str, Any]]] = None, blocks: Optional[List[Dict[str, Any]]] = None) -> bool:
        """Send a message to Slack."""
        if not self.enabled:
            return False

        payload = {
            "text": text
        }

        if attachments:
            payload["attachments"] = json.loads(json.dumps(attachments))
        if blocks:
            payload["blocks"] = json.loads(json.dumps(blocks))

        try:
            response = requests.post(
                self.webhook_url,
                data=json.dumps(payload),
                headers={"Content-Type": "application/json"},
                timeout=10
            )
            response.raise_for_status()
            return True
        except Exception as e:
            logger.error(f"Failed to send Slack notification: {e}")
            return False

    # def notify_service_start(self) -> bool:
    #     """Notify that the service has started."""
    #     # return self.send_message("🟢 Circles Trust Management service has started.")

    def notify_service_stop(self) -> bool:
        """Notify that the service has stopped."""
        return self.send_message("🔴 Circles Trust Management service has stopped.")

    def notify_order_uid_same(self, instance_address: str, backer_address: str, retry_count: int, next_retry_time: float) -> bool:
        """
        Notify about OrderUidIsTheSame condition with detailed information.

        Args:
            instance_address: The backing instance address
            backer_address: The backer address
            retry_count: The current retry count (1 for first detection)
            next_retry_time: Unix timestamp for the next retry
        """
        # Convert timestamp to human-readable format
        retry_datetime = datetime.fromtimestamp(next_retry_time)
        time_now = datetime.now()
        minutes_until_retry = max(0, round((next_retry_time - time.time()) / 60))

        blocks = [
            {
                "type": "header",
                "text": {"type": "plain_text", "text": "⏱️ Cowswap Order UID Same - Retry Scheduled"}
            },
            {
                "type": "section",
                "fields": [
                    {"type": "mrkdwn", "text": f"*Instance:* `{instance_address}`"},
                    {"type": "mrkdwn", "text": f"*Backer:* `{backer_address}`"},
                    {"type": "mrkdwn", "text": "*Status:* OrderUidIsTheSame"},
                    {"type": "mrkdwn", "text": f"*Retry Count:* {retry_count}"},
                    {"type": "mrkdwn", "text": f"*Next Retry:* {retry_datetime.strftime('%Y-%m-%d %H:%M:%S')} (in ~{minutes_until_retry} min)"},
                    {"type": "mrkdwn", "text": f"*Current Time:* {time_now.strftime('%Y-%m-%d %H:%M:%S')}"}
                ]
            },
            {
                "type": "context",
                "elements": [
                    {
                        "type": "mrkdwn",
                        "text": "Waiting for Cowswap order UID to change. This is normal during the order settlement process."
                    }
                ]
            },
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": "Service will automatically retry resetCowswapOrder() with exponential backoff."
                }
            }
        ]

        # Add different context based on retry count
        if retry_count > 3:
            blocks.append({
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": "⚠️ Multiple retries detected. This may indicate a stuck order."
                }
            })

        return self.send_message(
            f"Cowswap Order UID Same for {instance_address} - Retry #{retry_count} scheduled",
            blocks=blocks
        )

    def notify_order_uid_resolved(self, instance_address: str, backer_address: str, retry_count: int) -> bool:
        """Notify when OrderUidIsTheSame condition is resolved."""
        text = (
            f"✅ OrderUidIsTheSame resolved for instance `{instance_address}` after {retry_count} retries.\n"
            f"Backer: `{backer_address}`\n"
            f"Successfully executed resetCowswapOrder(). Proceeding with completion check."
        )
        return self.send_message(text)

    def notify_lbp_created(self, instance_address: str, backer_address: str) -> bool:
        """Notify that LBP was successfully created."""
        text = (
            f"✅ Successfully created LBP for backing instance `{instance_address}`\n"
            f"Backer: `{backer_address}`\n"
            f"Waiting for CirclesBackingCompleted event in next blocks..."
        )
        return self.send_message(text)

    def notify_lbp_creation_failed(self, instance_address: str, error: str) -> bool:
        """Notify that LBP creation failed."""
        text = f"❌ Failed to create LBP for backing instance `{instance_address}`\nError: ```{error}```"
        return self.send_message(text)

    def notify_insufficient_balance(self, instance_address: str, backer_address: str) -> bool:
        """Notify about insufficient backing asset balance."""
        text = (
            f"⚠️ *Manual intervention required*: Insufficient backing asset balance for `{instance_address}`\n"
            f"Backer: `{backer_address}`\n"
            f"*Action needed*: Send missing assets and call createLBP() manually."
        )
        return self.send_message(text)

    def notify_indexer_issue(self, message: str) -> bool:
        """Notify about potential indexer issues."""
        text = f"🔍 *Potential indexer issue detected*\n{message}"
        return self.send_message(text)

    def notify_health_check(self, stats: Dict[str, Any]) -> bool:
        """Send a health check notification with stats."""
        blocks = [
            {
                "type": "header",
                "text": {"type": "plain_text", "text": "🩺 Trust Management Service Health Check"}
            },
            {
                "type": "section",
                "fields": [
                    {"type": "mrkdwn", "text": f"*Current Block:* {stats.get('current_block', 'N/A')}"},
                    {"type": "mrkdwn", "text": f"*Uptime:* {stats.get('uptime', 'N/A')}"},
                    {"type": "mrkdwn", "text": f"*LBP Created:* {stats.get('lbp_created', 0)}"},
                    {"type": "mrkdwn", "text": f"*Backers Trusted:* {stats.get('backers_trusted', 0)}"},
                    {"type": "mrkdwn", "text": f"*Pending Instances:* {stats.get('pending_instances', 0)}"},
                    {"type": "mrkdwn", "text": f"*Problem Instances:* {stats.get('problem_instances', 0)}"}
                ]
            }
        ]

        return self.send_message("Trust Management Service Health Report", blocks=blocks)
