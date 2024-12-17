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
        set_a = set(self.nethermind_client.get_all_v2_humans())

        # Step 2: Filter Blacklisted
        set_a, set_b = self._filter_blacklisted(set_a, self.trusted_accounts)

        # Step 3: Evaluate Backing for Trusted and Not-Blacklisted Humans

        # Sub-Step 3a: First Check for Backed, Already Trusted Humans
        set_c = set() # Build the list of accounts to trust in the new iteration
        set_d = set() # Keep a list of humans who are currently backing their CRC, for determining new friends
        set_a, set_b, set_c, set_d = self._check_backed_trusted(
            set_a, set_b, set_c, set_d)

        # Stop if we've reached the max trusted limit
        if len(set_c) >= settings.max_trusted:
            self._finalize_trust_list(set_c)
            return

        # Sub-Step 3b: Find Newly Backed Humans (in list A)
        set_a, set_c, set_d = self._check_backed_newly(set_a, set_c, set_d)

        # Stop if we've reached the max trusted limit
        if len(set_c) >= settings.max_trusted:
            self._finalize_trust_list(set_c)
            return

        # Step 4: Trust "Unbacked" Friends

        # Sub-Step 4a: Filter the remaining humans for at least 3 Trust Connections
        set_a = self._filter_at_least_three_trust_connections(set_a, set_d)

        # Sub-Step 4b: Reconsider First Previously Trusted Accounts as possible friends (list A)
        if not settings.append_only:
            # with append_only we have already included all not-blacklisted, previously trusted humans
            set_a, set_b, set_c = self._reconsider_previously_trusted_as_friends(set_a, set_b, set_c)

    def _filter_blacklisted(self, set_a: Set[str], set_b: Set[str]) -> Tuple[Set[str], Set[str]]:
        blacklisted_accounts = set(self.screening_client.get_blacklisted_accounts())
        set_a -= blacklisted_accounts
        set_b -= blacklisted_accounts
        return set_a, set_b

    def _check_backed_trusted(self, set_a: Set[str], set_b: Set[str], set_c: Set[str], set_d: Set[str]) -> Tuple[Set[str], Set[str], Set[str], Set[str]]:
        # copy list b to avoid modifying the list in place while looping
        for account in set_b.copy():
            if self.lbp_indexer_client.is_crc_sufficiently_backed(account):
                set_c.add(account)
                set_d.add(account)
                set_a.discard(account)
                set_b.discard(account)
            elif settings.append_only:
                # when append-only always re-include the existing trust connections (list b)
                set_c.add(account)
                set_a.discard(account)
        return set_a, set_b, set_c, set_d

    def _check_backed_newly(self, set_a: Set[str], set_c: Set[str], set_d: Set[str]) -> Tuple[Set[str], Set[str], Set[str]]:
        for account in set_a.copy():
            if self.lbp_indexer_client.is_crc_sufficiently_backed(account):
                set_c.add(account)
                set_d.add(account)
                set_a.discard(account)
        return set_a, set_c, set_d

    def _filter_at_least_three_trust_connections(self, set_a: Set[str], set_d: Set[str]) -> Set[str]:
        # initialize a dictionary to tally
        for account in set_a.copy():
            trusted_by = self.nethermind_client.get_trusted_by_accounts(account)
            if len(trusted_by.intersection(set_d)) < 3:
                set_a.discard(account)
        return set_a

    def _reconsider_previously_trusted_as_friends(self, set_a: Set[str], set_b: Set[str], set_c: Set[str]) -> Tuple[Set[str], Set[str], Set[str]]:
        for account in set_b.intersection(set_a):
            set_c.add(account)
            set_a.discard(account)
            set_b.discard(account)

        return set_a, set_b, set_c

    def _finalize_trust_list(self, set_c: Set[str]):
        # Determine changes
        current_trusted_set = self.trusted_accounts
        delta_joiners = set_c - current_trusted_set
        delta_leavers = current_trusted_set - set_c

        # Apply threshold
        # TODO continue to apply and execute
