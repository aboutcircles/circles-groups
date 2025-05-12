import os
import logging
import signal
import sys
from dotenv import load_dotenv
from clients.nethermind import NethermindClient
from clients.screening import ScreeningClient
from algorithm.trust_management import TrustManagementAlgorithm
from utils.polling_service import PollingService
from utils.health_server import HealthServer
from utils.slack_notifier import SlackNotifier
from config.settings import settings

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler("circles_trust_service.log"),
        logging.StreamHandler()
    ]
)

logger = logging.getLogger(__name__)

# Global references for clean shutdown
polling_service = None
health_server = None
slack_notifier = None

def signal_handler(sig, frame):
    """Handle signals for graceful shutdown."""
    logger.info(f"Received signal {sig}, shutting down...")

    if polling_service:
        polling_service.stop()

    if health_server:
        health_server.stop()

    if slack_notifier:
        slack_notifier.notify_service_stop()

    logger.info("Shutdown complete")
    sys.exit(0)

def main():
    global polling_service, health_server, slack_notifier

    logger.info("Starting Circles Trust Management Service")
    logger.info(f"Starting from block {settings.deploy_block}")

    # Register signal handlers
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    # Initialize clients
    nethermind_client = NethermindClient(settings.nethermind_rpc_url)
    screening_client = ScreeningClient(settings.screening_url)

    # Initialize Slack notifier if webhook URL is provided
    if hasattr(settings, 'slack_webhook_url') and settings.slack_webhook_url:
        slack_notifier = SlackNotifier(
            webhook_url=settings.slack_webhook_url,
            channel=getattr(settings, 'slack_channel', '#circles-alerts'),
            username="Circles Trust Bot"
        )

    # Initialize trust management algorithm
    trust_algorithm = TrustManagementAlgorithm(
        nethermind_client=nethermind_client,
        screening_client=screening_client,
        baseGroup_address=settings.baseGroup_address,  # Fixed parameter name
        private_key=settings.private_key,
        slack_notifier=slack_notifier
    )

    # Initialize health server
    health_server = HealthServer(
        host=getattr(settings, 'health_server_host', '0.0.0.0'),
        port=getattr(settings, 'health_server_port', 8080),
        trust_algorithm=trust_algorithm,
        nethermind_client=nethermind_client,
        screening_client=screening_client
    )
    health_server.start()

    # Initialize and start polling service
    polling_service = PollingService(
        trust_algorithm=trust_algorithm,
        nethermind_client=nethermind_client,
        poll_interval=getattr(settings, 'poll_interval', 5),
        health_check_interval=getattr(settings, 'health_check_interval', 3600),
        slack_notifier=slack_notifier
    )

    try:
        polling_service.start()
    except Exception as e:
        logger.critical(f"Service crashed: {e}", exc_info=True)
        if slack_notifier:
            slack_notifier.send_message(f"🚨 Service crashed: {str(e)}")
    finally:
        health_server.stop()
        if slack_notifier:
            slack_notifier.notify_service_stop()
        logger.info("Service shut down")

if __name__ == "__main__":
    main()
