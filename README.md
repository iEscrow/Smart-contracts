# EscrowTeamTreasury

A Solidity smart contract for managing token vesting for team members, founders, and advisors with a 3-year lock period and 5 vesting milestones.

## 🚀 Quick Start

### Prerequisites

- Node.js (v16 or higher)
- npm or yarn
- Git

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd tresary_contract
   ```

2. **Install dependencies**
   ```bash
   npm install
   ```

3. **Compile contracts**
   ```bash
   npx hardhat compile
   ```

## 📋 Deployment Guide

### Local Deployment (Hardhat Network)

1. **Start local network**
   ```bash
   npx hardhat node
   ```

2. **Deploy contracts**
   ```bash
   npx hardhat run scripts/deploy.js --network localhost
   ```

   This will:
   - Deploy `MockEscrowTokenNoMint` contract
   - Deploy `EscrowTeamTreasury` contract
   - Mint 1B tokens to the owner
   - Fund the treasury
   - Add a test beneficiary
   - Lock allocations

3. **Verify deployment**
   ```bash
   # Check contract addresses
   grep "deployed to:" deployment-output.txt

   # Or run tests
   npm test
   ```

### Production Deployment

For mainnet or testnet deployment:

1. **Configure network** in `hardhat.config.js`
   ```javascript
   networks: {
     mainnet: {
       url: "https://mainnet.infura.io/v3/YOUR_PROJECT_ID",
       accounts: [PRIVATE_KEY]
     }
   }
   ```

2. **Deploy with specific network**
   ```bash
   npx hardhat run scripts/deploy.js --network mainnet
   ```

3. **Verify contracts** (if supported)
   ```bash
   npx hardhat verify --network mainnet <CONTRACT_ADDRESS>
   ```

## 🛠️ Setup Guide

### Environment Configuration

1. **Create `.env` file** (optional, for private keys)
   ```
   PRIVATE_KEY=your_private_key_here
   INFURA_PROJECT_ID=your_infura_id
   ```

2. **Update Hardhat config** for additional networks if needed

### Adding Beneficiaries

After deployment:

```javascript
// Connect to deployed treasury
const treasury = await ethers.getContractAt("EscrowTeamTreasury", treasuryAddress);

// Add beneficiary (before locking)
await treasury.addBeneficiary(beneficiaryAddress, allocationAmount);

// Lock allocations (no more changes allowed)
await treasury.lockAllocations();
```

### Claiming Tokens

```javascript
// Beneficiaries claim their vested tokens
await treasury.claimTokens();

// Check claimable amount
const claimable = await treasury.getClaimableAmount(beneficiaryAddress);
```

# EscrowTeamTreasury

A Solidity smart contract for managing token vesting for team members, founders, and advisors with a 3-year lock period and 5 vesting milestones.

## 🚀 Quick Start

### Prerequisites
- Node.js (v16 or higher)
- npm or yarn
- Git

### Installation
1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd tresary_contract
   ```

2. **Install dependencies**
   ```bash
   npm install
   ```

3. **Compile contracts**
   ```bash
   npx hardhat compile
   ```

## 📋 Deployment Guide

### Local Deployment (Hardhat Network)
1. **Start local network**
   ```bash
   npx hardhat node
   ```

2. **Deploy contracts**
   ```bash
   npx hardhat run scripts/deploy.js --network localhost
   ```

   This deploys the treasury, funds it, and locks allocations.

3. **Verify deployment**
   ```bash
   npm test
   ```

### Production Deployment
Configure network in `hardhat.config.js` and deploy to mainnet/testnet.

## 🛠️ Usage

### Adding Beneficiaries
```javascript
await treasury.addBeneficiary(beneficiaryAddress, allocationAmount);
await treasury.lockAllocations();
```

### Claiming Tokens
```javascript
await treasury.claimTokens();
```

## 📊 Test Coverage
- **100% Statement Coverage**
- **100% Branch Coverage**
- **100% Function Coverage**
- **100% Line Coverage**

Run `npx hardhat coverage` for reports.

## 🔧 Gas Optimization
Optimized for efficiency with unchecked operations and efficient array management.

## 🧪 Testing
Run `npm test` for 90+ passing tests.

## 📚 Documentation
- **Project Progress**: See [project_progress.md](project_progress.md)
- **Detailed Docs**: See [project_document.md](project_document.md)

## 🔒 Security Features
Reentrancy protection, access control, pause mechanism, input validation.

## 📄 License
MIT License.

---

**Quick Deploy Command:**
```bash
npm install && npx hardhat compile && npx hardhat run scripts/deploy.js --network localhost
```

## 🔧 Gas Optimization

The contract has been optimized for gas efficiency:

- **Unchecked Operations**: Used in safe loops to save gas
- **Efficient Array Management**: Swap-and-pop method for removals instead of shifting
- **Minimal Storage Writes**: State variables updated only when necessary
- **Immutable Parameters**: Constants prevent unnecessary computations

Gas usage is optimized for scalability, with O(n) operations noted for large beneficiary counts.

## 🧪 Testing

Run the comprehensive test suite:

```bash
# Run all tests
npm test

# Run with coverage
npx hardhat coverage

# Run specific test
npx hardhat test test/EscrowTeamTreasury.test.js
```

**Test Results**: 61 passing tests with comprehensive edge case coverage including:
- Deployment and funding scenarios
- Beneficiary management (add, update, remove)
- Vesting and claiming at milestone boundaries
- Emergency functions (pause, revoke, withdraw)
- Edge cases (large allocations, multiple beneficiaries, time precision)

## 📚 Documentation

For detailed documentation, see [PROJECT_DOCUMENTATION.md](PROJECT_DOCUMENTATION.md)

- **Contract Details**: In-depth explanation of smart contracts
- **Architecture**: System design and security features
- **API Reference**: Complete function documentation
- **Advanced Usage**: Custom implementations and edge cases

## 🔒 Security Features

- Reentrancy protection
- Access control (owner-only functions)
- Pause/unpause mechanism
- Input validation
- Safe ERC20 operations

## 📊 Contract Addresses

After deployment, contract addresses will be logged to the console. Save them for interaction:

- **Token Contract**: [Address]
- **Treasury Contract**: [Address]

## 🆘 Troubleshooting

**Common Issues:**

- **Out of gas**: Increase gas limit in `hardhat.config.js`
- **Network errors**: Check RPC URL and API keys
- **Compilation errors**: Ensure Solidity version compatibility

**Get Help:**
- Check [PROJECT_DOCUMENTATION.md](PROJECT_DOCUMENTATION.md) for detailed guides
- Review test files for usage examples
- Open an issue in the repository

## 📄 License

MIT License - See contract headers for details.

---

**Quick Deploy Command:**
```bash
npm install && npx hardhat compile && npx hardhat run scripts/deploy.js --network localhost
```
