import pytest
from src.clients.nethermind import NethermindClient
from src.config.settings import settings

@pytest.fixture(scope="module")
def nethermind_client():
    """Fixture to create a NethermindClient instance."""
    client = NethermindClient(settings.nethermind_rpc_url)
    yield client

def test_get_all_humans_with_pagination(nethermind_client):
    """Test the get_all_humans_with_pagination method."""
    limit = 1000
    human_addresses = nethermind_client.get_all_humans_with_pagination(limit=limit)

    assert isinstance(human_addresses, list), "Result should be a list"
    assert len(human_addresses) > 0, "Should return at least one human account"
    assert all(isinstance(address, str) for address in human_addresses), "All elements should be strings"

def test_get_all_humans_with_pagination_with_limit(nethermind_client):
    """Test the get_all_humans_with_pagination method with a limit of 10."""
    limit = 10
    human_accounts = nethermind_client.get_all_humans_with_pagination(limit=limit)

    assert isinstance(human_accounts, list), "Result should be a list"
    assert len(human_accounts) == limit, "Should return a list of length limit"

def test_get_all_v2_humans(nethermind_client):
    """Test the get_all_v2_humans method."""
    human_addresses = nethermind_client.get_all_v2_humans()

    assert isinstance(human_addresses, list), "Result should be a list"
    assert len(human_addresses) > 0, "Should return at least one human account"
    assert all(isinstance(address, str) for address in human_addresses), "All elements should be strings"
