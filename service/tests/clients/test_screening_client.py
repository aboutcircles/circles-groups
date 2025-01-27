import pytest
from unittest import mock
from src.clients.screening import ScreeningClient

@pytest.fixture(scope="module")
def screening_client():
    """Fixture to create a ScreeningClient instance."""
    base_url = "http://mock-api-for-tests.com"  # Placeholder URL
    client = ScreeningClient(base_url)
    return client

def test_check_blacklist_valid_response(screening_client):
    """Test the check_blacklist method with a valid response containing blocked addresses."""
    test_addresses = [
        "0x1234567890abcdef1234567890abcdef12345678",
        "0xabcdef1234567890abcdef1234567890abcdef12"
    ]
    mocked_response = {
        "verdicts": [
            {"address": "0x1234567890abcdef1234567890abcdef12345678", "is_bot": True, "category": "flagged"},
            {"address": "0xabcdef1234567890abcdef1234567890abcdef12", "is_bot": False, "category": "allowed"}
        ]
    }

    with mock.patch('requests.post') as mock_post:
        # Mock the POST request
        mock_post.return_value.status_code = 200
        mock_post.return_value.json.return_value = mocked_response

        # Call the method
        blacklist = screening_client.check_blacklist(test_addresses)

        # Assertions
        assert isinstance(blacklist, list), "Result should be a list"
        assert len(blacklist) == 1, "Should return one blocked or flagged address"
        assert blacklist == ["0x1234567890abcdef1234567890abcdef12345678"], "Only the blocked address should be returned"

def test_check_blacklist_no_blocked_addresses(screening_client):
    """Test the check_blacklist method with no blocked or flagged addresses."""
    test_addresses = [
        "0xabcdef1234567890abcdef1234567890abcdef12"
    ]
    mocked_response = {
        "verdicts": [
            {"address": "0xabcdef1234567890abcdef1234567890abcdef12", "is_bot": False, "category": "allowed"}
        ]
    }

    with mock.patch('requests.post') as mock_post:
        # Mock the POST request
        mock_post.return_value.status_code = 200
        mock_post.return_value.json.return_value = mocked_response

        blacklist = screening_client.check_blacklist(test_addresses)

        assert isinstance(blacklist, list), "Result should be a list"
        assert len(blacklist) == 0, "Should return an empty list if no addresses are blocked or flagged"

def test_check_blacklist_api_failure(screening_client):
    """Test the check_blacklist method when the API fails."""
    test_addresses = [
        "0x1234567890abcdef1234567890abcdef12345678"
    ]

    with mock.patch('requests.post') as mock_post:
        # Mock the POST request to return a 500 status code
        mock_post.return_value.status_code = 500

        blacklist = screening_client.check_blacklist(test_addresses)

        assert isinstance(blacklist, list), "Result should be a list even if API fails"
        assert len(blacklist) == 0, "Should return an empty list on API failure"
