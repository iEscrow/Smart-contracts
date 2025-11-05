# Deployment Guide: ESCROW Presale System

## Overview

This guide covers deploying the complete ESCROW presale system using the Foundry deployment script.

## Files

- **`script/DeployPresale.s.sol`** - Main deployment script
- **Deployed Contracts:**
  - `EscrowToken.sol` - Main ESCROW token (ERC20)
  - `EscrowStaking.sol` - Staking contract with bonuses and penalties
  - `MultiTokenPresale.sol` - Presale contract accepting multiple tokens

## Deployment Script Features

### What Gets Deployed

1. **ESCROW Token** - Main token contract
2. **EscrowStaking Contract** - Staking with penalties and rewards
3. **Mock Tokens** (Testnet only) - For testing presale purchases:
   - Mock USDT (6 decimals)
   - Mock USDC (6 decimals)
   - Mock WETH (18 decimals)
   - Mock WBTC (8 decimals)
   - Mock LINK (18 decimals)
   - Mock WBNB (18 decimals)
4. **MultiTokenPresale Contract** - Presale accepting all tokens
5. **Presale Allocation** - 5B tokens minted to presale contract

### Network Detection

- **Testnet (Sepolia):** Deploys mock ERC20 tokens automatically
- **Mainnet:** Skips mock tokens, uses real token addresses

### Treasury Addresses (Hardcoded)

- **Project Treasury:** `0x1321286BB1f31d4438F6E5254D2771B79a6A773e`
- **Dev Treasury:** `0xd81d23f2e37248F8fda5e7BF0a6c047AE234F0A2`
- **Owner Address:** `0xd81d23f2e37248F8fda5e7BF0a6c047AE234F0A2`

### Presale Parameters

- **Presale Rate:** ~666.67 ESCROW tokens per 1 USD
- **Max Tokens:** 5,000,000,000 (5 billion tokens)

## How to Deploy

### Prerequisites

```bash
# 1. Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# 2. Set up environment
export PRIVATE_KEY=your_private_key_here
export SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/your-key
```

### Deploy to Sepolia Testnet

```bash
forge script script/DeployPresale.s.sol:DeployPresale \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

### Deploy to Mainnet (Ethereum)

```bash
forge script script/DeployPresale.s.sol:DeployPresale \
  --rpc-url https://eth-mainnet.g.alchemy.com/v2/your-key \
  --private-key $PRIVATE_KEY \
  --broadcast
```

### Deploy Locally (Testing)

```bash
# Start local Foundry anvil
anvil

# In another terminal:
forge script script/DeployPresale.s.sol:DeployPresale \
  --rpc-url http://localhost:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb476cbed5491b5cc5cc46ffbd451 \
  --broadcast
```

## Deployment Output

The script outputs detailed information:

```
Starting deployment...
Deployer: 0x...

=== Step 1: Deploying ESCROW Token ===
ESCROW Token deployed at: 0x...

=== Step 2: Deploying Mock Tokens (Testnet) ===
Mock USDT deployed at: 0x...
Mock USDC deployed at: 0x...
Mock WETH deployed at: 0x...
Mock WBTC deployed at: 0x...
Mock LINK deployed at: 0x...
Mock WBNB deployed at: 0x...

=== Step 3: Deploying Staking Contract ===
Staking Contract deployed at: 0x...

=== Step 4: Deploying Presale Contract ===
Presale Contract deployed at: 0x...

=== Step 5: Minting Presale Allocation ===
Presale allocation minted successfully

========== DEPLOYMENT SUMMARY ==========
Network Chain ID: 11155111
ESCROW Token: 0x...
Staking Contract: 0x...
Presale Contract: 0x...
Project Treasury: 0x...
Dev Treasury: 0x...
...

✅ Deployment completed successfully!
```

## Post-Deployment Steps

### 1. Verify Deployments

```bash
# Verify contract code on block explorers
forge verify-contract \
  --chain-id 11155111 \
  0x... \
  EscrowToken \
  --watch
