// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../EscrowToken.sol";
import "../Authorizer.sol";
import "../MultiTokenPresale.sol";
import "../SimpleKYC.sol";

contract DeployVoucherSystem is Script {
    // Deployment parameters
    address public constant OWNER = 0x1234567890123456789012345678901234567890; // Replace with actual owner
    address public constant BACKEND_SIGNER = 0x2345678901234567890123456789012345678901; // Replace with actual backend signer
    
    // Presale parameters
    uint256 public constant PRESALE_RATE = 666666666666666666; // 666.666... tokens per USD (18 decimals)
    uint256 public constant MAX_PRESALE_TOKENS = 5000000000 * 1e18; // 5 billion tokens
    
    function run() external {
        vm.startBroadcast();
        
        console.log("Starting voucher-based presale system deployment...");
        console.log("Owner:", OWNER);
        console.log("Backend Signer:", BACKEND_SIGNER);
        
        // 1. Deploy EscrowToken
        console.log("\\n1. Deploying EscrowToken...");
        EscrowToken escrowToken = new EscrowToken();
        console.log("EscrowToken deployed at:", address(escrowToken));
        
        // 2. Deploy SimpleKYC (for backward compatibility)
        console.log("\\n2. Deploying SimpleKYC...");
        SimpleKYC kyc = new SimpleKYC(BACKEND_SIGNER);
        console.log("SimpleKYC deployed at:", address(kyc));
        
        // 3. Deploy Authorizer for voucher-based KYC
        console.log("\\n3. Deploying Authorizer...");
        Authorizer authorizer = new Authorizer(BACKEND_SIGNER, OWNER);
        console.log("Authorizer deployed at:", address(authorizer));
        
        // 4. Deploy MultiTokenPresale
        console.log("\\n4. Deploying MultiTokenPresale...");
        MultiTokenPresale presale = new MultiTokenPresale(
            address(escrowToken),
            PRESALE_RATE,
            MAX_PRESALE_TOKENS,
            address(kyc)
        );
        console.log("MultiTokenPresale deployed at:", address(presale));
        
        // 5. Configure the presale with Authorizer
        console.log("\\n5. Configuring presale with Authorizer...");
        presale.updateAuthorizer(address(authorizer));
        presale.setVoucherSystemEnabled(true);
        console.log("Authorizer linked to presale");
        console.log("Voucher system enabled");
        
        // 6. Mint presale allocation to presale contract
        console.log("\\n6. Minting presale allocation...");
        escrowToken.mint(address(presale), MAX_PRESALE_TOKENS);
        console.log("Minted", MAX_PRESALE_TOKENS / 1e18, "ESCROW tokens to presale contract");
        
        // 7. Verify setup
        console.log("\\n7. Verifying deployment...");
        console.log("EscrowToken balance of presale:", escrowToken.balanceOf(address(presale)) / 1e18);
        console.log("Presale max tokens:", presale.maxTokensToMint() / 1e18);
        console.log("Presale rate:", presale.presaleRate());
        
        (address authorizerAddress, bool voucherEnabled) = presale.getAuthorizerInfo();
        console.log("Presale authorizer:", authorizerAddress);
        console.log("Voucher system enabled:", voucherEnabled);
        
        (address kycAddress, bool kycRequired) = presale.getKYCInfo();
        console.log("KYC contract:", kycAddress);
        console.log("KYC required:", kycRequired);
        
        console.log("Backend signer in Authorizer:", authorizer.signer());
        
        // 8. Display deployment summary
        console.log("\\n=== DEPLOYMENT COMPLETE ===");
        console.log("EscrowToken:", address(escrowToken));
        console.log("SimpleKYC:", address(kyc));
        console.log("Authorizer:", address(authorizer));
        console.log("MultiTokenPresale:", address(presale));
        
        console.log("\\n=== NEXT STEPS ===");
        console.log("1. Transfer ownership to multisig if needed");
        console.log("2. Auto-start will trigger on Nov 11, 2025 (timestamp: 1762819200)");
        console.log("3. Backend can now issue EIP-712 vouchers for purchases");
        console.log("4. Users can purchase with single transaction using vouchers");
        console.log("5. Legacy KYC system still available for compatibility");
        
        vm.stopBroadcast();
    }
    
    // Helper function for testnet deployment with different parameters
    function runTestnet() external {
        vm.startBroadcast();
        
        console.log("Starting TESTNET deployment...");
        
        // Use msg.sender as owner for testnet
        address testOwner = msg.sender;
        address testSigner = msg.sender; // Use same address for simplicity
        
        console.log("Test Owner/Signer:", testOwner);
        
        // Deploy with same parameters but different owner
        EscrowToken escrowToken = new EscrowToken();
        SimpleKYC kyc = new SimpleKYC(testSigner);
        Authorizer authorizer = new Authorizer(testSigner, testOwner);
        
        MultiTokenPresale presale = new MultiTokenPresale(
            address(escrowToken),
            PRESALE_RATE,
            MAX_PRESALE_TOKENS,
            address(kyc)
        );
        
        // Configure presale
        presale.updateAuthorizer(address(authorizer));
        presale.setVoucherSystemEnabled(true);
        presale.setKYCRequired(false); // Disable KYC for easier testing
        
        // Mint tokens
        escrowToken.mint(address(presale), MAX_PRESALE_TOKENS);
        
        // For testnet, start presale immediately
        presale.startPresale(34 days);
        
        console.log("\\n=== TESTNET DEPLOYMENT COMPLETE ===");
        console.log("EscrowToken:", address(escrowToken));
        console.log("SimpleKYC:", address(kyc));  
        console.log("Authorizer:", address(authorizer));
        console.log("MultiTokenPresale:", address(presale));
        console.log("Presale started immediately for testing");
        
        vm.stopBroadcast();
    }
}