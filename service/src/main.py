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

# Global references for shutdown
polling_service = None
health_server = None
slack_notifier = None

def signal_handler(sig, frame):
    """Handle signals for graceful shutdown."""
    logger.info(f"Received signal {sig}, shutting down...")

    if polling_service:
        try:
            polling_service.stop()
            logger.info("Polling service stopped")
        except Exception as e:
            logger.error(f"Error stopping polling service: {e}")

    if health_server:
        try:
            health_server.stop()
            logger.info("Health server will stop when process exits")
        except Exception as e:
            logger.error(f"Error stopping health server: {e}")

    if slack_notifier:
        try:
            slack_notifier.notify_service_stop()
            logger.info("Sent service stop notification to Slack")
        except Exception as e:
            logger.error(f"Error notifying Slack: {e}")

    logger.info("Shutdown complete")
    sys.exit(0)

def main():
    global polling_service, health_server, slack_notifier

    logger.info("Starting Circles Trust Management Service")
    logger.info(f"Starting from block {settings.deploy_block}")

    # Register signal handlers
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    # Load .env variables if needed
    load_dotenv()

    # Initialize clients
    nethermind_client = NethermindClient(settings.nethermind_rpc_url)
    screening_client = ScreeningClient(settings.screening_url)

    # Initialize Slack notifier
    if getattr(settings, 'slack_webhook_url', None):
        slack_notifier = SlackNotifier(
            webhook_url=settings.slack_webhook_url,
            channel=getattr(settings, 'slack_channel', '#circles-alerts'),
            username="Circles Trust Bot"
        )
        logger.info("Slack notifications enabled")
    else:
        logger.info("Slack notifications disabled (no webhook URL configured)")

    # Initialize Trust Management Algorithm
    trust_algorithm = TrustManagementAlgorithm(
        nethermind_client=nethermind_client,
        screening_client=screening_client,
        baseGroup_address=settings.baseGroup_address,
        private_key=settings.private_key,
        slack_notifier=slack_notifier
    )
    logger.info("Trust Management Algorithm initialized")

    # Initialize and start Health Server
    health_server = HealthServer(
        host=getattr(settings, 'health_server_host', '0.0.0.0'),
        port=getattr(settings, 'health_server_port', 8080),
        trust_algo=trust_algorithm,
        nether_client=nethermind_client,
        screening=screening_client
    )
    health_server.start()
    logger.info(f"Health server started on {getattr(settings, 'health_server_host', '0.0.0.0')}:{getattr(settings, 'health_server_port', 8080)}")

    # Initialize and start Polling Service
    polling_service = PollingService(
        trust_algorithm=trust_algorithm,
        nethermind_client=nethermind_client,
        poll_interval=getattr(settings, 'poll_interval', 5),
        health_check_interval=getattr(settings, 'health_check_interval', 3600),
        slack_notifier=slack_notifier
    )

    try:
        logger.info("Starting polling service")
        polling_service.start()
    except Exception as e:
        logger.critical("Service crashed", exc_info=True)
        if slack_notifier:
            slack_notifier.send_message(f"🚨 Circles Trust Service crashed: {e}")
    finally:
        # This section will execute on a normal exit or uncaught exception
        logger.info("Service is shutting down")

        if polling_service:
            try:
                polling_service.stop()
                logger.info("Polling service stopped")
            except Exception as e:
                logger.error(f"Error stopping polling service during shutdown: {e}")

        if slack_notifier:
            try:
                slack_notifier.notify_service_stop()
                logger.info("Sent service stop notification to Slack")
            except Exception as e:
                logger.error(f"Error notifying Slack during shutdown: {e}")

        logger.info("Service shut down complete")

if __name__ == "__main__":
    main()
