# Circles Groups: Templates for building groups on Circles

## Type 1: Base Groups

This repository implements a new type of group for the Circles v2 protocol - Base Groups. A Base Group allows a group of trusted members to pool their personal Circles (pCRC) tokens into a shared group currency (gCRC). The group maintains a treasury where all deposited pCRC collateral is held and can be redeemed via transitive transfer for gCRC tokens. This creates a more stable and liquid local currency backed by a diversified pool of personal Circles.

The Base Group contracts extend the Circles v2 groups functionality with optional mint handler. With membership conditions in Base Group on-chain conditions can be enforced for trusting new members (owner can bypass), and BaseTreasury presented as a vertix on a graph allows gCRC to flow over the Circles trust graph without people directly trusting the groups. Groups are deployed through a factory contract that ensures standardized setup and initialization.

## Repository Structure

### Core Contracts (`/src`)

The main implementation consists of several key components:

- **Base Group (`/base-group`)**: The main group contract that consists treasury, minting policy and handler, coordinates membership. Includes:
  - `BaseGroup.sol`: Base group contract implementing group functionality
  - `BaseTreasury.sol`: Holds pCRC collateral and allows its redemption via transitive transfers
  - `BaseMintPolicy.sol`: Base mint policy always allows to mint and burn gCRC
  - `BaseMintHandler.sol`: Handles minting of gCRC against pCRC collateral via transitive transfers
  - `BaseGroupFactory.sol`: Factory contract for standardized deployment of new Base Groups

- **Membership Conditions (`/membership-conditions`)**: Pluggable contracts that enforce requirements for group membership

### Support Code

- **Tests (`/test/base-group`)**: Comprehensive test suite
- **Scripts (`/scripts/base-group`)**: Deployment scripts

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