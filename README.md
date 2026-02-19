# EVM RWA Treasury Tokenization

A complete Solidity-based Real-World Asset (RWA) treasury tokenization protocol inspired by Ondo Finance's OUSG tokenized short-term US Treasuries product. This protocol enables tokenization of off-chain treasury assets with yield accrual, compliance features, and upgradeable architecture.

## 📋 Table of Contents

- [Features](#features)
- [Architecture](#architecture)
- [Project Structure](#project-structure)
- [Setup](#setup)
- [Testing](#testing)
- [Deployment](#deployment)
- [Contact](#contact)

## ✨ Features

### Core Functionality

- **Yield-Bearing Tokens**: Two token models:
  - **OUSG-style (Appreciating)**: Token balance stays fixed, price/NAV increases over time to reflect yield
  - **rOUSG-style (Rebasing)**: Token price stays ~$1, balances increase daily to reflect yield accrual
- **Minting & Redemption**: Permissioned minting when off-chain assets are deposited, redemption with off-chain payout signaling
- **Yield Accrual**: Configurable APY (default 4%) with daily/periodic yield updates
- **Compliance**: Whitelist/blacklist functionality for KYC/AML compliance
- **Access Control**: Role-based access control (MINTER, REDEEMER, PAUSER, ORACLE, ADMIN)
- **Upgradeability**: UUPS proxy pattern for implementation upgrades
- **Pausability**: Emergency pause functionality for all operations

### Technical Features

- **Price Oracle**: Mock oracle for NAV/price updates (production-ready for Chainlink integration)
- **Transfer Restrictions**: Enforceable whitelist/blacklist on transfers
- **Gas Optimized**: Efficient storage and computation patterns
- **Security**: Reentrancy guards, access control, overflow protection

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Users / Investors                        │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│              UUPS Proxy (TreasuryToken)                     │
│  ┌─────────────────────────────────────────────────────┐  │
│  │         Implementation Contract                     │  │
│  │  - mint() / redeem()                                │  │
│  │  - yield accrual                                    │  │
│  │  - whitelist/blacklist                              │  │
│  │  - pause/unpause                                    │  │
│  └─────────────────────────────────────────────────────┘  │
└──────┬──────────────┬──────────────┬────────────────────────┘
       │              │              │
       ▼              ▼              ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│ Price Oracle │ │ Access Control│ │ MockUSDC     │
│  (NAV/Price) │ │   (Roles)     │ │ (Underlying) │
└──────────────┘ └──────────────┘ └──────────────┘
```

### Contract Components

1. **TreasuryToken**: Main appreciating token (OUSG-style) - balance fixed, price increases
2. **RebasingTreasuryToken**: Rebasing variant (rOUSG-style) - price fixed, balance increases
3. **TreasuryPriceOracle**: Price oracle for NAV updates and yield rate management
4. **MockUSDC**: Mock stablecoin for testing mint/redemption flows

### Token Models

#### OUSG-style (Appreciating Token)
- Token balance remains constant
- Price/NAV per token increases over time
- Formula: `price = initialPrice * (1 + yieldRate * timeElapsed / 365 days)`
- Users see value appreciation through price increase

#### rOUSG-style (Rebasing Token)
- Token price stays constant (~$1)
- Token balances increase daily via rebasing
- Formula: `balance = scaledBalance * rebaseIndex`
- Users see value appreciation through balance increase

## 📁 Project Structure

```
evm-rwa-treasury-tokenization/
├── contracts/
│   ├── interfaces/
│   │   ├── ITreasuryToken.sol
│   │   └── ITreasuryPriceOracle.sol
│   ├── treasury/
│   │   ├── TreasuryToken.sol
│   │   └── RebasingTreasuryToken.sol
│   ├── oracle/
│   │   └── TreasuryPriceOracle.sol
│   └── mocks/
│       └── MockUSDC.sol
├── scripts/
│   └── deploy.js
├── test/
│   ├── TreasuryToken.test.js
│   └── RebasingTreasuryToken.test.js
├── hardhat.config.js
├── helper-config.js
├── package.json
└── README.md
```

## 🚀 Setup

### Prerequisites

- Node.js (v16 or higher)
- npm or yarn
- Git

### Installation

1. Navigate to the project directory:
```bash
cd evm-rwa-treasury-tokenization-1/evm-rwa-treasury-tokenization
```

2. Install dependencies:
```bash
npm install
# or
yarn install
```

3. Create a `.env` file (optional, for testnet deployment):
```bash
PRIVATE_KEY=your_private_key_here
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/your_key
ETHERSCAN_API_KEY=your_etherscan_api_key
```

4. Compile the contracts:
```bash
npx hardhat compile
```

## 🧪 Testing

Run the complete test suite:

```bash
npx hardhat test
```

Run specific test files:

```bash
npx hardhat test test/TreasuryToken.test.js
npx hardhat test test/RebasingTreasuryToken.test.js
```

Run tests with gas reporting:

```bash
REPORT_GAS=true npx hardhat test
```

### Test Coverage

The test suite covers:
- ✅ Contract deployment and initialization
- ✅ Minting and redemption flows
- ✅ Yield accrual mechanisms
- ✅ Whitelist/blacklist enforcement
- ✅ Transfer restrictions
- ✅ Pausability
- ✅ Upgradeability (UUPS proxy)
- ✅ Role-based access control
- ✅ Edge cases (zero amounts, unauthorized actions, etc.)

## 🚢 Deployment

### Local Network

1. Start a local Hardhat node:
```bash
npx hardhat node
```

2. In another terminal, deploy to localhost:
```bash
npx hardhat run scripts/deploy.js --network localhost
```

### Testnet Deployment (Sepolia)

1. Ensure your `.env` file is configured with:
   - `PRIVATE_KEY`: Your wallet private key
   - `SEPOLIA_RPC_URL`: Sepolia RPC endpoint
   - `ETHERSCAN_API_KEY`: Etherscan API key (for verification)

2. Deploy to Sepolia:
```bash
npx hardhat run scripts/deploy.js --network sepolia
```

3. Verify contracts (optional):
```bash
npx hardhat verify --network sepolia <CONTRACT_ADDRESS> <CONSTRUCTOR_ARGS>
```

## 📧 Contact

- Telegram: https://t.me/rouncey
- Twitter: https://x.com/rouncey_

