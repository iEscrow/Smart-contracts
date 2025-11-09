// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../EscrowToken.sol";
import "../Authorizer.sol";
import "../DevTreasury.sol";
import "../MultiTokenPresale.sol";

/**
 * @title DeployPresaleMainnet
 * @notice Production deployment script for Ethereum mainnet (no mock tokens)
 * @dev Deploy with: forge script script/DeployPresaleMainnet.s.sol:DeployPresaleMainnet --rpc-url $MAINNET_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify
 */
contract DeployPresaleMainnet is Script {
    // Deployed contracts
    EscrowToken public escrowToken;
    Authorizer public authorizer;
    DevTreasury public devTreasury;
    MultiTokenPresale public presale;

    // Treasury and authorization addresses
    address public constant PROJECT_TREASURY = 0x1321286BB1f31d4438F6E5254D2771B79a6A773e;
    address public constant OWNER_ADDRESS = 0xd81d23f2e37248F8fda5e7BF0a6c047AE234F0A2;
    address public constant BACKEND_SIGNER = 0xd81d23f2e37248F8fda5e7BF0a6c047AE234F0A2; // Backend signer for vouchers

    // Presale parameters
    uint256 public constant PRESALE_RATE = 666_666_666_666_666_667; // ~666.67 tokens per USD (18 decimals)
    uint256 public constant MAX_TOKENS_FOR_PRESALE = 5_000_000_000 * 10**18; // 5B tokens

    // Mainnet token addresses (real tokens - already deployed)
    address public constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant WBNB_ADDRESS = 0x418D75f65a02b3D53B2418FB8E1fe493759c7605;
    address public constant LINK_ADDRESS = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address public constant WBTC_ADDRESS = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT_ADDRESS = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        console.log("========================================");
        console.log("MAINNET DEPLOYMENT - NO TEST TOKENS");
        console.log("========================================");
        console.log("Deployer:", deployer);
        console.log("Network Chain ID:", block.chainid);

        // Step 1: Deploy ESCROW Token
        console.log("\n=== Step 1: Deploying ESCROW Token ===");
        escrowToken = new EscrowToken();
        console.log("ESCROW Token deployed at:", address(escrowToken));

        // Step 2: Deploy Authorizer for KYC voucher system
        console.log("\n=== Step 2: Deploying Authorizer ===");
        authorizer = new Authorizer(BACKEND_SIGNER, OWNER_ADDRESS);
        console.log("Authorizer deployed at:", address(authorizer));

        // Step 3: Calculate future presale address (for DevTreasury constructor)
        console.log("\n=== Step 3: Calculating Future Presale Address ===");
        address predictedPresaleAddress = vm.computeCreateAddress(deployer, vm.getNonce(deployer) + 1);
        console.log("Predicted Presale Address:", predictedPresaleAddress);

        // Step 4: Deploy DevTreasury with predicted presale address
        console.log("\n=== Step 4: Deploying DevTreasury ===");
        devTreasury = new DevTreasury(predictedPresaleAddress);
        console.log("DevTreasury deployed at:", address(devTreasury));
        console.log("DevTreasury linked to future presale:", predictedPresaleAddress);

        // Step 5: Deploy MultiTokenPresale with DevTreasury address
        console.log("\n=== Step 5: Deploying Presale Contract ===");
        presale = new MultiTokenPresale(
            address(escrowToken),
            PRESALE_RATE,
            MAX_TOKENS_FOR_PRESALE,
            address(devTreasury)
        );
        console.log("Presale Contract deployed at:", address(presale));
        
        // Verify prediction was correct
        require(address(presale) == predictedPresaleAddress, "Presale address mismatch!");
        console.log("SUCCESS: Presale address matches prediction");

        // Step 6: Mint presale allocation to presale contract
        console.log("\n=== Step 6: Minting Presale Allocation ===");
        escrowToken.mintPresaleAllocation(address(presale));
        console.log("Presale allocation minted successfully");
        
        console.log("\n=== Configuration Steps (Owner Only) ===");
        console.log("NOTE: The following must be done by owner:", OWNER_ADDRESS);
        console.log("1. presale.updateAuthorizer(", address(authorizer), ")");
        console.log("2. presale.setVoucherSystemEnabled(true)");

        // Step 7: Display deployment summary
        console.log("\n========== DEPLOYMENT SUMMARY ==========");
        console.log("Network: ETHEREUM MAINNET");
        console.log("Chain ID:", block.chainid);
        console.log("\n=== Core Contracts ===");
        console.log("ESCROW Token:", address(escrowToken));
        console.log("Authorizer:", address(authorizer));
        console.log("DevTreasury:", address(devTreasury));
        console.log("Presale Contract:", address(presale));
        console.log("\n=== Configuration ===");
        console.log("Project Treasury:", PROJECT_TREASURY);
        console.log("Owner Address:", OWNER_ADDRESS);
        console.log("Backend Signer:", BACKEND_SIGNER);
        console.log("Presale Rate:", PRESALE_RATE, "tokens per USD");
        console.log("Max Tokens for Presale:", MAX_TOKENS_FOR_PRESALE / 1e18, "billion");

        console.log("\n=== Mainnet Payment Tokens (Pre-configured) ===");
        console.log("ETH: Native (hardcoded in contract)");
        console.log("WETH:", WETH_ADDRESS);
        console.log("WBNB:", WBNB_ADDRESS);
        console.log("LINK:", LINK_ADDRESS);
        console.log("WBTC:", WBTC_ADDRESS);
        console.log("USDC:", USDC_ADDRESS);
        console.log("USDT:", USDT_ADDRESS);
        console.log("\nNOTE: These addresses are hardcoded in MultiTokenPresale.sol");
        console.log("      Token prices are pre-configured but can be updated by owner");

        console.log("\n========== NEXT STEPS ==========");
        console.log("1. Verify all deployed contract addresses");
        console.log("2. Owner calls: presale.updateAuthorizer(", address(authorizer), ")");
        console.log("3. Owner calls: presale.setVoucherSystemEnabled(true)");
        console.log("4. Verify contracts on Etherscan with --verify flag");
        console.log("5. Backend: Generate KYC vouchers using Authorizer signer key");
        console.log("6. Start presale when ready: presale.startPresale() or autoStartEscrowPresale()");
        console.log("7. After presale ends: DevTreasury.withdrawETH() and withdrawToken() distribute 4% fees");
        console.log("\nNOTE: All contracts deployed successfully with correct dependencies!");
        console.log("      NO TEST TOKENS - Using real mainnet tokens only");

        vm.stopBroadcast();

        console.log("\n========================================");
        console.log("DEPLOYMENT COMPLETED!");
        console.log("========================================");
    }
}
