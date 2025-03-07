import os
from dotenv import load_dotenv
import json
import click
from web3 import Web3
import csv
from datetime import datetime
from typing import Dict, List, Optional

class CMGLandscapeAnalyzer:
    """Analyzes Core Members Groups implementation landscape"""

    def __init__(self):
        # Load environment variables
        load_dotenv()

        # Get repo root path
        repo_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        print(f"DEBUG: repo_root path is {repo_root}")

        # Connect to Gnosis Chain
        self.w3 = Web3(Web3.HTTPProvider(os.getenv("RPC_URL_GNOSIS")))

        # Load proxy ABI
        self.load_abis(repo_root)

        # Known deployer addresses
        self.known_deployers = [
            # "0x2F1808520Fb68F7815dcF5ceFDb87fBAC0fc62E5", # CES Supergroup deployer, 27 January 2025, not covered
            "0x55785b41703728f1F1F05E77e22B13c3FCc9ce65", # First created 3 Feb 2025
            # "0xC108D57691f9235468D564D0Ad38e24988d93084", unknown
            # "0xCFb45206d6C9442ba93D723B14Db99fb382d7DEc", unknown
            # "0xB9F6f0dB7f59907964A29f3AD935b2ac2F6abEdb", unknwon
            "0xFEca40Eb02FB1f4F5F795fC7a03c1A27819B1Ded"  # CMG Deployer v0.1.0-preview, 26 Feb 2025
        ]

    def load_abis(self, repo_root: str):
        """Load required contract ABIs"""
        abi_path = os.path.join(repo_root, "export-abis/UpgradeableRenounceableProxy-virtual.json")
        with open(abi_path) as f:
            self.proxy_abi = json.load(f)

    def analyze_group(self, group_address: str) -> Dict:
        """Analyze a single CMG and return its details"""
        group_address = Web3.to_checksum_address(group_address)

        # Create proxy contract instance
        proxy = self.w3.eth.contract(address=group_address, abi=self.proxy_abi)

        # Get implementation
        impl_address = proxy.functions.implementation().call()

        # Get implementation code hash
        impl_code = self.w3.eth.get_code(impl_address)
        impl_hash = Web3.keccak(impl_code).hex()

        return {
            "group_address": group_address,
            "implementation": impl_address,
            "implementation_hash": impl_hash
        }

    def export_csv(self, results: List[Dict], filename: Optional[str] = None):
        """Export results to CSV"""
        if not filename:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = f"cmg_landscape_{timestamp}.csv"

        repo_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        output_path = os.path.join(repo_root, filename)

        with open(output_path, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=results[0].keys())
            writer.writeheader()
            writer.writerows(results)

        return filename

@click.group()
def cli():
    """CMG Landscape Analysis Tools"""
    pass

@cli.command()
@click.option("--output", "-o", help="Output CSV filename")
def analyze_all(output):
    """Analyze all known CMGs"""
    analyzer = CMGLandscapeAnalyzer()

    # Get groups from environment
    groups = json.loads(os.getenv("ALL_TRACKED_GROUPS", "[]"))

    results = []
    for group in groups:
        try:
            result = analyzer.analyze_group(group)
            results.append(result)
            click.echo(f"Analyzed group {group}")
        except Exception as e:
            click.echo(f"Error analyzing group {group}: {e}")

    # Export results
    if results:
        filename = analyzer.export_csv(results, output)
        click.echo(f"Results exported to {filename}")
    else:
        click.echo("No results to export")

@cli.command()
@click.argument("group_address")
def analyze_group(group_address):
    """Analyze a single CMG"""
    analyzer = CMGLandscapeAnalyzer()
    try:
        result = analyzer.analyze_group(group_address)
        click.echo(json.dumps(result, indent=2))
    except Exception as e:
        click.echo(f"Error analyzing group {group_address}: {e}")

if __name__ == "__main__":
    cli()
