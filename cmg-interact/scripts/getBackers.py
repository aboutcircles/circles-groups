import requests

class BackerFetcher:
    def __init__(self, rpc_url):
        self.rpc_url = rpc_url

    def fetch_backers(self) -> set[str]:
        params = [
            {
                "Namespace": "CrcV2",
                "Table": "CirclesBackingCompleted",
                "Limit": 1000,
                "Columns": [],
                "Filter": [],
                "Order": [
                    {"Column": "blockNumber", "SortOrder": "DESC"},
                    {"Column": "transactionIndex", "SortOrder": "DESC"},
                    {"Column": "logIndex", "SortOrder": "DESC"}
                ]
            }
        ]
        result = requests.post(self.rpc_url, json={
            "jsonrpc": "2.0",
            "method": "circles_query",
            "params": params,
            "id": 1
        }).json()

        if 'columns' not in result['result'] or 'rows' not in result['result']:
            raise ValueError("Unexpected response structure")

        keys = result['result']['columns']
        rows = result['result']['rows']

        try:
            backer_index = keys.index('backer')
        except ValueError:
            raise ValueError("Backer key not found in response columns")

        backers = [row[backer_index] for row in rows]
        return set(backers)

if __name__ == "__main__":
    fetcher = BackerFetcher('https://rpc.aboutcircles.com')
    backers = fetcher.fetch_backers()
    print(f"Total number of backers: {len(backers)}")
    print(" ".join(sorted(backers)))
