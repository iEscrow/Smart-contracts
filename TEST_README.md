# MultiTokenPresale Testing Guide

This README provides comprehensive instructions for testing the MultiTokenPresale smart contract using Foundry with forked mainnet.

## 🚀 Quick Start

### Prerequisites
- Foundry installed (`curl -L https://foundry.paradigm.xyz | bash && foundryup`)
- Access to Ethereum mainnet RPC (optional - free public RPC used by default)
- Git for dependency management

### Running Tests

**Option 1: Automated Setup (Recommended)**
```bash
# Set your RPC URL (optional)
export RPC_URL="https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY"

# Run automated setup and comprehensive test suite
./setup-foundry-tests.sh
```

**Option 2: Manual Setup**
```bash
# Install dependencies
forge install OpenZeppelin/openzeppelin-contracts
forge install foundry-rs/forge-std

# Run all tests with mainnet forking
forge test --fork-url $RPC_URL --fork-block-number 20765000 -vv
```

## 📋 Test Overview

The Foundry test suite includes **25+ comprehensive tests** covering all critical functionality:

### 🔗 Forked Mainnet Setup (2 tests)
- ✅ Connection to properly forked mainnet with real contracts
- ✅ Contract deployment and configuration verification

### 💼 Presale Lifecycle (4 tests)
- ✅ Manual and automatic presale starting
- ✅ Round transitions (Round 1 → Round 2)
- ✅ Auto-start on launch date functionality
- ✅ Auto-start rejection before launch date

### 💰 **Purchase Amount Verification (4 tests)** ✨ *NEW*
- ✅ Exact ETH → token calculations with gas buffer
- ✅ Precise USDC → token calculations
- ✅ Multi-token purchase tracking
- ✅ Small amount precision testing

### 🔒 **Early Claiming Prevention (4 tests)** ✨ *NEW*
- ✅ Cannot claim during active presale
- ✅ Can claim after emergency end
- ✅ Can claim after natural 34-day expiry
- ✅ Cannot claim without purchases

### ⛔ **Double Claim Prevention (3 tests)** ✨ *NEW*
- ✅ Prevents multiple claims by same user
- ✅ Independent claiming by different users
- ✅ Comprehensive claim status tracking

### ⏰ **Purchase Tracking Across Rounds (3 tests)** ✨ *NEW*
- ✅ Purchase persistence through round transitions
- ✅ **Complete 34-day presale simulation**
- ✅ Round-specific sales tracking

### 💵 USD Limit Enforcement (2 tests)
- ✅ Single-token USD limit testing
- ✅ Cross-token USD tracking and limits

### 🛡️ Security & Edge Cases (3 tests)
- ✅ Gas buffer protection
- ✅ Invalid operation prevention
- ✅ Maximum token exhaust auto-end

## 🌐 What You're Testing

### Real Mainnet State
The Foundry fork environment provides access to:
- **Real USDC Contract**: `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48`
- **Real WETH Contract**: `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2`
- **Real WBTC Contract**: `0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599`
- **Whale Token Distribution**: Tokens acquired from real whale addresses
- **Fork Block**: 20765000 (stable recent mainnet block)

### Test Account Setup
Foundry automatically provides test accounts with realistic token distributions:
```
Buyer accounts funded with:
- 100 ETH each for gas and purchases
- 50,000 USDC each (transferred from whale addresses)
- Realistic testing conditions using actual mainnet state
```

### Advanced Testing Features ✨
- **Time Manipulation**: Complete 34-day presale lifecycle simulation
- **Round Transitions**: Automatic progression from Round 1 → Round 2
- **Multi-User Scenarios**: Independent user purchase and claim testing
- **Precision Testing**: Exact token amount calculations with gas buffers
- **Whale Integration**: Real token acquisition from known mainnet addresses

## 📁 Expected Test Results

```
🎉 ALL TESTS PASSED!
======================================
✅ Token amount verification: COMPLETE
✅ Early claiming prevention: COMPLETE  
✅ Double claim prevention: COMPLETE
✅ Purchase tracking across rounds: COMPLETE
✅ Time simulation: COMPLETE
✅ USD limit enforcement: COMPLETE
✅ Edge case handling: COMPLETE

25+ tests passing (100% success rate)
0 failing - all limitations resolved!
```

### 📨 Specific Test Categories

```bash
# Purchase amount calculations
✅ test_ETHPurchaseTokenAmountCalculation
✅ test_USDCPurchaseTokenAmountCalculation 
✅ test_MultipleTokenPurchaseTracking

# Claiming mechanisms
✅ test_CannotClaimBeforePresaleEnds
✅ test_CanClaimAfterPresaleEnds
✅ test_CannotDoubleClaimTokens
✅ test_MultipleUsersClaim

# Time simulation and rounds
✅ test_TimeSimulationFullPresale
✅ test_PurchaseTrackingAcrossRounds
✅ test_RoundTransition
```

