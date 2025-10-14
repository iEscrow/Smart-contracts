# iEscrow Presale - Complete Deployment Guide

## 📋 Table of Contents

1. [Prerequisites](#prerequisites)
2. [Environment Setup](#environment-setup)
3. [Contract Deployment](#contract-deployment)
4. [Configuration](#configuration)
5. [Starting the Presale](#starting-the-presale)
6. [Monitoring](#monitoring)
7. [Finalization](#finalization)
8. [Security Checklist](#security-checklist)

## Prerequisites

### Required Software
- Node.js v18+ and npm
- Hardhat development environment
- MetaMask or hardware wallet
- Etherscan API key (for verification)

### Smart Contract Requirements
- $ESCROW token contract deployed
- Multi-sig treasury wallet address
- Test ETH/tokens for deployment and testing

### Key Parameters
- **Total Supply**: 100,000,000,000 $ESCROW
- **Presale Supply**: 5,000,000,000 $ESCROW (5%)
- **Round 1**: 3 billion tokens @ $0.0015 (23 days)
- **Round 2**: 2 billion tokens @ $0.002 (11 days)
- **Hard Cap**: $9.5 million
- **Min Purchase**: $50
- **Max Purchase**: $10,000 per user
- **Payment Tokens**: ETH, WETH, WBNB, LINK, WBTC, USDC, USDT
- **Referral Bonus**: 5%

## Environment Setup

### 1. Install Dependencies

```bash
cd escrow
npm install
```

### 2. Configure Environment Variables

Copy `.env.example` to `.env`:

```bash
cp .env.example .env
```

Edit `.env` with your values:

```env
# Network RPC URLs
MAINNET_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY

# Private key (NEVER commit!)
PRIVATE_KEY=your_private_key_here

# Etherscan API key
ETHERSCAN_API_KEY=your_etherscan_api_key

# Contract addresses (fill in after deployment)
ESCROW_TOKEN_ADDRESS=0x...
TREASURY_ADDRESS=0x... # Use multi-sig wallet!
```

### 3. Verify Network Configuration

Edit `hardhat.config.js` to ensure your network settings are correct.

## Contract Deployment

### Step 1: Deploy $ESCROW Token

First, deploy the $ESCROW token contract:

```bash
npx hardhat run scripts/deploy.js --network sepolia
```

Save the deployed token address to `.env` as `ESCROW_TOKEN_ADDRESS`.

### Step 2: Deploy Presale Contract

Deploy the presale contract:

```bash
npx hardhat run scripts/deploy-presale.js --network sepolia
```

**Important**: Verify the following during deployment:
- ✅ Correct $ESCROW token address
- ✅ Correct treasury address (should be multi-sig)
- ✅ Contract deploys successfully
- ✅ Save presale address to `.env` as `PRESALE_ADDRESS`

Expected output:
```
🚀 Deploying iEscrow Presale Contract...
✅ Presale Contract Deployed: 0x...
```

### Step 3: Verify Contracts on Etherscan

Verification happens automatically, but if needed, run manually:

```bash
npx hardhat verify --network sepolia <PRESALE_ADDRESS> <TOKEN_ADDRESS> <TREASURY_ADDRESS>
```

## Configuration

### Step 4: Configure Presale Rounds

Configure both presale rounds and payment tokens:

```bash
npx hardhat run scripts/configure-presale.js --network sepolia
```

This script will:
- ✅ Set Round 1: 3B tokens @ $0.0015
- ✅ Set Round 2: 2B tokens @ $0.002
- ✅ Configure payment token prices (ETH, WETH, WBNB, LINK, WBTC, USDC, USDT)
- ✅ Set purchase limits ($50 min, $10,000 max)
- ✅ Enable referral system (5% bonus)

**Verification**:
```bash
npx hardhat run scripts/monitor-presale.js --network sepolia
```

### Step 5: Transfer Presale Tokens

Transfer 5 billion $ESCROW tokens to the presale contract:

```bash
npx hardhat run scripts/transfer-tokens.js --network sepolia
```

**Critical**: Ensure you transfer exactly 5,000,000,000 tokens!

**Verification**:
Check token balance:
```javascript
const escrowToken = await ethers.getContractAt("IERC20", ESCROW_TOKEN_ADDRESS);
const balance = await escrowToken.balanceOf(PRESALE_ADDRESS);
console.log("Balance:", ethers.utils.formatEther(balance)); // Should be 5000000000
```

## Starting the Presale

### Step 6: Final Pre-Flight Checks

Before starting, verify:
- ✅ Both rounds configured correctly
- ✅ 5 billion tokens in presale contract
- ✅ All payment tokens configured
- ✅ Treasury address is correct (multi-sig!)
- ✅ Purchase limits set correctly
- ✅ Referral system enabled

### Step 7: Start Round 1

Start the presale (begins Round 1):

```bash
npx hardhat run scripts/start-presale.js --network sepolia
```

Expected output:
```
🚀 Starting iEscrow Presale...
✅ All checks passed!
✅ Presale started successfully!
🎉 Presale is now LIVE!
```

**Announcement**: 
- Announce presale start on all channels
- Share presale contract address
- Provide documentation for users

## Monitoring

### Real-Time Monitoring

Monitor presale progress:

```bash
npx hardhat run scripts/monitor-presale.js --network sepolia
```

Shows:
- Current round and status
- Tokens sold and remaining
- USD raised
- Round progress
- Time remaining
- Participant count

### Check Individual Users

Check specific user purchase info:

```bash
npx hardhat run scripts/check-user.js 0xUSER_ADDRESS --network sepolia
```

Shows:
- Tokens purchased
- USD spent
- Round breakdown
- Referral bonuses
- Whitelist status

### Round Transition

Round 1 → Round 2 happens automatically when:
- Round 1 sells out, OR
- 23 days have passed

Manual transition (if needed):
```bash
npx hardhat run scripts/start-round2.js --network sepolia
```

## Finalization

### Step 8: Finalize Presale

After Round 2 ends, finalize the presale:

```bash
npx hardhat run scripts/finalize-presale.js --network sepolia
```

This will:
- ✅ Mark presale as ended
- ✅ Return unsold tokens to owner
- ✅ Lock presale for modifications
- ✅ Prepare for claims

### Step 9: Enable Token Claims

Enable users to claim their tokens:

```bash
npx hardhat run scripts/enable-claims.js --network sepolia
```

**TGE (Token Generation Event)** is now live!

Users can claim by calling `claimTokens()` on the presale contract.

### Step 10: Withdraw Funds

Withdraw collected funds to treasury:

```bash
# Withdraw all collected tokens/ETH
npx hardhat run scripts/withdraw-funds.js --network sepolia
```

## Security Checklist

### Before Mainnet Deployment

- [ ] **Audit**: Get professional security audit from CertiK/Hacken/Quantstamp
- [ ] **Multi-sig**: Use multi-sig wallet (Gnosis Safe) for owner/treasury
- [ ] **Testing**: Complete all tests on testnet
- [ ] **Simulation**: Run full presale simulation on testnet
- [ ] **Backup**: Have emergency procedures documented
- [ ] **Team**: Multiple team members with access
- [ ] **Insurance**: Consider DeFi insurance
- [ ] **Monitoring**: Set up 24/7 monitoring and alerts

### Critical Security Settings

1. **Owner Address**: Should be multi-sig (3-of-5 or 4-of-7)
2. **Treasury Address**: Must be multi-sig wallet
3. **Private Keys**: Never store in code or version control
4. **Access Control**: Limit admin function access
5. **Emergency Pause**: Know how to use `pause()` function
6. **Rate Limits**: Monitor for unusual activity
7. **Oracle Prices**: Update payment token prices regularly

### Emergency Procedures

If issues occur:

1. **Pause Contract**:
```bash
npx hardhat run scripts/emergency-pause.js --network mainnet
```

2. **Cancel Presale** (extreme case):
```bash
npx hardhat run scripts/cancel-presale.js --network mainnet
```

3. **Enable Refunds** (if cancelled):
Users can call `emergencyRefund()` to get tokens back

## Production Deployment Timeline

### T-14 days: Preparation
- Complete all audits
- Finalize contracts
- Set up multi-sig wallets
- Prepare documentation

### T-7 days: Deploy & Configure
- Deploy contracts to mainnet
- Configure all parameters
- Transfer tokens
- Final testing

### T-1 day: Announcement
- Announce presale details
- Share contract addresses
- Publish audit reports
- Prepare support channels

### T-0: Launch
- Start presale
- Monitor closely
- Provide support
- Regular updates

### Post-Launch
- Daily monitoring
- Regular updates
- Community engagement
- Transition to Round 2
- Finalization
- TGE (Token Generation Event)

## Support & Resources

### Documentation
- [Complete Whitepaper](../Updated_contracts/v5/iEscrow%20Whitepaper%20-%20Missing%20Sections%20Completed)
- [Technical Specs](../Updated_contracts/v5/iEscrow%20Project%20-%20Complete%20Summary%20&%20Next%20Steps)
- [Audit Reports](#) (to be added)

### Smart Contract Addresses
- Mainnet: TBD
- Sepolia Testnet: TBD

### Contact
- Security: security@iescrow.com
- Support: support@iescrow.com
- Emergency: emergency@iescrow.com

## Common Issues & Solutions

### Issue: "Insufficient token balance"
**Solution**: Ensure 5 billion tokens transferred to presale contract

### Issue: "Presale not started"
**Solution**: Run `scripts/start-presale.js`

### Issue: "Round not configured"
**Solution**: Run `scripts/configure-presale.js`

### Issue: "Claims not enabled"
**Solution**: Finalize presale first, then run `scripts/enable-claims.js`

### Issue: "Transaction failed"
**Solution**: Check gas settings and network congestion

---

## Quick Reference Commands

```bash
# Deploy
npx hardhat run scripts/deploy-presale.js --network sepolia

# Configure
npx hardhat run scripts/configure-presale.js --network sepolia
npx hardhat run scripts/transfer-tokens.js --network sepolia

# Start
npx hardhat run scripts/start-presale.js --network sepolia

# Monitor
npx hardhat run scripts/monitor-presale.js --network sepolia
npx hardhat run scripts/check-user.js <ADDRESS> --network sepolia

# Finalize
npx hardhat run scripts/finalize-presale.js --network sepolia
npx hardhat run scripts/enable-claims.js --network sepolia

# Emergency
npx hardhat run scripts/emergency-pause.js --network sepolia
```

---

**Remember**: Always test on Sepolia testnet before deploying to mainnet!

🚀 Good luck with your presale!
