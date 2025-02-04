import json
from algorithm.trust_management import TrustManagementAlgorithm, PollingService
from clients.nethermind import NethermindClient
from clients.screening import ScreeningClient
from config.settings import settings
# from config.SuperGroupABI import SUPERGROUP_CONTRACT_ABI

def main():

    # Initialize clients using the settings instance
    nethermind_client = NethermindClient(settings.nethermind_rpc_url)
    screening_client = ScreeningClient(settings.screening_url)

    # Initialize algorithm
    algorithm = TrustManagementAlgorithm(
        nethermind_client,
        screening_client,
        settings.supergroup_address,
        private_key=settings.private_key,
        supergroup_contract_address=settings.supergroup_address,  # Use the same address
    )

    algorithm.run_trust_management()

    # Initialize PollingService
    polling_service = PollingService(nethermind_client)

    # Start the polling service with the TrustManagementAlgorithm
    polling_service.start_polling(algorithm)

if __name__ == "__main__":
    main()
