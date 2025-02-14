import pytest
import time
from unittest.mock import Mock, patch
from web3.exceptions import ContractLogicError
from src.clients.nethermind import NethermindClient

import sys
import os

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '../../')))

class TestNethermindClient:
    @pytest.fixture
    def mock_web3(self):
        with patch('web3.Web3') as mock:
            yield mock

    @pytest.fixture
    def mock_contract(self):
        mock = Mock()
        mock.functions.createLBP.return_value.call.return_value = True
        return mock

    @pytest.fixture
    def client(self, mock_web3):
        return NethermindClient("http://mock-rpc-url")

    def test_validate_create_lbp_success(self, client, mock_contract):
        """Test successful LBP creation validation"""
        result = client.validate_create_lbp(
            backer_address="0x1234...",
            instance_address="0x5678...",
            initiated_timestamp=int(time.time()) - 600,  # 10 minutes ago
            private_key="mock_key"
        )
        assert result is True

    def test_validate_create_lbp_already_created(self, client, mock_contract):
        """Test AlreadyCreated error case"""
        mock_contract.functions.createLBP.return_value.call.side_effect = ContractLogicError(
            "execution reverted: AlreadyCreated"
        )

        result = client.validate_create_lbp(
            backer_address="0x1234...",
            instance_address="0x5678...",
            initiated_timestamp=int(time.time()) - 600,
            private_key="mock_key"
        )
        assert result is True

    def test_validate_create_lbp_order_not_filled_recent(self, client, mock_contract):
        """Test OrderNotFilledYet error for recent orders"""
        current_time = int(time.time())
        mock_contract.functions.createLBP.return_value.call.side_effect = ContractLogicError(
            "execution reverted: OrderNotFilledYet"
        )

        with patch('requests.post') as mock_slack:
            result = client.validate_create_lbp(
                backer_address="0x1234...",
                instance_address="0x5678...",
                initiated_timestamp=current_time - 600,  # 10 minutes ago
                private_key="mock_key"
            )

            assert result is False
            assert mock_slack.called
            # Verify Slack message content for recent order

    def test_validate_create_lbp_order_not_filled_old(self, client, mock_contract):
        """Test OrderNotFilledYet error for orders over 20 minutes old"""
        current_time = int(time.time())
        mock_contract.functions.createLBP.return_value.call.side_effect = ContractLogicError(
            "execution reverted: OrderNotFilledYet"
        )

        with patch('requests.post') as mock_slack:
            result = client.validate_create_lbp(
                backer_address="0x1234...",
                instance_address="0x5678...",
                initiated_timestamp=current_time - 1500,  # 25 minutes ago
                private_key="mock_key"
            )

            assert result is False
            assert mock_slack.called
            # Verify Slack message content for old order

    def test_validate_create_lbp_insufficient_balance(self, client, mock_contract):
        """Test InsufficientBackingAssetBalance error"""
        mock_contract.functions.createLBP.return_value.call.side_effect = ContractLogicError(
            "execution reverted: InsufficientBackingAssetBalance"
        )

        with patch('requests.post') as mock_slack:
            result = client.validate_create_lbp(
                backer_address="0x1234...",
                instance_address="0x5678...",
                initiated_timestamp=int(time.time()) - 600,
                private_key="mock_key"
            )

            assert result is False
            assert mock_slack.called

    def test_fetch_backing_status(self, client):
        """Test fetch_backing_status with timestamps"""
        mock_response = {
            "result": {
                "columns": ["backer", "circlesBackingInstance", "blockNumber", "timestamp"],
                "rows": [
                    ["0x1234...", "0x5678...", "100", str(int(time.time()) - 1200)],
                    ["0x4321...", "0x8765...", "101", str(int(time.time()) - 600)]
                ]
            }
        }

        with patch('requests.post') as mock_request:
            mock_request.return_value.json.return_value = mock_response
            fallback_pairs, completed_backers, latest_block = client.fetch_backing_status()

            assert len(fallback_pairs) > 0
            # Verify tuple structure (backer, instance, timestamp)
            for pair in fallback_pairs:
                assert len(pair) == 3
                assert isinstance(pair[2], int)
