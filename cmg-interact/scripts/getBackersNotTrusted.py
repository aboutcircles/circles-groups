import requests
from getBackers import BackerFetcher
from getTrusted import Truster

def get_untrusted_backers(address: str) -> set[str]:
    fetcher = BackerFetcher('https://rpc.aboutcircles.com')
    truster = Truster('https://rpc.aboutcircles.com')

    backers = fetcher.fetch_backers()
    trusted = truster.get_trusters(address)

    return backers - trusted

if __name__ == "__main__":
    import sys

    if len(sys.argv) != 2:
        print("Usage: python script.py <address>")
        sys.exit(1)

    address = sys.argv[1]
    untrusted = get_untrusted_backers(address)

    print(f"Number of untrusted backers: {len(untrusted)}")
    print("Untrusted backers:")
    print(" ".join(sorted(untrusted)))
