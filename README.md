# Circles Groups: Templates for building groups on Circles

## Type 1: Core Members Groups

This repository implements a new type of group for the Circles v2 protocol - Core Members Groups (CMG). A CMG allows a group of trusted core members to pool their personal Circles (pCRC) tokens into a shared group currency (gCRC). The group maintains a vault where all deposited pCRC collateral is held and can be redeemed by burning gCRC tokens. This creates a more stable and liquid local currency backed by a diversified pool of personal Circles.

The CMG contracts extend the base Circles v2 groups functionality with optional mint and redemption handlers. With membership conditions in CMG on-chain conditions can be enforced for trusting new core members (owner can bypass), and integrated liquidity provision helper contract to allow gCRC to flow over the Circles trust graph without people directly trusting the groups. Groups are deployed through a factory contract that ensures standardized setup and initialization. (There are deprecated helper contracts referencing the initial upgradeable versions, but these do not form part of the final code base).

## Repository Structure

### Core Contracts (`/src`)

The main implementation consists of several key components:

- **Core Members Group (`/core-members-group`)**: The main group contract that coordinates membership, minting policy and redemptions. Includes:
  - `CoreMembersGroup.sol`: Base contract implementing group functionality
  - `CMGMintHandler.sol`: Handles minting of gCRC against pCRC collateral
  - `CMGRedemptionHandler.sol`: Manages redemption of gCRC back to collateral
  - `CMGFactory.sol`: Factory contract for standardized deployment of new CMGs

- **Redemption Operator (`/redemption-operator`)**: Helper contract that executes redemptions by finding and claiming available collateral

- **Liquidity Provider (`/liquidity-provider`)**: Contracts that help provide liquidity to CMGs over the Circles trust graph, as at this stage (in the wallets) we discourage people to trust groups directly.

- **Membership Conditions (`/membership-conditions`)**: Pluggable contracts that enforce requirements for core membership

### Support Code

- **Tests (`/test`)**: Comprehensive test suite with mocked Circles v2 dependencies
- **Scripts (`/scripts`)**: Deployment and interaction scripts
- **Interaction CLI (`/cmg-interact`)**: Python CLI for interacting with deployed CMGs

## Setup & Development

The repository uses Foundry for development. Key commands:

```shell
# Install dependencies
forge install

# Run tests
forge test

# Build contracts
forge build
```

For deploying and interacting with contracts, see deployment scripts in `/scripts` and the interaction CLI in `/cmg-interact`.
