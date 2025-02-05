# CMG Interaction CLI

A command line tool for interacting with CMG smart contracts on Gnosis Chain.

## Installation

1. Clone this repository:
```bash
git clone https://github.com/aboutcircles/circles-groups
cd ces-interact
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
python interact_cmg.py get-owner
```

Get service address:
```bash
python interact_cmg.py get-service
```

Check if address is authorized operator:
```bash
python interact_cmg.py is-authorized-operator <address>
```

### Modify Contract State

Set service address:
```bash
python interact_cmg.py set-service <service_address>
```

Trust batch of addresses:
```bash
python interact_cmg.py trust-batch <address1> <address2> ... <expiry_timestamp>
```

## Examples

Trust multiple addresses until timestamp 1735689600 (Jan 1, 2025):
```bash
python interact_cmg.py trust-batch 0x123... 0x456... 0x789... 1735689600
```

## Requirements

- Python 3.7+
- Web3.py
- Click
- python-dotenv
