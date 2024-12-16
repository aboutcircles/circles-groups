import time
import random
from typing import List, Dict, Set, Tuple
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
        self.trusted_accounts = set(self.nethermind_client.get_trusted_by_accounts(
            self.supergroup_address))
        self.current_iteration += 1

    def run_trust_management(self):
        max_offset = settings.update_max_offset
        while True:
            self._update_trusted_list()
            random_offset = random.randint(- max_offset, max_offset)
            time.sleep(settings.update_interval + random_offset)

    def _update_trusted_list(self):
        self.current_iteration += 1

        # Step 1: Fethc All Humans
        list_a = set(self.nethermind_client.get_all_v2_humans())

        # Step 2: Filter Blacklisted
        list_a, list_b = self._filter_blacklisted(list_a, self.trusted_accounts)

        # Step 3: Evaluate Backing for Trusted and Not-Blacklisted Humans

        # Sub-Step 3a: First Check for Backed, Already Trusted Humans
        list_c = set() # Build the list of accounts to trust in the new iteration
        list_d = set() # Keep a list of humans who are currently backing their CRC, for determining new friends
        list_a, list_b, list_c, list_d = self._check_backed_trusted(
            list_a, list_b, list_c, list_d)

        # Stop if we've reached the max trusted limit
        if len(list_c) >= settings.max_trusted:
            self._finalize_trust_list(list_c)
            return

        # Sub-Step 3b: Find Newly Backed Humans (in list A)
        list_a, list_c, list_d = self._check_backed_newly(list_a, list_c, list_d)

        # Stop if we've reached the max trusted limit
        if len(list_c) >= settings.max_trusted:
            self._finalize_trust_list(list_c)
            return

        # Step 4: Trust "Unbacked" Friends

        # Sub-Step 4a: Filter the remaining humans for at least 3 Trust Connections
        #   to the set of current backers
        list_a = self._filter_at_least_three_trust_connections(list_a, list_d)

    def _filter_blacklisted(self, list_a: Set[str], list_b: Set[str]) -> Tuple[Set[str], Set[str]]:
        blacklisted_accounts = set(self.screening_client.get_blacklisted_accounts())
        list_a -= blacklisted_accounts
        list_b -= blacklisted_accounts
        return list_a, list_b

    def _check_backed_trusted(self, list_a: Set[str], list_b: Set[str], list_c: Set[str], list_d: Set[str]) -> Tuple[Set[str], Set[str], Set[str], Set[str]]:
        # copy list b to avoid modifying the list in place while looping
        for account in list_b.copy():
            if self.lbp_indexer_client.is_crc_sufficiently_backed(account):
                list_c.add(account)
                list_d.add(account)
                list_a.discard(account)
                list_b.discard(account)
            elif settings.append_only:
                # when append-only always re-include the existing trust connections (list b)
                list_c.add(account)
                list_a.discard(account)
        return list_a, list_b, list_c, list_d

    def _check_backed_newly(self, list_a: Set[str], list_c: Set[str], list_d: Set[str]) -> Tuple[Set[str], Set[str], Set[str]]:
        for account in list_a.copy():
            if self.lbp_indexer_client.is_crc_sufficiently_backed(account):
                list_c.add(account)
                list_d.add(account)
                list_a.discard(account)
        return list_a, list_c, list_d

    def _filter_at_least_three_trust_connections(self, list_a: Set[str], list_d: Set[str]) -> Set[str]:
        for account in list_a.copy():
            trusted_by = self.nethermind_client.get_trusted_by_accounts(account)
            if len(trusted_by.intersection(list_d)) < 3:
                list_a.discard(account)
        return list_a

    def _finalize_trust_list(self, list_c: Set[str]):
        # Determine changes
        current_trusted_set = self.trusted_accounts
        delta_joiners = list_c - current_trusted_set
        delta_leavers = current_trusted_set - list_c

        # Apply threshold
        # TODO continue to apply and execute
