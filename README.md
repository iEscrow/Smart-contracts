# EscrowTeamTreasury

A gas-optimized Solidity smart contract for managing token vesting for team members, founders, and advisors. Features a 3-year lock period followed by 5 vesting milestones (20% every 6 months) with 1 billion ESCROW tokens total allocation.

## 🚀 Quick Start

### Prerequisites
- [Foundry](https://book.getfoundry.sh/getting-started/installation) (forge, anvil, etc.)
- Git

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd tresary_contract
   ```

2. **Install dependencies**
   ```bash
   forge install
   ```

3. **Build contracts**
   ```bash
   forge build
   ```

## 🧪 Testing

Run the comprehensive test suite:
```bash
# Run all tests
forge test

# Run with verbose output
forge test -vvv

# Run specific test file
forge test --match-contract EscrowTeamTreasuryTest
```

**Test Results**: ✅ 54 tests passing (updated after optimizations)

## 📋 Contract Overview

### Key Features
- **Total Allocation**: 1 billion ESCROW tokens (1% of 100B supply)
- **Vesting Schedule**: 3-year lock + 5 milestones (20% every 6 months)
- **Gas Optimized**: Removed unnecessary features for efficiency
- **Security**: Access control, input validation, SafeERC20 operations

### Contract Architecture
- `EscrowTeamTreasury.sol`: Main vesting contract
- `MockEscrowToken.sol`: Test token implementation
- `MockEscrowTokenNoMint.sol`: Token without constructor minting

## 🚀 Deployment

### Local Development
```bash
# Start local anvil node
anvil

# Deploy in another terminal
forge create --rpc-url http://localhost:8545 --private-key 0x... contracts/EscrowTeamTreasury.sol:EscrowTeamTreasury --constructor-args <TOKEN_ADDRESS>
```

### Production Deployment
```bash
# Deploy to mainnet (update foundry.toml)
forge create --rpc-url $MAINNET_RPC --private-key $PRIVATE_KEY contracts/EscrowTeamTreasury.sol:EscrowTeamTreasury --constructor-args <TOKEN_ADDRESS>
```

## 🛠️ Usage

### Adding Beneficiaries
```solidity
// Add beneficiary (before locking)
await treasury.addBeneficiary(beneficiaryAddress, allocationAmount);

// Lock allocations (no more changes allowed)
await treasury.lockAllocations();
```

### Claiming Tokens
```solidity
// Beneficiaries claim their vested tokens
await treasury.claimFor(beneficiaryAddress);

// Check claimable amount
const claimable = await treasury.getClaimableAmount(beneficiaryAddress);
```

### View Functions
```solidity
// Get beneficiary details
const info = await treasury.getBeneficiaryInfo(beneficiaryAddress);

// Get all beneficiaries
const [addresses, allocations, claimed, active] = await treasury.getAllBeneficiaries();

// Get vesting schedule
const [startTime, firstUnlock, currentMilestone, totalMilestones, intervalDays] = await treasury.getVestingSchedule();
```

## 📊 Gas Optimizations

The contract has been optimized for gas efficiency:

- **Removed Complexity**: Eliminated pause/unpause, emergency functions
- **Simplified Struct**: Removed unused `lastClaimMilestone` field
- **Optimized Views**: Removed dynamic array creation in `getVestingSchedule`
- **Clean Architecture**: Streamlined functions and state variables
- **Efficient Loops**: Used unchecked operations where safe

## 🔒 Security Features

- **Access Control**: Owner-only admin functions
- **Input Validation**: All functions validate addresses and amounts
- **Safe Operations**: SafeERC20 for token transfers
- **Overflow Protection**: Proper allocation limits and checks

## 📚 Documentation

- **Technical Details**: See [project_document.md](project_document.md)
- **Contract Addresses**: Update after deployment
- **API Reference**: All functions documented in code

## 🏗️ Project Structure

```
tresary_contract/
├── contracts/          # Smart contracts
│   ├── EscrowTeamTreasury.sol
│   ├── MockEscrowToken.sol
│   └── MockEscrowTokenNoMint.sol
├── test/              # Test files
│   └── EscrowTeamTreasury.t.sol
├── lib/               # Foundry dependencies
├── foundry.toml       # Foundry configuration
└── README.md          # This file
```

## 🔧 Development

### Adding Tests
```bash
# Create new test
forge test --match-test testNewFeature
```

### Code Coverage
```bash
forge coverage
```

## 📄 License

MIT License - See contract headers for details.

---

