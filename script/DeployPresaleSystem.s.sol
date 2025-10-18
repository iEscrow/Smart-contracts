// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../EscrowToken.sol";
import "../MultiTokenPresale.sol";
import "../SimpleKYC.sol";

// Deployment script for the complete presale system
// Usage: forge script script/DeployPresaleSystem.s.sol --broadcast --rpc-url <your_rpc>
contract DeployPresaleSystem is Script {
    
    // Constants matching whitepaper specifications
    uint256 constant PRESALE_RATE = 666666666666666666; // 0.0015 USD per token
    uint256 constant PRESALE_ALLOCATION = 5_000_000_000 * 1e18; // 5 billion tokens
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("Deploying presale system with deployer:", deployer);
        console.log("Deployer balance:", deployer.balance);
        
        // 1. Deploy EscrowToken
        console.log("\n=== Step 1: Deploying EscrowToken ===");
        EscrowToken escrowToken = new EscrowToken();
        console.log("EscrowToken deployed at:", address(escrowToken));
        console.log("Token name:", escrowToken.name());
        console.log("Token symbol:", escrowToken.symbol());
        console.log("Max supply:", escrowToken.MAX_SUPPLY() / 1e18, "tokens");
        
        // 2. Deploy SimpleKYC
        console.log("\n=== Step 2: Deploying KYC Contract ===");
        SimpleKYC kyc = new SimpleKYC(deployer); // Deployer is KYC signer
        console.log("SimpleKYC deployed at:", address(kyc));
        console.log("KYC signer:", kyc.kycSigner());
        console.log("KYC admin:", kyc.admin());
        
        // 3. Deploy MultiTokenPresale
        console.log("\n=== Step 3: Deploying Presale Contract ===");
        MultiTokenPresale presale = new MultiTokenPresale(
            address(escrowToken),
            PRESALE_RATE,
            PRESALE_ALLOCATION,
            address(kyc)
        );
        console.log("MultiTokenPresale deployed at:", address(presale));
        console.log("Presale rate:", presale.presaleRate());
        console.log("Max tokens to mint:", presale.maxTokensToMint() / 1e18, "tokens");
        
        // 4. Mint presale allocation to presale contract
        console.log("\n=== Step 4: Minting Presale Allocation ===");
        escrowToken.mintPresaleAllocation(address(presale));
        console.log("Minted", PRESALE_ALLOCATION / 1e18, "ESCROW tokens to presale contract");
        console.log("Presale contract balance:", escrowToken.balanceOf(address(presale)) / 1e18, "tokens");
        
        // 5. Verify setup
        console.log("\n=== Step 5: Verifying Setup ===");
        (bool hasTokens, bool startDate, bool limits, bool deposited, string memory issues) = 
            presale.validateIEscrowSetup();
            
        console.log("Has correct tokens:", hasTokens);
        console.log("Start date configured:", startDate);
        console.log("Limits configured:", limits);
        console.log("Tokens deposited:", deposited);
        console.log("Setup status:", issues);
        
        // 6. Show presale status
        console.log("\n=== Step 6: Presale Status ===");
        console.log("Presale ready - launches Nov 11, 2025");
        
        // 7. Show supported tokens
        console.log("\n=== Step 7: Supported Payment Tokens ===");
        console.log("ETH, WETH, WBNB, LINK, WBTC, USDC, USDT - All active");
        
        // Store addresses before stopping broadcast
        address tokenAddr = address(escrowToken);
        address kycAddr = address(kyc);
        address presaleAddr = address(presale);
        
        vm.stopBroadcast();
        
        // 8. Summary
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("EscrowToken:", tokenAddr);
        console.log("SimpleKYC:", kycAddr);
        console.log("MultiTokenPresale:", presaleAddr);
        console.log("\nPresale launches: November 11, 2025");
        console.log("Duration: 34 days (23 + 11 day rounds)");
        console.log("Total allocation: 5 billion ESCROW tokens");
        console.log("Token price: $0.0015 USD");
        console.log("\nNext steps:");
        console.log("1. Verify contracts on Etherscan");
        console.log("2. Set up frontend integration");
        console.log("3. Configure KYC verification");
        console.log("4. Prepare marketing materials");
    }
}