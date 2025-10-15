# EscrowTeamTreasury Project Documentation

## Overview

The EscrowTeamTreasury project is a Solidity-based smart contract system for managing token vesting for team members, founders, and advisors. It implements a flexible vesting schedule with a 3-year lock period followed by a 2-year release period with 5 milestones (20% every 6 months).

### Project Structure

```
tresary_contract/
├── contracts/
│   ├── ERC20Mock.sol              # Mock ERC20 token for testing
│   ├── EscrowTeamTreasury.sol     # Main treasury contract (585 lines)
│   └── MockEscrowTokenNoMint.sol  # Alternative mock token without initial mint
├── test/
│   └── EscrowTeamTreasury.test.js # Comprehensive test suite (736 lines)
├── scripts/
│   └── deploy.js                  # Deployment script
├── hardhat.config.js              # Hardhat configuration
├── package.json                   # Project dependencies and scripts
└── .gitignore                     # Git ignore rules
```

### Architecture

- **Framework**: Hardhat 2.26.3
- **Solidity Version**: 0.8.20
- **Testing Framework**: Chai, Mocha
- **Dependencies**:
  - OpenZeppelin Contracts 5.4.0
  - Ethers.js 6.15.0
  - Hardhat Toolbox

## Smart Contracts

### 1. EscrowTeamTreasury.sol

The main treasury contract implementing token vesting for team allocations.

#### Key Features

- **Total Allocation**: 1% of 100B tokens = 1,000,000,000 tokens (1e18 decimals)
- **Lock Period**: 3 years (1095 days) from deployment
- **Vesting Schedule**:
  - 5 milestones every 6 months (180 days each)
  - 20% unlock per milestone (2000 basis points)
  - Total vesting period: 3 years lock + 2 years release = 5 years

#### Contract State Variables

```solidity
IERC20 public immutable escrowToken;           // ESCROW token contract
uint256 public immutable treasuryStartTime;   // Deployment timestamp
uint256 public immutable firstUnlockTime;     // Lock end timestamp
mapping(address => Beneficiary) public beneficiaries;
address[] public beneficiaryList;
uint256 public totalAllocated;
uint256 public totalClaimed;
bool public allocationsLocked;
bool public treasuryFunded;
```

#### Beneficiary Structure

```solidity
struct Beneficiary {
    uint256 totalAllocation;      // Total tokens allocated
    uint256 claimedAmount;        // Amount already claimed
    uint256 lastClaimMilestone;   // Last milestone claimed (0-4)
    bool isActive;                // Whether beneficiary is active
    bool revoked;                 // Whether allocation was revoked
}
```

#### Core Functions

**Admin Functions:**
- `fundTreasury()`: Fund treasury with 1B tokens (one-time)
- `addBeneficiary(address, uint256)`: Add new beneficiary
- `updateBeneficiary(address, uint256)`: Update beneficiary allocation
- `removeBeneficiary(address)`: Remove beneficiary
- `lockAllocations()`: Lock allocations (no more changes)
- `revokeAllocation(address)`: Emergency revocation
- `pause()/unpause()`: Emergency pause/unpause
- `emergencyWithdraw()`: Withdraw unallocated tokens

**Beneficiary Functions:**
- `claimTokens()`: Claim vested tokens
- `claimFor(address)`: Claim for specific beneficiary

**View Functions:**
- `getClaimableAmount(address)`: Get claimable amount
- `getBeneficiaryInfo(address)`: Get detailed beneficiary info
- `getAllBeneficiaries()`: Get all beneficiaries
- `getVestingSchedule()`: Get vesting schedule details
- `getTreasuryStats()`: Get treasury statistics
- `getTimeUntilNextUnlock()`: Time until next unlock

#### Events

```solidity
event TreasuryFunded(uint256 amount, uint256 timestamp);
event BeneficiaryAdded(address indexed beneficiary, uint256 allocation);
event BeneficiaryUpdated(address indexed beneficiary, uint256 newAllocation);
event BeneficiaryRemoved(address indexed beneficiary, uint256 allocation);
event TokensClaimed(address indexed beneficiary, uint256 amount, uint256 milestone);
event AllocationRevoked(address indexed beneficiary, uint256 unvestedAmount);
event AllocationsLocked(uint256 timestamp);
event EmergencyWithdraw(address indexed token, uint256 amount);
```

#### Error Codes

