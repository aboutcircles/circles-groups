# CMG Interaction CLI

A command line tool for interacting with CMG smart contracts on Gnosis Chain.

## Installation

1. Clone this repository:
```bash
git clone https://github.com/aboutcircles/circles-groups
cd circles-groups/cmg-interact
```

2. Create and activate a virtual environment:
```bash
python3 -m venv venv
source venv/bin/activate  # Linux/Mac
# OR
venv\Scripts\activate  # Windows (not tested)
```

3. Install dependencies:
```bash
pip3 install -r requirements.txt
```

4. Set up environment variables:
```bash
cp scripts/.env.example scripts/.env
```

Edit `.env` and add:
- Your RPC URL for Gnosis Chain
- Your private key for signing transactions

## Usage

The CLI provides the following commands:

### View Contract Information

Get contract owner:
```bash
python ./scripts/interact_cmg.py get-owner
```

Get service address:
```bash
python ./scripts/interact_cmg.py get-service
```

Get membership conditions:
```bash
python ./scripts/interact_cmg.py get-membership-conditions
```

Get mint and redemption handler addresses:
```bash
python ./scripts/interact_cmg.py get-handlers
```

Get minimal deposit amount:
```bash
python ./scripts/interact_cmg.py get-minimal-deposit
```

Get fee collection address:
```bash
python ./scripts/interact_cmg.py get-fee-collection
```

### Contract Management

Set service address:
```bash
python ./scripts/interact_cmg.py set-service <service_address>
```

Set mint handler address:
```bash
python ./scripts/interact_cmg.py set-mint-handler <mint_handler_address>
```

Set redemption handler address:
```bash
python ./scripts/interact_cmg.py set-redemption-handler <redemption_handler_address>
```

Set minimal deposit amount:
```bash
python ./scripts/interact_cmg.py set-minimal-deposit <amount>
```

Set fee collection address:
```bash
python ./scripts/interact_cmg.py set-fee-collection <fee_collection_address>
```

Enable/disable membership condition:
```bash
python ./scripts/interact_cmg.py set-membership-condition <condition_address> <true|false>
```

### Trust Management

Trust a single address:
```bash
python ./scripts/interact_cmg.py trust <address> [--expiry TIMESTAMP]
```

Trust multiple addresses with conditions:
```bash
python ./scripts/interact_cmg.py trust-batch-with-conditions <address1> <address2> ... [--expiry TIMESTAMP]
```

Sync trust relationships to mint handler:
```bash
python ./scripts/interact_cmg.py sync-trust <address1> [address2 ...]
```

### Advanced Features

Set advanced usage flag:
```bash
python ./scripts/interact_cmg.py set-advanced-usage-flag <flag>
```

Update metadata digest:
```bash
python ./scripts/interact_cmg.py update-metadata-digest <digest>
```

Register short name:
```bash
python ./scripts/interact_cmg.py register-short-name
```

Register short name with nonce:
```bash
python ./scripts/interact_cmg.py register-short-name-with-nonce <nonce>
```

### Redemption Operations

Find available collateral:
```bash
python ./scripts/interact_cmg.py find-collateral <group_address> <amount> [--partial]
```

Redeem collateral:
```bash
python ./scripts/interact_cmg.py redeem <group_address> <redemption_id1> <redemption_value1> [<redemption_id2> <redemption_value2> ...]
```

Sync valid collateral:
```bash
python ./scripts/interact_cmg.py sync-valid-collateral <collateral_id1> [collateral_id2 ...]
```

## Requirements

- Python 3.7+
- Web3.py
- Click
- python-dotenv
