// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../contracts/EscrowToken.sol";
import "../contracts/Authorizer.sol";
import "../contracts/DevTreasury.sol";
import "../contracts/MultiTokenPresale.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title SimulatePaymentsSimple
 * @notice Simulation script for testing WBTC, USDT, and USDC payments with real mainnet tokens
 * @dev Run with: forge script script/SimulatePaymentsSimple.s.sol:SimulatePaymentsSimple --fork-url $MAINNET_RPC_URL
 */
contract SimulatePaymentsSimple is Script {
    // Deployed contracts
    EscrowToken public escrowToken;
    Authorizer public authorizer;
    DevTreasury public devTreasury;
    MultiTokenPresale public presale;
    
    // Mainnet token addresses
    address public constant WBTC_ADDRESS = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT_ADDRESS = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    // Test accounts
    address public constant OWNER = 0xd81d23f2e37248F8fda5e7BF0a6c047AE234F0A2;
    uint256 public signerPrivateKey = 0x1234567890123456789012345678901234567890123456789012345678901234;
    address public signer;
    
    // Test buyers
    address public buyer1 = address(0x1111);
    address public buyer2 = address(0x2222);
    address public buyer3 = address(0x3333);

    // Presale parameters
    uint256 public constant PRESALE_RATE = 66_666_666_666_666_666_667; // ~66.67 tokens per USD = $0.015 per token
    uint256 public constant MAX_TOKENS = 5_000_000_000 * 1e18; // 5 billion
    uint256 public constant PRESALE_LAUNCH_DATE = 1763856000; // Nov 23, 2025 00:00 UTC

    function run() public {
        signer = vm.addr(signerPrivateKey);
        
        console.log("========================================");
        console.log("PAYMENT SIMULATION - WBTC, USDT, USDC");
        console.log("========================================");
        console.log("Signer:", signer);
        console.log("Owner:", OWNER);
        
        // Deploy contracts
        vm.startPrank(OWNER);
        
        console.log("\n=== Deploying Contracts ===");
        escrowToken = new EscrowToken();
        authorizer = new Authorizer(signer, OWNER);
        devTreasury = new DevTreasury(OWNER);
        presale = new MultiTokenPresale(
            address(escrowToken),
            PRESALE_RATE,
            MAX_TOKENS,
            address(devTreasury)
        );
        
        console.log("ESCROW Token:", address(escrowToken));
        console.log("Authorizer:", address(authorizer));
        console.log("DevTreasury:", address(devTreasury));
        console.log("Presale:", address(presale));
        console.log("\n=== Using Mainnet Tokens ===");
        console.log("WBTC:", WBTC_ADDRESS);
        console.log("USDC:", USDC_ADDRESS);
        console.log("USDT:", USDT_ADDRESS);
        
        // Setup presale
        console.log("\n=== Setting Up Presale ===");
        presale.updateAuthorizer(address(authorizer));
        presale.setVoucherSystemEnabled(true);
        escrowToken.mintPresaleAllocation(address(presale));
        
        // Set token prices
        console.log("\n=== Updating Token Prices ===");
        address[] memory tokens = new address[](3);
        uint256[] memory prices = new uint256[](3);
        uint8[] memory decimalsArray = new uint8[](3);
        bool[] memory activeArray = new bool[](3);
        
        tokens[0] = WBTC_ADDRESS;
        tokens[1] = USDC_ADDRESS;
        tokens[2] = USDT_ADDRESS;
        
        prices[0] = 86648 * 1e8; // $86,648 per WBTC
        prices[1] = 1 * 1e8;     // $1 per USDC
        prices[2] = 1 * 1e8;     // $1 per USDT
        
        decimalsArray[0] = 8;  // WBTC has 8 decimals
        decimalsArray[1] = 6;  // USDC has 6 decimals
        decimalsArray[2] = 6;  // USDT has 6 decimals
        
        activeArray[0] = true;
        activeArray[1] = true;
        activeArray[2] = true;
        
        presale.setTokenPrices(tokens, prices, decimalsArray, activeArray);
        console.log("Token prices updated:");
        console.log("- WBTC: $86,648");
        console.log("- USDC: $1");
        console.log("- USDT: $1");
        
        vm.stopPrank();
        
        // Warp to presale start time
        vm.warp(PRESALE_LAUNCH_DATE + 1 days);
        console.log("\n=== Warped to Presale Time ===");
        console.log("Current timestamp:", block.timestamp);
        
        // Simulate payments
        console.log("\n========================================");
        console.log("SIMULATING PAYMENTS");
        console.log("========================================");
        
        _simulateWBTCPayment();
        _simulateUSDCPayment();
        _simulateUSDTPayment();
        
        // Summary
        console.log("\n========================================");
        console.log("SIMULATION SUMMARY");
        console.log("========================================");
        console.log("Total tokens sold:", presale.totalTokensMinted() / 1e18, "ESCROW");
        console.log("Buyer 1 (WBTC) purchased:", presale.totalPurchased(buyer1) / 1e18, "ESCROW");
        console.log("Buyer 2 (USDC) purchased:", presale.totalPurchased(buyer2) / 1e18, "ESCROW");
        console.log("Buyer 3 (USDT) purchased:", presale.totalPurchased(buyer3) / 1e18, "ESCROW");
        
        console.log("\n=== Dev Treasury Balances (4% Fee) ===");
        console.log("WBTC balance:", IERC20(WBTC_ADDRESS).balanceOf(address(devTreasury)), "(4% of payment)");
        console.log("USDC balance:", IERC20(USDC_ADDRESS).balanceOf(address(devTreasury)), "(4% of payment)");
        console.log("USDT balance:", IERC20(USDT_ADDRESS).balanceOf(address(devTreasury)), "(4% of payment)");
        
        console.log("\n========================================");
        console.log("SIMULATION COMPLETED!");
        console.log("========================================");
    }

    function _simulateWBTCPayment() internal {
        console.log("\n--- Test 1: WBTC Payment ---");
        
        // Give WBTC to buyer1 using storage manipulation
        uint256 wbtcAmount = 0.01 * 1e8; // 0.01 WBTC (~$866)
        _giveTokens(WBTC_ADDRESS, buyer1, wbtcAmount);
        
        console.log("Buyer1 received:", wbtcAmount, "WBTC (0.01 WBTC)");
        console.log("USD value: ~$866");
        
        // Approve presale
        vm.prank(buyer1);
        IERC20(WBTC_ADDRESS).approve(address(presale), wbtcAmount);
        
        // Create voucher
        Authorizer.Voucher memory voucher = Authorizer.Voucher({
            buyer: buyer1,
            beneficiary: buyer1,
            paymentToken: WBTC_ADDRESS,
            usdLimit: 1000000 * 1e8, // $1M limit
            nonce: 0,
            deadline: block.timestamp + 1 days,
            presale: address(presale)
        });
        
        // Generate signature
        bytes memory signature = _generateSignature(voucher);
        
        // Make purchase
        uint256 balanceBefore = presale.totalPurchased(buyer1);
        vm.prank(buyer1);
        presale.buyWithTokenVoucher(WBTC_ADDRESS, wbtcAmount, buyer1, voucher, signature);
        uint256 balanceAfter = presale.totalPurchased(buyer1);
        
        uint256 tokensReceived = balanceAfter - balanceBefore;
        console.log("Tokens allocated:", tokensReceived / 1e18, "ESCROW");
        console.log("Expected: ~57,733 ESCROW (866 * 66.67)");
        console.log("[SUCCESS] WBTC payment processed");
    }

    function _simulateUSDCPayment() internal {
        console.log("\n--- Test 2: USDC Payment ---");
        
        // Give USDC to buyer2 using storage manipulation
        uint256 usdcAmount = 1000 * 1e6; // $1000 USDC
        _giveTokens(USDC_ADDRESS, buyer2, usdcAmount);
        
        console.log("Buyer2 received:", usdcAmount / 1e6, "USDC ($1000)");
        console.log("USD value: $1000");
        
        // Approve presale
        vm.prank(buyer2);
        IERC20(USDC_ADDRESS).approve(address(presale), usdcAmount);
        
        // Create voucher
        uint256 nonce = authorizer.getNonce(buyer2);
        Authorizer.Voucher memory voucher = Authorizer.Voucher({
            buyer: buyer2,
            beneficiary: buyer2,
            paymentToken: USDC_ADDRESS,
            usdLimit: 1000000 * 1e8, // $1M limit
            nonce: nonce,
            deadline: block.timestamp + 1 days,
            presale: address(presale)
        });
        
        // Generate signature
        bytes memory signature = _generateSignature(voucher);
        
        // Make purchase
        uint256 balanceBefore = presale.totalPurchased(buyer2);
        vm.prank(buyer2);
        presale.buyWithTokenVoucher(USDC_ADDRESS, usdcAmount, buyer2, voucher, signature);
        uint256 balanceAfter = presale.totalPurchased(buyer2);
        
        uint256 tokensReceived = balanceAfter - balanceBefore;
        console.log("Tokens allocated:", tokensReceived / 1e18, "ESCROW");
        console.log("Expected: ~66,667 ESCROW (1000 * 66.67)");
        console.log("[SUCCESS] USDC payment processed");
    }

    function _simulateUSDTPayment() internal {
        console.log("\n--- Test 3: USDT Payment ---");
        
        // Give USDT to buyer3 using storage manipulation
        uint256 usdtAmount = 500 * 1e6; // $500 USDT
        _giveTokens(USDT_ADDRESS, buyer3, usdtAmount);
        
        console.log("Buyer3 received:", usdtAmount / 1e6, "USDT ($500)");
        console.log("USD value: $500");
        
        // Get nonce first
        uint256 nonce = authorizer.getNonce(buyer3);
        
        // Approve presale (USDT doesn't return bool from approve, use low-level call)
        vm.prank(buyer3);
        (bool success,) = USDT_ADDRESS.call(abi.encodeWithSignature("approve(address,uint256)", address(presale), usdtAmount));
        require(success, "USDT approve failed");
        
        // Create voucher
        Authorizer.Voucher memory voucher = Authorizer.Voucher({
            buyer: buyer3,
            beneficiary: buyer3,
            paymentToken: USDT_ADDRESS,
            usdLimit: 1000000 * 1e8, // $1M limit
            nonce: nonce,
            deadline: block.timestamp + 1 days,
            presale: address(presale)
        });
        
        // Generate signature
        bytes memory signature = _generateSignature(voucher);
        
        // Make purchase
        uint256 balanceBefore = presale.totalPurchased(buyer3);
        vm.prank(buyer3);
        presale.buyWithTokenVoucher(USDT_ADDRESS, usdtAmount, buyer3, voucher, signature);
        uint256 balanceAfter = presale.totalPurchased(buyer3);
        
        uint256 tokensReceived = balanceAfter - balanceBefore;
        console.log("Tokens allocated:", tokensReceived / 1e18, "ESCROW");
        console.log("Expected: ~33,333 ESCROW (500 * 66.67)");
        console.log("[SUCCESS] USDT payment processed");
    }

    /// @notice Helper to give tokens to an address by manipulating storage
    function _giveTokens(address token, address to, uint256 amount) internal {
        // Standard ERC20 balance slot: keccak256(abi.encode(holder, slot))
        // Try slot 0 first (most common)
        bytes32 slot = keccak256(abi.encode(to, uint256(0)));
        vm.store(token, slot, bytes32(amount));
        
        // Verify balance was set
        uint256 balance = IERC20(token).balanceOf(to);
        if (balance != amount) {
            // Try different slots if standard slot 0 didn't work
            for (uint256 i = 1; i < 10; i++) {
                slot = keccak256(abi.encode(to, i));
                vm.store(token, slot, bytes32(amount));
                balance = IERC20(token).balanceOf(to);
                if (balance == amount) break;
            }
        }
        require(IERC20(token).balanceOf(to) == amount, "Failed to give tokens");
    }

    function _generateSignature(Authorizer.Voucher memory voucher) internal view returns (bytes memory) {
        bytes32 voucherHash = keccak256(abi.encode(
            keccak256("Voucher(address buyer,address beneficiary,address paymentToken,uint256 usdLimit,uint256 nonce,uint256 deadline,address presale)"),
            voucher.buyer,
            voucher.beneficiary,
            voucher.paymentToken,
            voucher.usdLimit,
            voucher.nonce,
            voucher.deadline,
            voucher.presale
        ));
        
        bytes32 domainSeparator = authorizer.getDomainSeparator();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, voucherHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
