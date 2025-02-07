
class Truster:
    def __init__(self, rpc_url):
        self.rpc_url = rpc_url

    def get_trusters(self, truster_address: str) -> set[str]:
        """Get all accounts that a given address trusts."""
        query = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "circles_query",
            "params": [
                {
                    "Namespace": "V_CrcV2",
                    "Table": "TrustRelations",
                    "Columns": ["trustee"],
                    "Filter": [
                        {
                            "Type": "FilterPredicate",
                            "FilterType": "Equals",
                            "Column": "truster",
                            "Value": truster_address.lower()
                        }
                    ],
                    "Order": [
                        {"Column": "blockNumber", "SortOrder": "DESC"}
                    ],
                    "Limit": 1000
                }
            ]
        }

        response = requests.post(self.rpc_url, json=query)
        response.raise_for_status()

        result = response.json().get("result", {})
        if 'columns' not in result or 'rows' not in result:
            raise ValueError("Unexpected response structure")

        keys = result['columns']
        rows = result['rows']

        try:
            trustee_index = keys.index('trustee')
        except ValueError:
            return set()

        trustees = set()
        for row in rows:
            trustees.add(row[trustee_index])

        return trustees

if __name__ == "__main__":
    import sys
    import requests

    if len(sys.argv) != 2:
        print("Usage: python script.py <truster_address>")
        sys.exit(1)

    truster = Truster('https://rpc.aboutcircles.com')
    trusters = truster.get_trusters(sys.argv[1])
    print(f"Addresses trusted by {sys.argv[1]}:")
    for trustee in sorted(trusters):
        print(trustee)
