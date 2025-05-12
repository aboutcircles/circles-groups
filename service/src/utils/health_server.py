import json
import logging
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler
from typing import Dict, Any, Optional

from algorithm.trust_management import TrustManagementAlgorithm
from clients.nethermind import NethermindClient
from clients.screening import ScreeningClient

logger = logging.getLogger(__name__)

class HealthRequestHandler(BaseHTTPRequestHandler):
    trust_algorithm = None
    nethermind_client = None
    screening_client = None

    def do_GET(self):
        """Handle GET requests to various endpoints."""
        if self.path == '/health':
            self.send_health_response()
        elif self.path == '/metrics':
            self.send_metrics_response()
        else:
            self.send_error(404, "Not Found")

    def send_health_response(self):
        """Send health check response."""
        try:
            # Check the health of all components
            health = {
                'status': 'healthy',
                'details': {}
            }

            # Check RPC and indexer health
            if self.nethermind_client:
                rpc_health = self.nethermind_client.check_health()
                health['details']['rpc'] = rpc_health

                # If RPC is unhealthy, the overall service is unhealthy
                if rpc_health.get('status') != 'healthy':
                    health['status'] = rpc_health.get('status', 'unhealthy')

            # Check algorithm health
            if self.trust_algorithm:
                algo_health = self.trust_algorithm.check_health()
                health['details']['algorithm'] = algo_health

                # If block lag is too high, service is degraded
                if algo_health.get('block_lag', 0) > 5:
                    health['status'] = 'degraded'

                # If algorithm can't connect to blockchain, service is unhealthy
                if algo_health.get('status') == 'unhealthy':
                    health['status'] = 'unhealthy'

            # Check screening service health
            if self.screening_client:
                screening_health = self.screening_client.check_health()
                health['details']['screening'] = screening_health

                # If screening service is unhealthy, overall service is degraded
                if screening_health.get('status') != 'healthy' and health['status'] == 'healthy':
                    health['status'] = 'degraded'

            self.send_json_response(health)

        except Exception as e:
            logger.error(f"Error in health check: {e}", exc_info=True)
            self.send_json_response({'status': 'unhealthy', 'error': str(e)}, 500)

    def send_metrics_response(self):
        """Send metrics response."""
        try:
            metrics = {}

            if self.trust_algorithm:
                # Get algorithm stats
                metrics = self.trust_algorithm.check_health()

                # Remove status and other non-metric fields
                if 'status' in metrics:
                    del metrics['status']

            self.send_json_response(metrics)

        except Exception as e:
            logger.error(f"Error in metrics: {e}", exc_info=True)
            self.send_json_response({'error': str(e)}, 500)

    def send_json_response(self, data: Dict[str, Any], status: int = 200):
        """Send a JSON response with the provided data."""
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode('utf-8'))

    def log_message(self, format, *args):
        """Override to use our logger instead of stderr."""
        logger.info(f"{self.address_string()} - {format % args}")

class HealthServer:
    def __init__(
            self,
            host: str = '0.0.0.0',
            port: int = 8080,
            trust_algorithm: Optional[TrustManagementAlgorithm] = None,
            nethermind_client: Optional[NethermindClient] = None,
            screening_client: Optional[ScreeningClient] = None
        ):
            self.host = host
            self.port = port
            self.server = None
            self.thread = None

            # Set static references for the handler class
            # Using setattr to avoid type checking issues
            setattr(HealthRequestHandler, 'trust_algorithm', trust_algorithm)
            setattr(HealthRequestHandler, 'nethermind_client', nethermind_client)
            setattr(HealthRequestHandler, 'screening_client', screening_client)

            logger.info(f"Initialized health server on {host}:{port}")

    def start(self):
        """Start the health server in a separate thread."""
        if self.thread and self.thread.is_alive():
            logger.warning("Health server already running")
            return

        try:
            self.server = HTTPServer((self.host, self.port), HealthRequestHandler)
            self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
            self.thread.start()
            logger.info(f"Health server started on http://{self.host}:{self.port}")
        except Exception as e:
            logger.error(f"Failed to start health server: {e}", exc_info=True)

    def stop(self):
        """Stop the health server."""
        if self.server:
            logger.info("Stopping health server")
            self.server.shutdown()
            self.server.server_close()
            self.server = None
            if self.thread:
                self.thread.join(timeout=5)
                self.thread = None