- `InvalidAddress()`: Zero address provided
- `InvalidAmount()`: Invalid amount (zero or exceeds limits)
- `ExceedsTotalAllocation()`: Allocation exceeds total limit
- `AlreadyAllocated()`: Beneficiary already exists
- `NotBeneficiary()`: Address is not a beneficiary
- `AllocationsAlreadyLocked()`: Allocations are locked
- `AllocationsNotLocked()`: Allocations not locked yet
- `TreasuryNotFunded()`: Treasury not funded
- `TreasuryAlreadyFunded()`: Treasury already funded
- `LockPeriodNotEnded()`: Lock period not ended
- `NoTokensAvailable()`: No tokens available to claim
- `AllocationAlreadyRevoked()`: Allocation already revoked
- `InvalidMilestone()`: Invalid milestone
- `InsufficientBalance()`: Insufficient token balance

### 2. ERC20Mock.sol

Mock ERC20 token for testing purposes.

```solidity
contract MockEscrowToken is ERC20, Ownable {
    constructor() ERC20("MockEscrowToken", "ESC") Ownable(msg.sender) {
        _mint(msg.sender, 1_000_000_000 * 10 ** decimals()); // 1B tokens
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
```

### 3. MockEscrowTokenNoMint.sol

Alternative mock token without initial minting.

```solidity
contract MockEscrowTokenNoMint is ERC20, Ownable {
    constructor() ERC20("MockEscrowTokenNoMint", "MOCK") Ownable(msg.sender) {
        // No initial mint
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
```

## Testing

### Test Suite: EscrowTeamTreasury.test.js

Comprehensive test coverage including:

#### Test Categories

1. **Deployment Tests**
   - Correct token address setting
   - Total allocation verification
   - Initial state verification

2. **Funding Tests**
   - Successful treasury funding
   - Double funding prevention
   - Insufficient balance handling

3. **Beneficiary Management**
   - Adding beneficiaries
   - Updating allocations
   - Removing beneficiaries
   - Allocation limits enforcement

4. **Allocation Locking**
   - Locking allocations
   - Preventing changes after lock

5. **Token Claiming**
   - Vesting schedule testing
   - Claim calculations
   - Multiple claim scenarios

6. **Emergency Functions**
   - Allocation revocation
   - Emergency withdrawal
   - Pause/unpause functionality

7. **View Functions**
   - Beneficiary info retrieval
   - Treasury statistics
   - Vesting schedule queries

#### Test Utilities

- Time manipulation using Hardhat Network Helpers
- Multiple signers for testing different roles
- Event emission verification
- Error condition testing

## Deployment

### Deployment Script: scripts/deploy.js

Automated deployment process:

1. **Deploy Mock Token**
   ```javascript
   const MockToken = await ethers.getContractFactory("MockEscrowTokenNoMint");
   const token = await MockToken.deploy();
   ```

2. **Deploy Treasury Contract**
   ```javascript
   const Treasury = await ethers.getContractFactory("EscrowTeamTreasury");
   const treasury = await Treasury.deploy(await token.getAddress());
   ```

3. **Fund Treasury**
   - Mint 1B tokens to owner
   - Approve treasury spending
   - Call `fundTreasury()`

4. **Setup Beneficiaries**
   - Add test beneficiary with allocation
   - Lock allocations

5. **Verification**
   - Log deployed contract addresses
   - Confirm setup completion

### Hardhat Configuration

```javascript
module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  networks: {
    hardhat: { chainId: 31337 },
    localhost: { url: "http://127.0.0.1:8545" }
  },
  mocha: { timeout: 20000 }
};
```

## Usage Guide

### 1. Contract Deployment

```bash
npx hardhat run scripts/deploy.js --network localhost
```

### 2. Adding Beneficiaries

```javascript
// After deployment and funding
await treasury.addBeneficiary(beneficiaryAddress, allocationAmount);
await treasury.lockAllocations();
```

### 3. Claiming Tokens

```javascript
// Beneficiaries can claim vested tokens
await treasury.claimTokens();

// Or anyone can claim for a beneficiary
await treasury.claimFor(beneficiaryAddress);
```

### 4. Querying Information

```javascript
// Get claimable amount
const claimable = await treasury.getClaimableAmount(beneficiaryAddress);

// Get beneficiary details
const info = await treasury.getBeneficiaryInfo(beneficiaryAddress);

// Get treasury statistics
const stats = await treasury.getTreasuryStats();
```

## Security Features

- **ReentrancyGuard**: Prevents reentrancy attacks
- **Pausable**: Emergency pause functionality
- **Access Control**: Owner-only admin functions
- **Input Validation**: Comprehensive error checking
- **SafeERC20**: Safe token transfers
- **Immutable State**: Critical parameters are immutable

## Gas Optimization

- Solidity optimizer enabled (200 runs)
- Efficient data structures
- Batch operations where possible
- Minimal storage writes

## Events and Monitoring

All major operations emit events for off-chain monitoring:
- Treasury funding
- Beneficiary management
- Token claims
- Emergency actions

## Error Handling

Robust error handling with custom errors for gas efficiency and clear error messages.

## License

MIT License - See contract headers for details.