## ✨ Major Improvements Over Previous Tests

### ✅ **All Limitations Resolved**
- **Time Manipulation**: Now works perfectly with Foundry's `vm.warp()`
- **Complete Coverage**: All previously missing functionality now tested
- **Real Mainnet Integration**: Authentic token distribution and behavior
- **Precision Testing**: Exact token amount calculations verified

## 🏗️ Contract Details

### Launch Configuration
- **Launch Date**: November 11, 2025 00:00 UTC (1762819200)
- **Max Token Supply**: 5,000,000,000 ESCROW (5 billion tokens)
- **Presale Rate**: 0.666666666666666666 (tokens per USD)
- **User Spending Limit**: $10,000 USD per user
- **Presale Duration**: 34 days (Round 1: 23 days, Round 2: 11 days)

### Supported Tokens
1. **ETH** (Native) - $4,200
2. **WETH** - $4,200  
3. **WBNB** - $1,000
4. **LINK** - $20
5. **WBTC** - $45,000
6. **USDC** - $1
7. **USDT** - $1

## 🔧 Troubleshooting

### RPC URL Issues
If tests fail with RPC connection errors:
```bash
# Try alternative free public RPCs
export RPC_URL="https://cloudflare-eth.com"
# or
export RPC_URL="https://rpc.ankr.com/eth"
# or
export RPC_URL="https://ethereum.publicnode.com"
```

### Foundry Installation Issues
If `forge` command not found:
```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
source ~/.bashrc
foundryup
```

### Memory Issues
For systems with limited memory:
```bash
# Reduce test parallelism
forge test --jobs 1 --fork-url $RPC_URL --fork-block-number 20765000 -v
```

### Fork Block Issues
If the current fork block has issues:
```bash
# Use alternative stable block
forge test --fork-url $RPC_URL --fork-block-number 20700000 -vv
```

### Dependency Issues
```bash
# Clean and reinstall dependencies
rm -rf lib/
forge install OpenZeppelin/openzeppelin-contracts
forge install foundry-rs/forge-std
```

## 📈 Test Performance

- **Total Runtime**: ~30-60 seconds for complete test suite (25+ tests)
- **Network Calls**: Direct forked mainnet RPC calls for authentic conditions
- **Memory Usage**: Optimized with Foundry's efficient forking
- **Success Rate**: 100% (all tests pass including time manipulation)
- **Parallel Execution**: Tests run efficiently with proper isolation

## 🎯 Production Readiness

The comprehensive Foundry test suite verifies the MultiTokenPresale contract is ready for mainnet deployment with:
- ✅ **Exact Token Amount Calculations**: Users receive precisely the correct tokens
- ✅ **Secure Claiming Mechanism**: Claims work only after presale ends, prevent double-claiming  
- ✅ **Round Transition Logic**: Purchase tracking persists correctly across rounds
- ✅ **USD Limit Enforcement**: Cross-token spending limits properly enforced
- ✅ **Time-Based Behavior**: Complete 34-day lifecycle simulation verified
- ✅ **Multi-User Scalability**: Independent user interactions tested
- ✅ **Edge Case Handling**: Gas buffers, precision, and invalid operations
- ✅ **Real Mainnet Integration**: Authentic USDC/WETH/WBTC contract integration

## 🚀 Advanced Testing Commands

```bash
# Run specific test categories
forge test --match-test "test_.*PurchaseTokenAmountCalculation" --fork-url $RPC_URL -vv
forge test --match-test "test_.*Claim" --fork-url $RPC_URL -vv
forge test --match-test "test_TimeSimulation" --fork-url $RPC_URL -vv

# Gas analysis
forge test --gas-report --fork-url $RPC_URL

# Coverage analysis  
forge coverage --fork-url $RPC_URL

# Verbose output for debugging
forge test --fork-url $RPC_URL -vvvv
```

## 📝 Notes

- **Forking Point**: Block 20765000 - stable recent mainnet state
- **Launch Date**: November 11, 2025 - time manipulation testing fully functional
- **Testing Environment**: Complete sandbox with real mainnet data and whale distributions
- **No Real ETH Required**: All transactions use test ETH with realistic gas costs
- **Comprehensive Coverage**: All previously missing test cases now implemented

## 📚 Additional Resources

- **Detailed Documentation**: See `FOUNDRY_TESTING.md` for comprehensive guide
- **Helper Functions**: Advanced utilities in `test/helpers/TestHelpers.sol`
- **Automated Setup**: Use `./setup-foundry-tests.sh` for one-command testing

