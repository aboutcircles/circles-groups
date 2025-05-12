import unittest
from unittest.mock import MagicMock, patch, mock_open
import json
import requests
from web3 import Web3
from web3.exceptions import ContractLogicError
from src.clients.nethermind import NethermindClient


class TestNethermindClient(unittest.TestCase):
    def setUp(self):
        """Set up NethermindClient with mocked dependencies."""
        # Mock Web3
        self.mock_web3 = MagicMock()
        self.mock_web3.is_connected.return_value = True

        # Patch Web3 constructor
        with patch('src.clients.nethermind.Web3') as mock_web3_class:
            mock_web3_class.HTTPProvider.return_value = "mock_provider"
            mock_web3_class.return_value = self.mock_web3

            # Mock settings
            self.mock_settings = MagicMock()
            self.mock_settings.circles_backing_abi_path = 'mock_path'

            # Mock open for ABI file
            with patch('src.clients.nethermind.settings', self.mock_settings):
                with patch('builtins.open', mock_open(read_data='{"abi": "mock"}')):
                    with patch('json.load', return_value={"abi": "mock"}):
                        # Initialize client
                        self.client = NethermindClient("http://mock-rpc.example.com")

        # Mock requests for POST calls
        self.patcher = patch('src.clients.nethermind.requests.post')
        self.mock_post = self.patcher.start()
        self.addCleanup(self.patcher.stop)

    def test_initialization(self):
        """Test client initialization."""
        self.assertEqual(self.client.rpc_url, "http://mock-rpc.example.com")
        self.assertEqual(self.client.web3, self.mock_web3)
        self.assertEqual(self.client._cache, {'trusted_accounts': set(), 'last_processed_block': 0})
        self.assertEqual(self.client.abi, {"abi": "mock"})

    def test_fetch_backing_status_success(self):
        """Test fetching backing status successfully."""
        # Mock response for initiated events
        initiated_response = MagicMock()
        initiated_response.json.return_value = {
            "result": {
                "columns": ["backer", "circlesBackingInstance", "blockNumber"],
                "rows": [
                    ["0xbacker1", "0xinstance1", "100"],
                    ["0xbacker2", "0xinstance2", "200"]
                ]
            }
        }

        # Mock response for completed events
        completed_response = MagicMock()
        completed_response.json.return_value = {
            "result": {
                "columns": ["backer", "circlesBackingInstance", "blockNumber"],
                "rows": [
                    ["0xbacker1", "0xinstance1", "150"]  # This one is complete
                ]
            }
        }

        # Configure mock to return different responses
        self.mock_post.side_effect = [initiated_response, completed_response]

        # Call the method
        fallback_pairs, completed_backers, latest_block = self.client.fetch_backing_status(from_block=50)

        # Assertions
        self.assertEqual(len(self.mock_post.call_args_list), 2)  # Should make 2 calls

        # Check fallback pairs (initiated but not completed)
        self.assertEqual(len(fallback_pairs), 1)
        self.assertIn(("0xbacker2", "0xinstance2"), fallback_pairs)

        # Check completed backers
        self.assertEqual(len(completed_backers), 1)
        self.assertIn("0xbacker1", completed_backers)

        # Check latest block
        self.assertEqual(latest_block, 200)  # Max block from both results

    def test_fetch_backing_status_request_exception(self):
        """Test handling a request exception in fetch_backing_status."""
        # Mock request to raise an exception
        self.mock_post.side_effect = requests.RequestException("Connection error")

        # Call the method
        fallback_pairs, completed_backers, latest_block = self.client.fetch_backing_status(from_block=50)

        # Assertions - should return empty sets and cache value
        self.assertEqual(len(fallback_pairs), 0)
        self.assertEqual(len(completed_backers), 0)
        self.assertEqual(latest_block, 0)  # Default from cache

    def test_fetch_group_trust_relations_success(self):
        """Test fetching trust relations successfully."""
        # Mock response
        response = MagicMock()
        response.json.return_value = {
            "result": {
                "columns": ["trustee", "blockNumber"],
                "rows": [
                    ["0xtrustee1", "100"],
                    ["0xtrustee2", "200"]
                ]
            }
        }

        self.mock_post.return_value = response

        # Call the method
        trustees, latest_block = self.client.fetch_group_trust_relations("0xBaseGroup", from_block=50)

        # Assertions
        self.mock_post.assert_called_once()

        # Check trustees
        self.assertEqual(len(trustees), 2)
        self.assertIn("0xtrustee1", trustees)
        self.assertIn("0xtrustee2", trustees)

        # Check latest block
        self.assertEqual(latest_block, 200)

        # Check cache updates
        self.assertEqual(self.client._cache['trusted_accounts'], trustees)
        self.assertEqual(self.client._cache['last_processed_block'], 200)

    def test_fetch_group_trust_relations_no_results(self):
        """Test fetching trust relations with no results."""
        # Mock response with no rows
        response = MagicMock()
        response.json.return_value = {
            "result": {
                "columns": ["trustee", "blockNumber"],
                "rows": []
            }
        }

        self.mock_post.return_value = response

        # Set up cache with existing data
        self.client._cache['trusted_accounts'] = {"0xcached"}
        self.client._cache['last_processed_block'] = 100

        # Call the method with from_block > 0 to test cache fallback
        trustees, latest_block = self.client.fetch_group_trust_relations("0xBaseGroup", from_block=50)

        # Assertions
        self.mock_post.assert_called_once()

        # Should use cached values
        self.assertEqual(trustees, {"0xcached"})
        self.assertEqual(latest_block, 50)  # Should not update, return from_block

    def test_fetch_group_trust_relations_exception(self):
        """Test exception handling in fetch_group_trust_relations."""
        # Mock request to raise an exception
        self.mock_post.side_effect = Exception("Unknown error")

        # Set up cache with existing data
        self.client._cache['trusted_accounts'] = {"0xcached"}
        self.client._cache['last_processed_block'] = 100

        # Call the method
        trustees, latest_block = self.client.fetch_group_trust_relations("0xBaseGroup", from_block=50)

        # Assertions
        self.assertEqual(trustees, {"0xcached"})  # Should use cached values
        self.assertEqual(latest_block, 100)  # Should use cached block

        # Test with no cache - should return empty set and from_block
        self.client._cache['trusted_accounts'] = None
        trustees, latest_block = self.client.fetch_group_trust_relations("0xBaseGroup", from_block=50)
        self.assertEqual(trustees, set())
        self.assertEqual(latest_block, 50)

    # New tests for eth_call methods
    def test_eth_call_reset_cowswap_order_success(self):
        """Test eth_call for resetCowswapOrder success."""
        # Mock contract call success
        mock_contract = MagicMock()
        self.mock_web3.eth.contract.return_value = mock_contract
        mock_contract.functions.resetCowswapOrder.return_value.call.return_value = None  # No error

        # Mock to_checksum_address
        self.mock_web3.to_checksum_address.return_value = "0xChecksum"

        # Call the method
        self.client.eth_call_reset_cowswap_order("0xinstance")

        # Assertions
        self.mock_web3.eth.contract.assert_called_once_with(address="0xChecksum", abi=self.client.abi)
        mock_contract.functions.resetCowswapOrder.assert_called_once_with("0xinstance")
        mock_contract.functions.resetCowswapOrder.return_value.call.assert_called_once()

    def test_eth_call_reset_cowswap_order_error(self):
        """Test eth_call for resetCowswapOrder with contract errors."""
        # Mock contract call to raise ContractLogicError
        mock_contract = MagicMock()
        self.mock_web3.eth.contract.return_value = mock_contract
        mock_contract.functions.resetCowswapOrder.return_value.call.side_effect = ContractLogicError("OrderAlreadySettled()")

        # Call the method - should raise the error for caller to handle
        with self.assertRaises(ContractLogicError):
            self.client.eth_call_reset_cowswap_order("0xinstance")

    def test_eth_call_create_lbp_success(self):
        """Test eth_call for createLBP success."""
        # Mock contract call success
        mock_contract = MagicMock()
        self.mock_web3.eth.contract.return_value = mock_contract
        mock_contract.functions.createLBP.return_value.call.return_value = None  # No error

        # Mock to_checksum_address
        self.mock_web3.to_checksum_address.return_value = "0xChecksum"

        # Call the method
        self.client.eth_call_create_lbp("0xinstance")

        # Assertions
        self.mock_web3.eth.contract.assert_called_once_with(address="0xChecksum", abi=self.client.abi)
        mock_contract.functions.createLBP.assert_called_once_with("0xinstance")
        mock_contract.functions.createLBP.return_value.call.assert_called_once()

    def test_eth_call_create_lbp_error(self):
        """Test eth_call for createLBP with contract errors."""
        # Mock contract call to raise ContractLogicError
        mock_contract = MagicMock()
        self.mock_web3.eth.contract.return_value = mock_contract
        mock_contract.functions.createLBP.return_value.call.side_effect = ContractLogicError("LBPAlreadyCreated()")

        # Call the method - should raise the error for caller to handle
        with self.assertRaises(ContractLogicError):
            self.client.eth_call_create_lbp("0xinstance")

    def test_execute_reset_cowswap_order_success(self):
        """Test executing resetCowswapOrder successfully."""
        # Mock contract call success
        mock_contract = MagicMock()
        self.mock_web3.eth.contract.return_value = mock_contract

        # Mock transaction details
        self.mock_web3.eth.get_transaction_count.return_value = 1
        self.mock_web3.eth.gas_price = 20000000000

        # Mock transaction sending
        tx_hash = b"tx_hash"
        self.mock_web3.eth.send_raw_transaction.return_value = tx_hash

        # Mock receipt
        receipt = {"status": 1, "blockNumber": 100}
        self.mock_web3.eth.wait_for_transaction_receipt.return_value = receipt

        # Call the method
        result = self.client.execute_reset_cowswap_order("0xinstance", "private_key")

        # Assertions
        self.assertEqual(result["transactionHash"], tx_hash.hex())
        mock_contract.functions.resetCowswapOrder.assert_called_once()

    def test_execute_reset_cowswap_order_error(self):
        """Test executing resetCowswapOrder with error."""
        # Mock contract call to raise an error
        mock_contract = MagicMock()
        self.mock_web3.eth.contract.return_value = mock_contract

        # Make build_transaction raise an exception
        mock_contract.functions.resetCowswapOrder.return_value.build_transaction.side_effect = Exception("Transaction error")

        # Call the method - should raise the error for caller to handle
        with self.assertRaises(Exception):
            self.client.execute_reset_cowswap_order("0xinstance", "private_key")

    def test_execute_create_lbp_success(self):
        """Test executing createLBP successfully."""
        # Mock contract call success
        mock_contract = MagicMock()
        self.mock_web3.eth.contract.return_value = mock_contract

        # Mock transaction details
        self.mock_web3.eth.get_transaction_count.return_value = 1
        self.mock_web3.eth.gas_price = 20000000000

        # Mock transaction sending
        tx_hash = b"tx_hash"
        self.mock_web3.eth.send_raw_transaction.return_value = tx_hash

        # Mock receipt
        receipt = {"status": 1, "blockNumber": 100}
        self.mock_web3.eth.wait_for_transaction_receipt.return_value = receipt

        # Call the method
        result = self.client.execute_create_lbp("0xinstance", "private_key")

        # Assertions
        self.assertEqual(result["transactionHash"], tx_hash.hex())
        mock_contract.functions.createLBP.assert_called_once()

    def test_execute_create_lbp_error(self):
        """Test executing createLBP with error."""
        # Mock contract call to raise an error
        mock_contract = MagicMock()
        self.mock_web3.eth.contract.return_value = mock_contract

        # Make build_transaction raise an exception
        mock_contract.functions.createLBP.return_value.build_transaction.side_effect = Exception("Transaction error")

        # Call the method - should raise the error for caller to handle
        with self.assertRaises(Exception):
            self.client.execute_create_lbp("0xinstance", "private_key")

    # Leave these older tests for backward compatibility during transition
    def test_validate_reset_cowswap_order_valid(self):
        """Test validating resetCowswapOrder as valid."""
        # Mock contract call success
        mock_contract = MagicMock()
        self.mock_web3.eth.contract.return_value = mock_contract
        mock_contract.functions.resetCowswapOrder.return_value.call.return_value = None  # No error

        # Mock account
        mock_account = MagicMock(address="0xService")
        self.mock_web3.eth.account.from_key.return_value = mock_account

        # Mock to_checksum_address
        self.mock_web3.to_checksum_address.return_value = "0xChecksum"

        # Call the method
        result = self.client.validate_reset_cowswap_order("0xinstance", "private_key")

        # Assertions
        self.assertEqual(result["status"], "valid")
        self.mock_web3.eth.contract.assert_called_once_with(address="0xChecksum", abi=self.client.abi)
        mock_contract.functions.resetCowswapOrder.assert_called_once()

    def test_validate_reset_cowswap_order_already_settled(self):
        """Test validating resetCowswapOrder with OrderAlreadySettled error."""
        # Mock contract call to raise an error
        mock_contract = MagicMock()
        self.mock_web3.eth.contract.return_value = mock_contract
        mock_contract.functions.resetCowswapOrder.return_value.call.side_effect = Exception("OrderAlreadySettled")

        # Call the method
        result = self.client.validate_reset_cowswap_order("0xinstance", "private_key")

        # Assertions
        self.assertEqual(result["status"], "order_already_settled")

    def test_validate_reset_cowswap_order_uid_same(self):
        """Test validating resetCowswapOrder with OrderUidIsTheSame error."""
        # Mock contract call to raise an error
        mock_contract = MagicMock()
        self.mock_web3.eth.contract.return_value = mock_contract
        mock_contract.functions.resetCowswapOrder.return_value.call.side_effect = Exception("OrderUidIsTheSame")

        # Call the method
        result = self.client.validate_reset_cowswap_order("0xinstance", "private_key")

        # Assertions
        self.assertEqual(result["status"], "order_uid_same")

    def test_validate_reset_cowswap_order_other_error(self):
        """Test validating resetCowswapOrder with other validation errors."""
        # Mock contract call to raise an error
        mock_contract = MagicMock()
        self.mock_web3.eth.contract.return_value = mock_contract
        mock_contract.functions.resetCowswapOrder.return_value.call.side_effect = Exception("Other error")

        # Call the method
        result = self.client.validate_reset_cowswap_order("0xinstance", "private_key")

        # Assertions
        self.assertEqual(result["status"], "validation_error")
        self.assertEqual(result["error"], "Other error")

    def test_validate_create_lbp_valid(self):
        """Test validating createLBP as valid."""
        # Mock contract call success
        mock_contract = MagicMock()
        self.mock_web3.eth.contract.return_value = mock_contract
        mock_contract.functions.createLBP.return_value.call.return_value = None  # No error

        # Call the method
        result = self.client.validate_create_lbp("0xinstance", "private_key")

        # Assertions
        self.assertEqual(result["status"], "valid")

    def test_validate_create_lbp_already_created(self):
        """Test validating createLBP with AlreadyCreated error."""
        # Mock contract call to raise an error
        mock_contract = MagicMock()
        self.mock_web3.eth.contract.return_value = mock_contract
        mock_contract.functions.createLBP.return_value.call.side_effect = Exception("AlreadyCreated")

        # Call the method
        result = self.client.validate_create_lbp("0xinstance", "private_key")

        # Assertions
        self.assertEqual(result["status"], "already_created")

    def test_validate_create_lbp_insufficient_balance(self):
        """Test validating createLBP with InsufficientBackingAssetBalance error."""
        # Mock contract call to raise an error
        mock_contract = MagicMock()
        self.mock_web3.eth.contract.return_value = mock_contract
        mock_contract.functions.createLBP.return_value.call.side_effect = Exception("InsufficientBackingAssetBalance")

        # Call the method
        result = self.client.validate_create_lbp("0xinstance", "private_key")

        # Assertions
        self.assertEqual(result["status"], "insufficient_balance")

    def test_try_reset_cowswap_order_success(self):
        """Test executing resetCowswapOrder successfully."""
        # Mock contract call success
        mock_contract = MagicMock()
        self.mock_web3.eth.contract.return_value = mock_contract

        # Mock transaction details
        self.mock_web3.eth.get_transaction_count.return_value = 1
        self.mock_web3.eth.gas_price = 20000000000

        # Mock transaction sending
        tx_hash = b"tx_hash"
        self.mock_web3.eth.send_raw_transaction.return_value = tx_hash

        # Mock receipt
        receipt = {"status": 1, "blockNumber": 100}
        self.mock_web3.eth.wait_for_transaction_receipt.return_value = receipt

        # Call the method
        result = self.client.try_reset_cowswap_order("0xinstance", "private_key")

        # Assertions
        self.assertEqual(result["status"], "success")
        self.assertEqual(result["receipt"], receipt)
        mock_contract.functions.resetCowswapOrder.assert_called_once()

    def test_try_reset_cowswap_order_already_settled(self):
        """Test resetCowswapOrder with OrderAlreadySettled error."""
        # Mock contract call to raise an error
        mock_contract = MagicMock()
        self.mock_web3.eth.contract.return_value = mock_contract

        # Make build_transaction raise an exception
        mock_contract.functions.resetCowswapOrder.return_value.build_transaction.side_effect = Exception("OrderAlreadySettled")

        # Call the method
        result = self.client.try_reset_cowswap_order("0xinstance", "private_key")

        # Assertions
        self.assertEqual(result["status"], "order_already_settled")

    def test_try_reset_cowswap_order_uid_same(self):
        """Test resetCowswapOrder with OrderUidIsTheSame error."""
        # Mock contract call to raise an error
        mock_contract = MagicMock()
        self.mock_web3.eth.contract.return_value = mock_contract

        # Make build_transaction raise an exception
        mock_contract.functions.resetCowswapOrder.return_value.build_transaction.side_effect = Exception("OrderUidIsTheSame")

        # Call the method
        result = self.client.try_reset_cowswap_order("0xinstance", "private_key")

        # Assertions
        self.assertEqual(result["status"], "order_uid_same")

    def test_check_completed_event_success(self):
        """Test checking for completed event successfully."""
        # Mock response with a completed event
        response = MagicMock()
        response.json.return_value = {
            "result": {
                "columns": ["backer", "circlesBackingInstance"],
                "rows": [["0xbacker", "0xinstance"]]
            }
        }

        self.mock_post.return_value = response

        # Call the method
        result = self.client.check_completed_event("0xinstance", "0xbacker")

        # Assertions
        self.assertTrue(result)
        self.mock_post.assert_called_once()

    def test_check_completed_event_not_found(self):
        """Test checking for completed event when not found."""
        # Mock response with no rows
        response = MagicMock()
        response.json.return_value = {
            "result": {
                "columns": ["backer", "circlesBackingInstance"],
                "rows": []
            }
        }

        self.mock_post.return_value = response

        # Call the method
        result = self.client.check_completed_event("0xinstance", "0xbacker")

        # Assertions
        self.assertFalse(result)

    def test_get_initiated_block_success(self):
        """Test getting initiated block successfully."""
        # Mock response with an initiated event
        response = MagicMock()
        response.json.return_value = {
            "result": {
                "columns": ["blockNumber"],
                "rows": [["100"]]
            }
        }

        self.mock_post.return_value = response

        # Call the method
        result = self.client.get_initiated_block("0xinstance")

        # Assertions
        self.assertEqual(result, 100)
        self.mock_post.assert_called_once()

    def test_get_initiated_block_not_found(self):
        """Test getting initiated block when not found."""
        # Mock response with no rows
        response = MagicMock()
        response.json.return_value = {
            "result": {
                "columns": ["blockNumber"],
                "rows": []
            }
        }

        self.mock_post.return_value = response

        # Call the method
        result = self.client.get_initiated_block("0xinstance")

        # Assertions
        self.assertIsNone(result)

    def test_get_trusted_accounts(self):
        """Test getting trusted accounts."""
        # Mock response
        response = MagicMock()
        response.json.return_value = {
            "result": {
                "columns": ["trustee"],
                "rows": [
                    ["0xtrustee1"],
                    ["0xtrustee2"]
                ]
            }
        }

        self.mock_post.return_value = response

        # Call the method
        trustees = self.client.get_trusted_accounts("0xBaseGroup")

        # Assertions
        self.mock_post.assert_called_once()
        self.assertEqual(len(trustees), 2)
        self.assertIn("0xtrustee1", trustees)
        self.assertIn("0xtrustee2", trustees)

    def test_get_trusted_accounts_no_results(self):
        """Test getting trusted accounts with no results."""
        # Mock response with missing data
        response = MagicMock()
        response.json.return_value = {
            "result": {}
        }

        self.mock_post.return_value = response

        # Call the method
        trustees = self.client.get_trusted_accounts("0xBaseGroup")

        # Assertions
        self.assertEqual(trustees, set())

    def test_check_health(self):
        """Test health check functionality."""
        # Mock web3 connection and block number
        self.mock_web3.is_connected.return_value = True
        self.mock_web3.eth.block_number = 1000

        # Mock indexer response
        response = MagicMock()
        response.json.return_value = {
            "result": {
                "rows": [["990"]]
            }
        }

        self.mock_post.return_value = response

        # Call the method
        health = self.client.check_health()

        # Assertions
        self.assertTrue(health["rpc_connected"])
        self.assertEqual(health["current_block"], 1000)
        self.assertTrue(health["indexer_connected"])
        self.assertEqual(health["latest_indexed_block"], 990)
        self.assertEqual(health["block_lag"], 10)
        self.assertEqual(health["status"], "degraded")  # Because block_lag > 5

    def test_check_health_all_healthy(self):
        """Test health check with all components healthy."""
        # Mock web3 connection and block number
        self.mock_web3.is_connected.return_value = True
        self.mock_web3.eth.block_number = 1000

        # Mock indexer response with close block number
        response = MagicMock()
        response.json.return_value = {
            "result": {
                "rows": [["998"]]
            }
        }

        self.mock_post.return_value = response

        # Call the method
        health = self.client.check_health()

        # Assertions
        self.assertEqual(health["status"], "healthy")  # Because block_lag <= 5

    def test_check_health_rpc_down(self):
        """Test health check with RPC connection down."""
        # Mock web3 connection failure
        self.mock_web3.is_connected.return_value = False

        # Call the method
        health = self.client.check_health()

        # Assertions
        self.assertFalse(health["rpc_connected"])
        self.assertEqual(health["status"], "unhealthy")

    def test_check_health_indexer_down(self):
        """Test health check with indexer down."""
        # Mock web3 connection success
        self.mock_web3.is_connected.return_value = True
        self.mock_web3.eth.block_number = 1000

        # Make indexer request fail
        self.mock_post.side_effect = Exception("Indexer error")

        # Call the method
        health = self.client.check_health()

        # Assertions
        self.assertTrue(health["rpc_connected"])
        self.assertFalse(health["indexer_connected"])
        self.assertEqual(health["status"], "unhealthy")


if __name__ == "__main__":
    unittest.main()