```

### 2. Configure Presale

```bash
# Set token prices in presale contract
cast send 0x[PRESALE_ADDRESS] \
  "setPriceUSD(address,uint256)" \
  0x[USDT_ADDRESS] \
  420000000 \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY
```

### 3. Transfer Test Tokens to Users

```bash
# Transfer mock USDT to tester
cast send 0x[USDT_ADDRESS] \
  "transfer(address,uint256)" \
  0x[TESTER_ADDRESS] \
  100000000 \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY
```

### 4. Test Presale

```bash
# Approve presale to spend USDT
cast send 0x[USDT_ADDRESS] \
  "approve(address,uint256)" \
  0x[PRESALE_ADDRESS] \
  100000000 \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY

# Purchase tokens in presale
cast send 0x[PRESALE_ADDRESS] \
  "buyWithToken(address,uint256)" \
  0x[USDT_ADDRESS] \
  100000000 \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY
```

## Mock Token Addresses on Sepolia

After deployment, you'll receive addresses for:
- Mock USDT
- Mock USDC
- Mock WETH
- Mock WBTC
- Mock LINK
- Mock WBNB

Use these for testing presale purchases.

## Important Notes

### For Testnet Deployment
- Mock tokens are deployed automatically
- Each mock has generous initial supply for testing
- Use these addresses for presale token configuration

### For Mainnet Deployment
- Real token addresses are used (hardcoded in MultiTokenPresale)
- No mock tokens deployed
- Ensure treasury wallets are configured correctly
- Review all parameters before deployment

### Security Considerations

1. **Private Key Management**
   - Never commit private keys to version control
   - Use environment variables or `.env` files with gitignore
   - Consider using hardware wallet for mainnet

2. **Contract Verification**
   - Always verify contracts on block explorer
   - Use Etherscan/Blockscout for transparency

3. **Multi-sig Treasury**
   - Consider using multi-sig wallet for treasury
   - Requires governance approval for funds transfer

## Troubleshooting

### Compilation Errors

```bash
# Clean and rebuild
forge clean
forge build
```

### RPC Connection Issues

```bash
# Check RPC endpoint
curl -X POST $SEPOLIA_RPC_URL \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

### Insufficient Gas

```bash
# Increase gas limit
forge script ... --gas-limit 500000
```

### Transaction Failures

```bash
# Get transaction details
cast receipt 0x[TX_HASH] --rpc-url $SEPOLIA_RPC_URL
```

## Contract Interactions After Deployment

### ESCROW Token

```solidity
// Check balance
cast call 0x[ESCROW_ADDRESS] "balanceOf(address)(uint256)" 0x[USER_ADDRESS]

// Transfer tokens
cast send 0x[ESCROW_ADDRESS] "transfer(address,uint256)" 0x[TO_ADDRESS] 1000000000000000000
```

### Staking Contract

```solidity
// Start stake
cast send 0x[STAKING_ADDRESS] "startStake(uint256,uint256)" 1000000000000000000 365

// End stake (after lock period)
cast send 0x[STAKING_ADDRESS] "endStake()"

// Emergency unstake
cast send 0x[STAKING_ADDRESS] "emergencyEndStake()"
```

### Presale Contract

```solidity
// Check token price
cast call 0x[PRESALE_ADDRESS] "tokenPrices(address)(uint256,bool,uint8)" 0x[TOKEN_ADDRESS]

// Check total sold
cast call 0x[PRESALE_ADDRESS] "totalTokensMinted()(uint256)"

// Check user purchase
cast call 0x[PRESALE_ADDRESS] "totalPurchased(address)(uint256)" 0x[USER_ADDRESS]
```

## Summary

The deployment script provides a comprehensive, automated way to deploy the entire ESCROW presale system. It handles:

✅ Contract deployment order  
✅ Proper initialization  
✅ Mock token setup for testing  
✅ Presale allocation minting  
✅ Detailed output and logging  
✅ Network detection  

Ready for both testnet and mainnet deployment!
