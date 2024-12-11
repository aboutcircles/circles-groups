import time
import random
from typing import List, Dict, Set
from web3 import Web3
from clients.nethermind import NethermindClient
from clients.lbp_indexer import LBPIndexerClient
from clients.screening import ScreeningClient
from config.settings import settings

class TrustManagementAlgorithm:
    def __init__(
        self,
        nethermind_client: NethermindClient,
        lbp_indexer_client: LBPIndexerClient,
        screening_client: ScreeningClient,
        supergroup_address: str
    ):
        self.nethermind_client = nethermind_client
        self.lbp_indexer_client = lbp_indexer_client
        self.screening_client = screening_client
        self.supergroup_address = supergroup_address
        self.current_iteration = 0
        self.trusted_accounts = set() # load during initialisation

    def initialize(self):
        # Fetch the current list of trusted accounts by the supergroup from Nethermind
        self.trusted_accounts = set(self.nethermind_client.get_trusted_accounts(
            self.supergroup_address))
        self.current_iteration += 1

    def run_trust_management(self):
        max_offset = settings.update_max_offset
        while True:
            random_offset = random.randint(- max_offset, max_offset)
