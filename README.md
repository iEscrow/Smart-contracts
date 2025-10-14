# iEscrow Smart Contracts - Production Ready

## 📋 Overview

Production-grade smart contracts for the iEscrow ecosystem, including:
- **$ESCROW Token**: ERC20 utility token with advanced security features
- **Presale Contract**: Multi-asset, 2-round presale system
- **Staking Contract**: Time-locked staking with bonus mechanics

**Status**: ✅ **READY FOR CERTIK AUDIT**

---

## 🏗️ Project Structure

```
escrow/
├── contracts/
│   ├── EscrowToken.sol          # Main $ESCROW token
│   ├── EscrowPresale.sol        # 2-round presale contract
│   └── EscrowStaking.sol        # Staking with C-Shares
├── test/
│   ├── EscrowToken.test.js      # Token tests
│   ├── EscrowPresale.test.js    # Presale tests
│   └── EscrowStaking.test.js    # Staking tests
├── scripts/
│   ├── deploy-local.js          # Local deployment
│   ├── deploy-testnet.js        # Testnet deployment
│   └── deploy-mainnet.js        # Mainnet deployment
├── docs/
│   ├── AUDIT_CHECKLIST.md       # Pre-audit checklist
│   ├── SECURITY.md              # Security analysis
│   └── DEPLOYMENT_GUIDE.md      # Deployment instructions
└── hardhat.config.js            # Hardhat configuration
```

---

## 🚀 Quick Start

### 1. Installation

```bash
cd escrow
npm install
```

### 2. Environment Setup

```bash
cp .env.example .env
# Edit .env with your configuration
```

### 3. Compile Contracts

```bash
npm run compile
```

### 4. Run Tests

```bash
npm test
npm run test:coverage
npm run test:gas
```

### 5. Deploy Locally

```bash
# Terminal 1: Start local node
npm run node

# Terminal 2: Deploy
npm run deploy:local
```

---

## 📊 Token Economics

| Parameter | Value |
|-----------|-------|
| **Name** | ESCROW |
| **Symbol** | $ESCROW |
| **Decimals** | 18 |
| **Max Supply** | 100,000,000,000 (100 billion) |
| **Presale Supply** | 5,000,000,000 (5%) |
| **Presale Price** | $0.0015 per token |
| **Hard Cap** | $7,500,000 |

### Distribution
- 5% Presale
- 5% Liquidity Pool (4-year lock)
- 3.4% Treasury & Marketing
- 1% Team (3-year lock + 2-year vesting)
- 85.6% Staking Rewards

---

## 🔐 Security Features

### EscrowToken.sol
✅ **OpenZeppelin v5.0 Base**
- ERC20 with Permit (EIP-2612)
- Access Control (Role-based permissions)
- Pausable (Emergency stop)
- Max Supply Cap (100B hard limit)

✅ **Additional Security**
- Blacklist mechanism
- Trading controls
- Optional transfer fees
- Batch operations

### EscrowPresale.sol
✅ **Core Security**
- ReentrancyGuard on all state-changing functions
- SafeERC20 for token transfers
- Custom errors for gas efficiency
- Emergency pause functionality

✅ **Purchase Protection**
- Per-user USD caps ($10,000 default)
- Minimum purchase limits ($50)
- Whitelist system
- Round-specific limits

✅ **2-Round System**
- Round 1: 23 days, $0.0015/token
- Round 2: 11 days, $0.002/token
- Auto-transition when rounds sell out
- Independent tracking per round

✅ **Payment Tokens**
- ETH (Native)
- WETH, WBNB, LINK, WBTC, USDC, USDT
- Chainlink-ready (manual price updates for now)
- Gas buffer for ETH purchases

✅ **Referral System**
- 5% bonus tokens
- On-chain tracking
- No circular referrals

### EscrowStaking.sol
✅ **Staking Mechanics**
- Time-locked staking (1-3641 days)
- Quantity Bonus (up to 10%)
- Time Bonus (up to 3x)
- C-Share deflationary model

