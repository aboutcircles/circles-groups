# import unittest
# from unittest.mock import MagicMock, patch
# import json
# import threading
# import http.client
# import socket
# import time
# from src.utils.health_server import HealthServer, HealthRequestHandler


# class TestHealthServer(unittest.TestCase):
#     def setUp(self):
#         """Set up the HealthServer with mocked dependencies."""
#         # Mock dependencies
#         self.mock_trust_algorithm = MagicMock()
#         self.mock_nethermind_client = MagicMock()
#         self.mock_screening_client = MagicMock()

#         # Find a free port for testing
#         self.port = self._get_free_port()

#         # Create a health server
#         self.server = HealthServer(
#             host="localhost",
#             port=self.port,
#             trust_algorithm=self.mock_trust_algorithm,
#             nethermind_client=self.mock_nethermind_client,
#             screening_client=self.mock_screening_client
#         )

#     def tearDown(self):
#         """Clean up after tests."""
#         if hasattr(self, 'server') and self.server.server:
#             self.server.stop()

#     def _get_free_port(self):
#         """Get a free TCP port to use for testing."""
#         s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
#         s.bind(('localhost', 0))
#         port = s.getsockname()[1]
#         s.close()
#         return port

#     def _make_request(self, path, method="GET"):
#         """Make an HTTP request to the server."""
#         conn = http.client.HTTPConnection(f"localhost:{self.port}")
#         conn.request(method, path)
#         response = conn.getresponse()
#         data = response.read().decode('utf-8')
#         conn.close()
#         return response.status, data

#     def test_server_initialization(self):
#         """Test server initialization."""
#         # Check that the handler class references were set
#         self.assertEqual(HealthRequestHandler.trust_algorithm, self.mock_trust_algorithm)
#         self.assertEqual(HealthRequestHandler.nethermind_client, self.mock_nethermind_client)
#         self.assertEqual(HealthRequestHandler.screening_client, self.mock_screening_client)

#         # Check that the server attributes were set correctly
#         self.assertEqual(self.server.host, "localhost")
#         self.assertEqual(self.server.port, self.port)
#         self.assertIsNone(self.server.server)
#         self.assertIsNone(self.server.thread)

#     def test_start_and_stop(self):
#         """Test starting and stopping the server."""
#         # Start the server
#         self.server.start()

#         # Check that the server and thread were created
#         self.assertIsNotNone(self.server.server)
#         self.assertIsNotNone(self.server.thread)

#         # Only check is_alive if thread was actually created
#         if self.server.thread:
#             self.assertTrue(self.server.thread.is_alive())
#         else:
#             self.fail("Server thread was not created")

#         # Wait a bit for the server to start
#         time.sleep(0.1)

#         # Stop the server
#         self.server.stop()

#         # Check that the server was cleaned up
#         self.assertIsNone(self.server.server)

#         # Thread should be dead now or None
#         if self.server.thread:
#             self.assertFalse(self.server.thread.is_alive())

#     def test_health_endpoint_healthy(self):
#         """Test the /health endpoint when everything is healthy."""
#         # Mock the health check methods
#         self.mock_nethermind_client.check_health.return_value = {
#             "status": "healthy",
#             "rpc_connected": True,
#             "block_lag": 2
#         }
#         self.mock_trust_algorithm.check_health.return_value = {
#             "status": "healthy",
#             "block_lag": 2
#         }
#         self.mock_screening_client.check_health.return_value = {
#             "status": "healthy",
#             "connected": True
#         }

#         # Start the server
#         self.server.start()
#         time.sleep(0.1)  # Wait for server to start

#         # Make the request
#         status, data = self._make_request("/health")

#         # Parse the response
#         response = json.loads(data)

#         # Assertions
#         self.assertEqual(status, 200)
#         self.assertEqual(response["status"], "healthy")
#         self.assertIn("details", response)
#         self.assertIn("rpc", response["details"])
#         self.assertIn("algorithm", response["details"])
#         self.assertIn("screening", response["details"])

#     def test_health_endpoint_degraded(self):
#         """Test the /health endpoint when some component is degraded."""
#         # Mock the health check methods
#         self.mock_nethermind_client.check_health.return_value = {
#             "status": "healthy",
#             "rpc_connected": True,
#             "block_lag": 2
#         }
#         self.mock_trust_algorithm.check_health.return_value = {
#             "status": "healthy",
#             "block_lag": 10  # More than 5, should mark as degraded
#         }
#         self.mock_screening_client.check_health.return_value = {
#             "status": "healthy",
#             "connected": True
#         }

#         # Start the server
#         self.server.start()
#         time.sleep(0.1)  # Wait for server to start

#         # Make the request
#         status, data = self._make_request("/health")

#         # Parse the response
#         response = json.loads(data)

#         # Assertions
#         self.assertEqual(status, 200)
#         self.assertEqual(response["status"], "degraded")

#     def test_health_endpoint_unhealthy(self):
#         """Test the /health endpoint when some component is unhealthy."""
#         # Mock the health check methods
#         self.mock_nethermind_client.check_health.return_value = {
#             "status": "unhealthy",
#             "rpc_connected": False
#         }
#         self.mock_trust_algorithm.check_health.return_value = {
#             "status": "healthy",
#             "block_lag": 2
#         }
#         self.mock_screening_client.check_health.return_value = {
#             "status": "healthy",
#             "connected": True
#         }

#         # Start the server
#         self.server.start()
#         time.sleep(0.1)  # Wait for server to start

#         # Make the request
#         status, data = self._make_request("/health")

#         # Parse the response
#         response = json.loads(data)

#         # Assertions
#         self.assertEqual(status, 200)
#         self.assertEqual(response["status"], "unhealthy")

#     def test_metrics_endpoint(self):
#         """Test the /metrics endpoint."""
#         # Mock the health check method
#         self.mock_trust_algorithm.check_health.return_value = {
#             "status": "healthy",
#             "block_lag": 2,
#             "current_block": 1000,
#             "trusted_accounts_count": 100,
#             "backers_trusted": 50,
#             "lbp_created": 10
#         }

#         # Start the server
#         self.server.start()
#         time.sleep(0.1)  # Wait for server to start

#         # Make the request
#         status, data = self._make_request("/metrics")

#         # Parse the response
#         response = json.loads(data)

#         # Assertions
#         self.assertEqual(status, 200)
#         self.assertNotIn("status", response)  # Status should be removed
#         self.assertEqual(response["current_block"], 1000)
#         self.assertEqual(response["trusted_accounts_count"], 100)
#         self.assertEqual(response["backers_trusted"], 50)
#         self.assertEqual(response["lbp_created"], 10)

#     def test_not_found(self):
#         """Test requesting a non-existent endpoint."""
#         # Start the server
#         self.server.start()
#         time.sleep(0.1)  # Wait for server to start

#         # Make the request
#         status, _ = self._make_request("/nonexistent")

#         # Assertions
#         self.assertEqual(status, 404)

#     def test_error_handling(self):
#         """Test error handling in the health check."""
#         # Mock the health check method to raise an exception
#         self.mock_trust_algorithm.check_health.side_effect = Exception("Test error")

#         # Start the server
#         self.server.start()
#         time.sleep(0.1)  # Wait for server to start

#         # Make the request
#         status, data = self._make_request("/health")

#         # Parse the response
#         response = json.loads(data)

#         # Assertions
#         self.assertEqual(status, 500)
#         self.assertEqual(response["status"], "unhealthy")
#         self.assertEqual(response["error"], "Test error")


# if __name__ == "__main__":
#     unittest.main()
