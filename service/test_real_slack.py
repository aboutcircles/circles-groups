import os
from dotenv import load_dotenv
from src.utils.slack_notifier import SlackNotifier
from src.config.settings import settings

# Load environment variables
load_dotenv()

# Get the webhook URL from environment
webhook_url = os.getenv('SLACK_WEBHOOK_URL')
if not webhook_url:
    print("Error: SLACK_WEBHOOK_URL not found in environment variables")
    exit(1)

# Create the notifier
channel = os.getenv('SLACK_CHANNEL', '#circles-alerts')  # Use default if not specified
notifier = SlackNotifier(
    webhook_url=webhook_url,
    channel=channel,
    username="Circles Test Bot"
)

# Send a simple message
print(f"Sending message to Slack channel {channel}...")
result = notifier.send_message("🧪 This is a test message from the Circles Trust Bot")
print(f"Message sent successfully: {result}")

# Send a more complex message with blocks
print("Sending a health check notification...")
stats = {
    'current_block': 12345,
    'uptime': '3 days, 12:34:56',
    'lbp_created': 42,
    'backers_trusted': 123,
    'pending_instances': 7,
    'problem_instances': 2
}
result = notifier.notify_health_check(stats)
print(f"Health check notification sent: {result}")

# Try an order_uid_same notification
print("Sending an OrderUidIsTheSame notification...")
import time
from datetime import datetime
retry_time = time.time() + 300  # 5 minutes from now
result = notifier.notify_order_uid_same(
    instance_address="0xExample123456789abcdef",
    backer_address="0xBacker987654321fedcba",
    retry_count=2,
    next_retry_time=retry_time
)
print(f"OrderUidIsTheSame notification sent: {result}")

print("All test messages sent!")
