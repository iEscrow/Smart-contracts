#!/bin/bash

# MultiTokenPresale Foundry Test Setup Script
# This script sets up dependencies and runs the comprehensive test suite

set -e

echo "🚀 Setting up Foundry test environment for MultiTokenPresale..."

# Check if foundry is installed
if ! command -v forge &> /dev/null; then
    echo "❌ Foundry not found. Installing Foundry..."
    curl -L https://foundry.paradigm.xyz | bash
    source ~/.bashrc
    foundryup
else
    echo "✅ Foundry is already installed"
fi

# Install dependencies
echo "📦 Installing dependencies..."
forge install --no-commit OpenZeppelin/openzeppelin-contracts 2>/dev/null || echo "OpenZeppelin already installed"
forge install --no-commit foundry-rs/forge-std 2>/dev/null || echo "Forge-std already installed"

# Set up environment variables
echo "🔧 Setting up environment..."

# Check for RPC_URL environment variable
if [ -z "$RPC_URL" ]; then
    echo "⚠️  RPC_URL not set. Using free public RPC (may be slower)"
    export RPC_URL="https://cloudflare-eth.com"
else
    echo "✅ Using RPC_URL: $RPC_URL"
fi

# Create a .env file if it doesn't exist
if [ ! -f .env ]; then
    echo "📝 Creating .env file..."
    cat > .env << EOF
RPC_URL=$RPC_URL
EOF
fi

echo "🧪 Running comprehensive test suite..."
echo "======================================"

# Run tests with detailed output
echo "🔍 Testing fork setup and basic connectivity..."
forge test --match-test "test_ForkSetup|test_ContractSetup" --fork-url $RPC_URL --fork-block-number 20765000 -vv

if [ $? -eq 0 ]; then
    echo "✅ Basic setup tests passed!"
    
    echo ""
    echo "🧮 Testing purchase amount calculations..."
    forge test --match-test "test_.*PurchaseTokenAmountCalculation|test_MultipleTokenPurchaseTracking" --fork-url $RPC_URL --fork-block-number 20765000 -vv
    
    echo ""
    echo "🔒 Testing claiming mechanisms..."
    forge test --match-test "test_.*Claim" --fork-url $RPC_URL --fork-block-number 20765000 -vv
    
    echo ""
    echo "⏰ Testing time simulation and round transitions..."
    forge test --match-test "test_.*Round|test_TimeSimulation" --fork-url $RPC_URL --fork-block-number 20765000 -vv
    
    echo ""
    echo "💰 Testing USD limit enforcement..."
    forge test --match-test "test_.*USD.*Limit" --fork-url $RPC_URL --fork-block-number 20765000 -vv
    
    echo ""
    echo "🏁 Running complete test suite..."
    forge test --fork-url $RPC_URL --fork-block-number 20765000 -v
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "🎉 ALL TESTS PASSED!"
        echo "======================================"
        echo "✅ Token amount verification: COMPLETE"
        echo "✅ Early claiming prevention: COMPLETE"  
        echo "✅ Double claim prevention: COMPLETE"
        echo "✅ Purchase tracking across rounds: COMPLETE"
        echo "✅ Time simulation: COMPLETE"
        echo "✅ USD limit enforcement: COMPLETE"
        echo "✅ Edge case handling: COMPLETE"
        echo ""
        echo "🚀 Your MultiTokenPresale contract is ready for production!"
        echo ""
        echo "📊 To run specific test categories:"
        echo "  - Purchase calculations: forge test --match-test \"test_.*PurchaseTokenAmountCalculation\" --fork-url \$RPC_URL --fork-block-number 20765000 -vv"
        echo "  - Claiming tests: forge test --match-test \"test_.*Claim\" --fork-url \$RPC_URL --fork-block-number 20765000 -vv" 
        echo "  - Time simulation: forge test --match-test \"test_TimeSimulation\" --fork-url \$RPC_URL --fork-block-number 20765000 -vv"
        echo ""
        echo "📈 For gas analysis: forge test --gas-report --fork-url \$RPC_URL --fork-block-number 20765000"
        echo "📋 For coverage report: forge coverage --fork-url \$RPC_URL --fork-block-number 20765000"
    else
        echo "❌ Some tests failed. Check output above for details."
        exit 1
    fi
else
    echo "❌ Basic setup tests failed. Please check:"
    echo "  - RPC_URL is accessible: $RPC_URL"
    echo "  - Internet connection is stable"
    echo "  - Foundry installation is correct"
    exit 1
fi

echo ""
echo "📚 See FOUNDRY_TESTING.md for detailed documentation and troubleshooting."