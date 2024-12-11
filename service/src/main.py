from algorithm.trust_management import TrustManagementAlgorithm
from clients.nethermind import NethermindClient
from clients.lbp_indexer import LBPIndexerClient
from clients.screening import ScreeningClient
from config.settings import settings

def main():
    # Initialize clients using the settings instance
    nethermind_client = NethermindClient(settings.nethermind_rpc_url)
    lbp_indexer_client = LBPIndexerClient(settings.lbp_indexer_url)
    screening_client = ScreeningClient(settings.screening_url)

    # Initialize algorithm
    algorithm = TrustManagementAlgorithm(
        nethermind_client,
        lbp_indexer_client,
        screening_client,
        settings.supergroup_address
    )

    algorithm.initialize()
    algorithm.run_trust_management()

if __name__ == "__main__":
    main()
