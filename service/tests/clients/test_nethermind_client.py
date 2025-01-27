import pytest
from web3 import Web3
from src.clients.nethermind import NethermindClient
from src.config.settings import settings


@pytest.fixture(scope="module")
def nethermind_client():
    """Fixture to create a NethermindClient instance."""
    client = NethermindClient(settings.nethermind_rpc_url)
    yield client


def test_fetch_backers(nethermind_client):
    """Test the fetch_backers method."""
    backers = nethermind_client.fetch_backers()

    assert isinstance(backers, list), "Result should be a list"
    assert len(backers) > 0, "Should return at least one backer"
    assert all(isinstance(backer, str) for backer in backers), "All elements should be strings"


def test_fetch_group_trust_relations(nethermind_client):
    """Test the fetch_group_trust_relations method."""
    super_group_address =  settings.supergroup_address
    trust_relations = nethermind_client.fetch_group_trust_relations(super_group_address)

    assert isinstance(trust_relations, list), "Result should be a list"
    assert len(trust_relations) >= 0, "Should return a list of trust relations (could be empty)"
    assert all(isinstance(trustee, str) for trustee in trust_relations), "All elements should be strings"


def test_get_all_humans_with_pagination(nethermind_client):
    """Test the get_all_humans_with_pagination method."""
    limit = 1000
    human_addresses = nethermind_client.get_all_humans_with_pagination(limit=limit)

    assert isinstance(human_addresses, set), "Result should be a set"
    assert len(human_addresses) > 0, "Should return at least one human account"
    assert all(Web3.is_address(address) for address in human_addresses), "All elements should be valid Ethereum addresses"


def test_get_all_humans_with_pagination_with_limit(nethermind_client):
    """Test the get_all_humans_with_pagination method with a limit of 10."""
    limit = 10
    human_addresses = nethermind_client.get_all_humans_with_pagination(limit=limit)

    assert isinstance(human_addresses, set), "Result should be a set"
    assert len(human_addresses) <= limit, "Should return a set with at most 'limit' entries"
    assert all(Web3.is_address(address) for address in human_addresses), "All elements should be valid Ethereum addresses"


def test_get_all_v2_humans(nethermind_client):
    """Test the get_all_v2_humans method."""
    human_addresses = nethermind_client.get_all_v2_humans()

    assert isinstance(human_addresses, set), "Result should be a set"
    assert len(human_addresses) > 0, "Should return at least one human account"
    assert all(Web3.is_address(address) for address in human_addresses), "All elements should be valid Ethereum addresses"


def test_reset_and_flush(nethermind_client):
    """Test the reset and flush methods."""
    # Test cache reset
    nethermind_client.cache_trusted_by = {"key": "value"}
    nethermind_client.reset()
    assert nethermind_client.cache_trusted_by == {}, "Cache should be cleared after reset"

    # Test cache flush
    nethermind_client.cache_trusted_by = {"key": "value"}
    nethermind_client.flush()
    assert nethermind_client.cache_trusted_by == {}, "Cache should be cleared after flush"