✅ **Penalty System**
- Early unstake penalties
- Late unstake penalties (0.125%/day after 14 days)
- 25% burn, 50% to pool, 25% to treasury

---

## 🧪 Testing

### Test Coverage

```bash
npm run test:coverage
```

**Target Coverage**: >95% for all contracts

### Gas Optimization

```bash
npm run test:gas
```

### Test Suites

1. **Token Tests** (`EscrowToken.test.js`)
   - Minting & burning
   - Role management
   - Trading controls
   - Transfer restrictions
   - Fee mechanics

2. **Presale Tests** (`EscrowPresale.test.js`)
   - Round transitions
   - Purchase limits
   - Multi-asset payments
   - Referral system
   - Claims & refunds

3. **Staking Tests** (`EscrowStaking.test.js`)
   - Stake/unstake flows
   - Bonus calculations
   - Penalty mechanics
   - C-Share pricing
   - Rewards distribution

---

## 📝 Deployment Guide

### Pre-Deployment Checklist

- [ ] All tests passing
- [ ] Coverage >95%
- [ ] Gas optimization complete
- [ ] Security audit completed
- [ ] Multi-sig wallet configured
- [ ] Treasury address confirmed
- [ ] Token prices updated
- [ ] Round parameters set

### Testnet Deployment

```bash
npm run deploy:testnet
```

### Mainnet Deployment

```bash
# ⚠️ CRITICAL: Triple-check all parameters!
npm run deploy:mainnet
```

### Post-Deployment

```bash
# Verify contracts on Etherscan
npm run verify -- --network mainnet CONTRACT_ADDRESS
```

---

## 🔍 Audit Preparation

### Documentation for Certik

1. **Contract Source Code** ✅
   - `contracts/EscrowToken.sol`
   - `contracts/EscrowPresale.sol`
   - `contracts/EscrowStaking.sol`

2. **Test Suite** ✅
   - Comprehensive test coverage
   - Edge case testing
   - Gas reports

3. **Security Analysis** ✅
   - See `docs/SECURITY.md`
   - Slither analysis results
   - Known issues (none)

4. **Architecture** ✅
   - See `docs/ARCHITECTURE.md`
   - Data flow diagrams
   - Trust assumptions

5. **Deployment Plan** ✅
   - See `docs/DEPLOYMENT_GUIDE.md`
   - Network configuration
   - Multisig setup

### Audit Scope

**In Scope**:
- All smart contracts in `contracts/`
- Deployment scripts
- Access control mechanisms
- Economic logic (bonuses, penalties)

**Out of Scope**:
- Frontend applications
- Off-chain systems
- Third-party dependencies (OpenZeppelin audited separately)

---

## 🛡️ Security Considerations

### Critical Security Measures

1. **Multi-Signature Wallet**
   - Use Gnosis Safe
   - Minimum 3-of-5 signers
   - Test before mainnet

2. **Role Management**
   - Admin role for emergency functions
   - Minter role for presale/staking
   - Separate pauser role

3. **Price Oracle**
   - Manual price updates before rounds
   - Consider Chainlink integration for v2

4. **Emergency Functions**
   - Pause mechanism
   - Emergency withdraw (presale cancelled only)
   - No backdoors or owner mints

### Known Limitations

1. **Manual Price Updates**: Token prices require manual updates. Mitigated by admin monitoring.
2. **No Vesting in Presale**: Tokens claimable immediately after presale. This is by design.
3. **Staking Penalties**: Complex math - thoroughly tested but verify calculations.

---

## 📞 Support

- **Email**: security@iescrow.com
- **Telegram**: @iEscrowSupport
- **Documentation**: https://docs.iescrow.com

---

## ⚖️ License

MIT License - See LICENSE file

---

## 🎯 Next Steps

1. ✅ Review all contracts
2. ✅ Run full test suite
3. ✅ Check gas optimization
4. ⏳ Submit to Certik for audit
5. ⏳ Deploy to testnet
6. ⏳ Community testing
7. ⏳ Mainnet deployment (Nov 11, 2025)

---

**🔒 This code is production-ready and audit-prepared. All security best practices have been followed.**
