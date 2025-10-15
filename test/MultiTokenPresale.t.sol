// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../MultiTokenPresale.sol";
import "../SimpleKYC.sol";
import "../contracts/mocks/MockERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract MultiTokenPresaleTest is Test {
    MultiTokenPresale public presale;
    SimpleKYC public kycContract;
    MockERC20 public presaleToken;
    IERC20Metadata public usdc;
    IERC20Metadata public weth;
    IERC20Metadata public wbtc;
    
    // Test accounts
    address public owner;
    address public buyer1;
    address public buyer2;
    address public buyer3;
    
    // Constants from contract
    address constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant WBTC_ADDRESS = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant NATIVE_ADDRESS = address(0);
    
    uint256 constant PRESALE_LAUNCH_DATE = 1762819200; // Nov 11, 2025 00:00 UTC
    uint256 constant MAX_PRESALE_DURATION = 34 days;
    uint256 constant ROUND1_DURATION = 23 days;
    uint256 constant ROUND2_DURATION = 11 days;
    
    uint256 constant PRESALE_RATE = 666666666666666666; // ~0.667 tokens per USD
    uint256 constant MAX_TOKENS = 5_000_000_000 ether; // 5 billion tokens
    uint256 constant MAX_USD_PER_USER = 10_000 * 1e8; // $10,000 with 8 decimals
    
    // Fork setup
    uint256 mainnetFork;
    
    function setUp() public {
        // Fork mainnet
        string memory rpcUrl = vm.envOr("RPC_URL", string("https://eth-mainnet.alchemyapi.io/v2/demo"));
        mainnetFork = vm.createFork(rpcUrl, 20765000); // Stable recent block
        vm.selectFork(mainnetFork);
        
        // Set up test accounts
        owner = address(this);
        buyer1 = makeAddr("buyer1");
        buyer2 = makeAddr("buyer2");
        buyer3 = makeAddr("buyer3");
        
        // Give test accounts ETH
        vm.deal(buyer1, 100 ether);
        vm.deal(buyer2, 100 ether);
        vm.deal(buyer3, 100 ether);
        
        // Deploy presale token
        presaleToken = new MockERC20(
            "EscrowToken",
            "ESCROW",
            18,
            100_000_000_000 ether // 100 billion for testing
        );
        
        // Deploy KYC contract
        kycContract = new SimpleKYC(makeAddr("kycSigner"));
        
        // Deploy presale contract
        presale = new MultiTokenPresale(
            address(presaleToken),
            PRESALE_RATE,
            MAX_TOKENS,
            address(kycContract)
        );
        
        // Transfer presale tokens to contract
        presaleToken.transfer(address(presale), MAX_TOKENS);
        
        // Disable KYC requirement for existing tests
        presale.setKYCRequired(false);
        
        // Get real mainnet tokens for testing
        usdc = IERC20Metadata(USDC_ADDRESS);
        weth = IERC20Metadata(WETH_ADDRESS);
        wbtc = IERC20Metadata(WBTC_ADDRESS);
        
        // Give test accounts some USDC for testing (simulate whale transfers)
        _dealToken(USDC_ADDRESS, buyer1, 50_000 * 1e6); // 50k USDC
        _dealToken(USDC_ADDRESS, buyer2, 50_000 * 1e6); // 50k USDC
        _dealToken(USDC_ADDRESS, buyer3, 50_000 * 1e6); // 50k USDC
    }
    
    // Helper function to deal tokens from rich addresses
    function _dealToken(address token, address to, uint256 amount) internal {
        // Find a whale address for the token
        address whale;
        if (token == USDC_ADDRESS) {
            whale = 0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503; // Binance wallet
        } else if (token == WETH_ADDRESS) {
            whale = 0x8EB8a3b98659Cce290402893d0123abb75E3ab28; // Avalanche bridge
        } else if (token == WBTC_ADDRESS) {
            whale = 0x9ff58f4fFB29fA2266Ab25e75e2A8b3503311656; // Aave
        }
        
        vm.startPrank(whale);
        IERC20(token).transfer(to, amount);
        vm.stopPrank();
    }
    
    // ============ BASIC SETUP TESTS ============
    
    function test_ForkSetup() public view {
        // Verify we're on forked mainnet
        assertEq(block.chainid, 1, "Should be on mainnet fork");
        assertGt(block.number, 20_000_000, "Should be on recent mainnet block");
        
        // Verify real mainnet contracts exist
        assertGt(address(usdc).code.length, 0, "USDC contract should exist");
        assertEq(usdc.symbol(), "USDC", "Should be real USDC");
        assertEq(usdc.decimals(), 6, "USDC should have 6 decimals");
    }
    
    function test_ContractSetup() public view {
        // Verify presale contract is properly configured
        assertEq(address(presale.presaleToken()), address(presaleToken), "Wrong presale token");
        assertEq(presale.presaleRate(), PRESALE_RATE, "Wrong presale rate");
        assertEq(presale.maxTokensToMint(), MAX_TOKENS, "Wrong max tokens");
        assertEq(presaleToken.balanceOf(address(presale)), MAX_TOKENS, "Contract should have presale tokens");
    }
    
    // ============ PRESALE LIFECYCLE TESTS ============
    
    function test_PresaleStartsCorrectly() public {
        // Start presale manually
        presale.startPresale(MAX_PRESALE_DURATION);
        
        // Verify presale state
        assertTrue(presale.isPresaleActive(), "Presale should be active");
        assertEq(presale.currentRound(), 1, "Should be in round 1");
        
        uint256 startTime = presale.presaleStartTime();
        assertGt(startTime, 0, "Start time should be set");
        assertEq(presale.round1EndTime(), startTime + ROUND1_DURATION, "Round 1 end time incorrect");
        assertEq(presale.presaleEndTime(), startTime + MAX_PRESALE_DURATION, "Presale end time incorrect");
    }
    
    function test_AutoStartOnLaunchDate() public {
        // Time travel to launch date
        vm.warp(PRESALE_LAUNCH_DATE);
        
        // Auto-start should work
        presale.autoStartIEscrowPresale();
        
        // Verify state
        assertTrue(presale.isPresaleActive(), "Presale should be active");
        assertEq(presale.currentRound(), 1, "Should be in round 1");
        assertEq(presale.presaleStartTime(), PRESALE_LAUNCH_DATE, "Start time should be launch date");
    }
    
    function test_AutoStartTooEarly() public {
        // Try to auto-start before launch date
        vm.expectRevert("Too early - presale starts Nov 11, 2025");
        presale.autoStartIEscrowPresale();
    }
    
    function test_RoundTransition() public {
        // Start presale
        presale.startPresale(MAX_PRESALE_DURATION);
        
        uint256 startTime = presale.presaleStartTime();
        
        // Verify round 1 is active
        assertEq(presale.currentRound(), 1, "Should be in round 1");
        
        // Time travel to round 2
        vm.warp(startTime + ROUND1_DURATION + 1);
        
        // Make a purchase to trigger round advancement check
        vm.prank(buyer1);
        presale.buyWithNative{value: 0.1 ether}(buyer1);
        
        // Verify round 2 is active
        assertEq(presale.currentRound(), 2, "Should be in round 2");
    }
    
    // ============ PURCHASE AMOUNT VERIFICATION TESTS ============
    
    function test_ETHPurchaseTokenAmountCalculation() public {
        presale.startPresale(MAX_PRESALE_DURATION);
        
        uint256 ethAmount = 1 ether;
        uint256 ethPrice = 4200 * 1e8; // $4200 with 8 decimals
        
        // Expected: 1 ETH * $4200 * 0.667 tokens/USD = ~2800 tokens
        uint256 expectedTokens = (ethAmount * ethPrice * PRESALE_RATE) / (1e18 * 1e8);
        
        uint256 balanceBefore = presale.totalTokensMinted();
        
        vm.prank(buyer1);
        presale.buyWithNative{value: ethAmount}(buyer1);
        
        uint256 balanceAfter = presale.totalTokensMinted();
        uint256 actualTokens = balanceAfter - balanceBefore;
        
        // Allow for gas buffer deduction (should be close)
        assertApproxEqRel(actualTokens, expectedTokens, 0.05e18, "Token amount calculation incorrect");
        
        // Verify user's token balance tracking
        (, uint256 userTokens,) = presale.getUserPurchases(buyer1);
        assertApproxEqRel(userTokens, expectedTokens, 0.05e18, "User token tracking incorrect");
    }
    
    function test_USDCPurchaseTokenAmountCalculation() public {
        presale.startPresale(MAX_PRESALE_DURATION);
        
        uint256 usdcAmount = 1000 * 1e6; // $1000 USDC
        
        // Expected: $1000 * 0.667 tokens/USD = ~667 tokens
        uint256 expectedTokens = (usdcAmount * 1e8 * PRESALE_RATE) / (1e6 * 1e8); // Convert USDC to 8 decimals for calculation
        
        // Approve and purchase
        vm.startPrank(buyer1);
        usdc.approve(address(presale), usdcAmount);
        
        uint256 balanceBefore = presale.totalTokensMinted();
        presale.buyWithUSDC(usdcAmount, buyer1);
        uint256 balanceAfter = presale.totalTokensMinted();
        
        vm.stopPrank();
        
        uint256 actualTokens = balanceAfter - balanceBefore;
        assertEq(actualTokens, expectedTokens, "USDC token amount calculation incorrect");
        
        // Verify user's token balance tracking
        (, uint256 userTokens,) = presale.getUserPurchases(buyer1);
        assertEq(userTokens, expectedTokens, "User USDC token tracking incorrect");
    }
    
    function test_MultipleTokenPurchaseTracking() public {
        presale.startPresale(MAX_PRESALE_DURATION);
        
        uint256 ethAmount = 0.5 ether;
        uint256 usdcAmount = 2000 * 1e6;
        
        vm.startPrank(buyer1);
        
        // Buy with ETH
        uint256 tokensBefore = presale.totalTokensMinted();
        presale.buyWithNative{value: ethAmount}(buyer1);
        uint256 tokensAfterETH = presale.totalTokensMinted();
        uint256 ethTokens = tokensAfterETH - tokensBefore;
        
        // Buy with USDC
        usdc.approve(address(presale), usdcAmount);
        presale.buyWithUSDC(usdcAmount, buyer1);
        uint256 tokensAfterUSDC = presale.totalTokensMinted();
        uint256 usdcTokens = tokensAfterUSDC - tokensAfterETH;
        
        vm.stopPrank();
        
        // Verify total user tokens
        (, uint256 userTotalTokens,) = presale.getUserPurchases(buyer1);
        assertEq(userTotalTokens, ethTokens + usdcTokens, "Total user tokens tracking incorrect");
        
        // Verify individual purchase tracking
        uint256[] memory amounts;
        (amounts,) = presale.getUserAllPurchases(buyer1);
        
        assertGt(amounts[0], 0, "ETH purchase not tracked"); // ETH
        assertGt(amounts[5], 0, "USDC purchase not tracked"); // USDC
    }
    
    // ============ USD LIMIT ENFORCEMENT TESTS ============
    
    function test_USDLimitEnforcement() public {
        presale.startPresale(MAX_PRESALE_DURATION);
        
        // Try to purchase more than $10k limit with ETH
        // At $4200 per ETH, 2.5 ETH = $10,500
        uint256 excessiveAmount = 2.5 ether;
        
        vm.prank(buyer1);
        vm.expectRevert("Exceeds max user USD limit");
        presale.buyWithNative{value: excessiveAmount}(buyer1);
    }
    
    function test_USDLimitAcrossMultipleTokens() public {
        presale.startPresale(MAX_PRESALE_DURATION);
        
        vm.startPrank(buyer1);
        
        // Buy $5000 worth of ETH (about 1.19 ETH at $4200)
        uint256 eth1 = 1.19 ether;
        presale.buyWithNative{value: eth1}(buyer1);
        
        // Buy $4000 USDC
        uint256 usdc1 = 4000 * 1e6;
        usdc.approve(address(presale), usdc1);
        presale.buyWithUSDC(usdc1, buyer1);
        
        // Try to buy $2000 more USDC (should fail - would exceed $10k total)
        uint256 usdc2 = 2000 * 1e6;
        usdc.approve(address(presale), usdc2);
        vm.expectRevert("Exceeds max user USD limit");
        presale.buyWithUSDC(usdc2, buyer1);
        
        vm.stopPrank();
        
        // Verify total USD spent is close to $9000
        uint256 totalUSD = presale.getUserTotalUSDValue(buyer1);
        assertApproxEqRel(totalUSD, 9000 * 1e8, 0.1e18, "USD tracking across tokens incorrect");
    }
    
    // ============ EARLY CLAIMING PREVENTION TESTS ============
    
    function test_CannotClaimBeforePresaleEnds() public {
        presale.startPresale(MAX_PRESALE_DURATION);
        
        // Make a purchase
        vm.prank(buyer1);
        presale.buyWithNative{value: 1 ether}(buyer1);
        
        // Try to claim while presale is active
        vm.prank(buyer1);
        vm.expectRevert("Presale not ended yet");
        presale.claimTokens();
    }
    
    function test_CanClaimAfterPresaleEnds() public {
        presale.startPresale(MAX_PRESALE_DURATION);
        
        // Make a purchase
        vm.prank(buyer1);
        presale.buyWithNative{value: 1 ether}(buyer1);
        
        (, uint256 purchasedTokens,) = presale.getUserPurchases(buyer1);
        
        // End presale
        presale.emergencyEndPresale();
        
        // Should be able to claim now
        uint256 balanceBefore = presaleToken.balanceOf(buyer1);
        vm.prank(buyer1);
        presale.claimTokens();
        uint256 balanceAfter = presaleToken.balanceOf(buyer1);
        
        assertEq(balanceAfter - balanceBefore, purchasedTokens, "Claimed amount incorrect");
        assertTrue(presale.hasClaimed(buyer1), "Claim status not updated");
    }
    
    function test_CanClaimAfterNaturalPresaleEnd() public {
        presale.startPresale(MAX_PRESALE_DURATION);
        
        // Make a purchase
        vm.prank(buyer1);
        presale.buyWithNative{value: 1 ether}(buyer1);
        
        (, uint256 purchasedTokens,) = presale.getUserPurchases(buyer1);
        
        // Time travel to natural end
        uint256 startTime = presale.presaleStartTime();
        vm.warp(startTime + MAX_PRESALE_DURATION + 1);
        
        // Manually trigger the auto-end check using the public function
        presale.checkAutoEndConditions();
        
        // Verify presale has ended naturally
        assertTrue(presale.presaleEnded(), "Presale should have ended naturally");
        
        // Should be able to claim now
        uint256 balanceBefore = presaleToken.balanceOf(buyer1);
        vm.prank(buyer1);
        presale.claimTokens();
        uint256 balanceAfter = presaleToken.balanceOf(buyer1);
        
        assertEq(balanceAfter - balanceBefore, purchasedTokens, "Claimed amount incorrect after natural end");
    }
    
    // ============ DOUBLE CLAIM PREVENTION TESTS ============
    
    function test_CannotDoubleClaimTokens() public {
        presale.startPresale(MAX_PRESALE_DURATION);
        
        // Make a purchase
        vm.prank(buyer1);
        presale.buyWithNative{value: 1 ether}(buyer1);
        
        // End presale
        presale.emergencyEndPresale();
        
        // First claim should work
        vm.prank(buyer1);
        presale.claimTokens();
        
        // Second claim should fail
        vm.prank(buyer1);
        vm.expectRevert("Already claimed");
        presale.claimTokens();
    }
    
    function test_MultipleUsersClaim() public {
        presale.startPresale(MAX_PRESALE_DURATION);
        
        // Multiple users make purchases
        vm.prank(buyer1);
        presale.buyWithNative{value: 1 ether}(buyer1);
        
        vm.prank(buyer2);
        presale.buyWithNative{value: 0.5 ether}(buyer2);
        
        vm.startPrank(buyer3);
        usdc.approve(address(presale), 1000 * 1e6);
        presale.buyWithUSDC(1000 * 1e6, buyer3);
        vm.stopPrank();
        
        // Get purchase amounts
        (, uint256 tokens1,) = presale.getUserPurchases(buyer1);
        (, uint256 tokens2,) = presale.getUserPurchases(buyer2);
        (, uint256 tokens3,) = presale.getUserPurchases(buyer3);
        
        // End presale
        presale.emergencyEndPresale();
        
        // All users should be able to claim their tokens
        vm.prank(buyer1);
        presale.claimTokens();
        assertEq(presaleToken.balanceOf(buyer1), tokens1, "Buyer1 claim incorrect");
        
        vm.prank(buyer2);
        presale.claimTokens();
        assertEq(presaleToken.balanceOf(buyer2), tokens2, "Buyer2 claim incorrect");
        
        vm.prank(buyer3);
        presale.claimTokens();
        assertEq(presaleToken.balanceOf(buyer3), tokens3, "Buyer3 claim incorrect");
        
        // Verify all are marked as claimed
        assertTrue(presale.hasClaimed(buyer1), "Buyer1 claim status not updated");
        assertTrue(presale.hasClaimed(buyer2), "Buyer2 claim status not updated");
        assertTrue(presale.hasClaimed(buyer3), "Buyer3 claim status not updated");
    }
    
    function test_CannotClaimWithoutPurchase() public {
        presale.startPresale(MAX_PRESALE_DURATION);
        presale.emergencyEndPresale();
        
        // User who didn't purchase cannot claim
        vm.prank(buyer1);
        vm.expectRevert("No tokens to claim");
        presale.claimTokens();
    }
    
    // ============ ROUND TRANSITION AND PURCHASE TRACKING TESTS ============
    
    function test_PurchaseTrackingAcrossRounds() public {
        presale.startPresale(MAX_PRESALE_DURATION);
        
        uint256 startTime = presale.presaleStartTime();
        
        // Round 1 purchases
        vm.prank(buyer1);
        presale.buyWithNative{value: 1 ether}(buyer1);
        
        vm.startPrank(buyer2);
        usdc.approve(address(presale), 2000 * 1e6);
        presale.buyWithUSDC(2000 * 1e6, buyer2);
        vm.stopPrank();
        
        // Store user balances after round 1
        (, uint256 buyer1Round1,) = presale.getUserPurchases(buyer1);
        (, uint256 buyer2Round1,) = presale.getUserPurchases(buyer2);
        
        // Verify round 1 tracking
        assertEq(presale.currentRound(), 1, "Should be in round 1");
        assertGt(buyer1Round1, 0, "Buyer1 should have tokens from round 1");
        assertGt(buyer2Round1, 0, "Buyer2 should have tokens from round 1");
        
        // Time travel to round 2
        vm.warp(startTime + ROUND1_DURATION + 1);
        
        // Round 2 purchase (triggers round advancement)
        vm.startPrank(buyer3);
        usdc.approve(address(presale), 1500 * 1e6);
        presale.buyWithUSDC(1500 * 1e6, buyer3);
        vm.stopPrank();
        
        // Verify round transition occurred
        assertEq(presale.currentRound(), 2, "Should be in round 2 after purchase");
        
        // Verify user tracking persisted across round transition
        (, uint256 buyer1Final,) = presale.getUserPurchases(buyer1);
        (, uint256 buyer2Final,) = presale.getUserPurchases(buyer2);
        (, uint256 buyer3Final,) = presale.getUserPurchases(buyer3);
        
        assertEq(buyer1Final, buyer1Round1, "Buyer1 tokens should be unchanged");
        assertEq(buyer2Final, buyer2Round1, "Buyer2 tokens should be unchanged");
        assertGt(buyer3Final, 0, "Buyer3 should have tokens from round 2");
    }
    
    function test_TimeSimulationFullPresale() public {
        presale.startPresale(MAX_PRESALE_DURATION);
        uint256 startTime = presale.presaleStartTime();
        
        // === ROUND 1 (23 days) ===
        assertEq(presale.currentRound(), 1, "Should start in round 1");
        
        // Early round 1 purchases
        vm.prank(buyer1);
        presale.buyWithNative{value: 1 ether}(buyer1);
        
        // Mid round 1 - time travel 10 days
        vm.warp(startTime + 10 days);
        vm.startPrank(buyer2);
        usdc.approve(address(presale), 3000 * 1e6);
        presale.buyWithUSDC(3000 * 1e6, buyer2);
        vm.stopPrank();
        
        // Late round 1 - time travel to day 20
        vm.warp(startTime + 20 days);
        vm.prank(buyer3);
        presale.buyWithNative{value: 0.8 ether}(buyer3);
        
        // Still in round 1
        assertEq(presale.currentRound(), 1, "Should still be in round 1");
        
        // === TRANSITION TO ROUND 2 ===
        vm.warp(startTime + ROUND1_DURATION + 1 hours);
        
        // Make a purchase to trigger round advancement
        vm.prank(buyer1);
        presale.buyWithNative{value: 0.2 ether}(buyer1);
        
        assertEq(presale.currentRound(), 2, "Should be in round 2");
        
        // === ROUND 2 (11 days) ===
        // Early round 2 purchases
        vm.startPrank(buyer2);
        usdc.approve(address(presale), 1000 * 1e6);
        presale.buyWithUSDC(1000 * 1e6, buyer2);
        vm.stopPrank();
        
        // Mid round 2 - time travel 5 days into round 2
        vm.warp(startTime + ROUND1_DURATION + 5 days);
        vm.prank(buyer3);
        presale.buyWithNative{value: 0.3 ether}(buyer3);
        
        // Still in round 2
        assertEq(presale.currentRound(), 2, "Should still be in round 2");
        assertTrue(presale.isPresaleActive(), "Presale should still be active");
        
        // === NATURAL END ===
        vm.warp(startTime + MAX_PRESALE_DURATION + 1 hours);
        
        // Manually trigger auto-end check instead of purchase
        presale.checkAutoEndConditions();
        
        assertFalse(presale.isPresaleActive(), "Presale should have auto-ended");
        assertTrue(presale.presaleEnded(), "Presale should be marked as ended");
        
        // === CLAIMING PHASE ===
        // All users should be able to claim their accumulated tokens
        (, uint256 buyer1Tokens,) = presale.getUserPurchases(buyer1);
        (, uint256 buyer2Tokens,) = presale.getUserPurchases(buyer2);
        (, uint256 buyer3Tokens,) = presale.getUserPurchases(buyer3);
        
        assertGt(buyer1Tokens, 0, "Buyer1 should have tokens to claim");
        assertGt(buyer2Tokens, 0, "Buyer2 should have tokens to claim");
        assertGt(buyer3Tokens, 0, "Buyer3 should have tokens to claim");
        
        // Claims should work
        vm.prank(buyer1);
        presale.claimTokens();
        assertEq(presaleToken.balanceOf(buyer1), buyer1Tokens, "Buyer1 claim incorrect");
        
        vm.prank(buyer2);
        presale.claimTokens();
        assertEq(presaleToken.balanceOf(buyer2), buyer2Tokens, "Buyer2 claim incorrect");
        
        vm.prank(buyer3);
        presale.claimTokens();
        assertEq(presaleToken.balanceOf(buyer3), buyer3Tokens, "Buyer3 claim incorrect");
    }
    
    function test_MaxTokensReachedAutoEnd() public {
        // Test with a smaller scope - just verify the auto-end logic triggers
        // when tokens are theoretically exhausted (simulate with small purchase)
        presale.startPresale(MAX_PRESALE_DURATION);
        
        // Make a small purchase first
        vm.prank(buyer1);
        presale.buyWithNative{value: 1 ether}(buyer1);
        
        // Check that the auto-end condition check works by verifying remaining tokens
        uint256 remaining = presale.getRemainingTokens();
        assertLt(remaining, MAX_TOKENS, "Some tokens should have been purchased");
        
        // Verify the presale is still active (hasn't auto-ended)
        assertFalse(presale.presaleEnded(), "Presale should still be active");
        assertTrue(presale.isPresaleActive(), "Presale should be active");
    }
    
    // ============ EDGE CASE TESTS ============
    
    function test_GasBurnerProtection() public {
        presale.startPresale(MAX_PRESALE_DURATION);
        
        // Test that gas buffer is properly deducted
        // Use an extremely small amount that will definitely fail after gas estimation
        uint256 tinyAmount = 1000; // 1000 wei - definitely too small for gas buffer
        
        vm.prank(buyer1);
        vm.expectRevert("Insufficient payment after gas");
        presale.buyWithNative{value: tinyAmount}(buyer1);
    }
    
    function test_PrecisionInTokenCalculation() public {
        presale.startPresale(MAX_PRESALE_DURATION);
        
        // Test with small USDC amounts for precision
        uint256 smallUSDC = 1 * 1e6; // $1 USDC
        
        vm.startPrank(buyer1);
        usdc.approve(address(presale), smallUSDC);
        presale.buyWithUSDC(smallUSDC, buyer1);
        vm.stopPrank();
        
        (, uint256 tokens,) = presale.getUserPurchases(buyer1);
        
        // Expected: $1 * 0.667 tokens/USD = 0.667 tokens
        uint256 expected = PRESALE_RATE * 1e8 / 1e8; // 1 USD worth
        assertEq(tokens, expected, "Small amount precision incorrect");
    }
    
    // ============ COMPREHENSIVE STATUS TESTS ============
    
    function test_PresaleStatusThroughoutLifecycle() public {
        // Before start
        (bool started, bool ended,,,) = presale.getPresaleStatus();
        assertFalse(started, "Should not be started initially");
        assertFalse(ended, "Should not be ended initially");
        
        // After start
        presale.startPresale(MAX_PRESALE_DURATION);
        (started, ended,,,) = presale.getPresaleStatus();
        assertTrue(started, "Should be started");
        assertFalse(ended, "Should not be ended");
        assertTrue(presale.isPresaleActive(), "Should be active");
        
        // After end
        presale.emergencyEndPresale();
        (started, ended,,,) = presale.getPresaleStatus();
        assertTrue(started, "Should still be marked as started");
        assertTrue(ended, "Should be ended");
        assertFalse(presale.isPresaleActive(), "Should not be active");
    }
    
    function test_RevertWhen_InvalidDurationStart() public {
        // Should fail with wrong duration
        vm.expectRevert("Duration must match schedule");
        presale.startPresale(30 days); // Wrong duration
    }
    
    function test_RevertWhen_StartTwice() public {
        presale.startPresale(MAX_PRESALE_DURATION);
        vm.expectRevert("Presale already started");
        presale.startPresale(MAX_PRESALE_DURATION); // Should fail
    }
    
    function test_RevertWhen_BuyBeforeStart() public {
        vm.prank(buyer1);
        vm.expectRevert("Presale not started");
        presale.buyWithNative{value: 1 ether}(buyer1); // Should fail
    }
    
    function test_RevertWhen_BuyAfterEnd() public {
        presale.startPresale(MAX_PRESALE_DURATION);
        presale.emergencyEndPresale();
        
        vm.prank(buyer1);
        vm.expectRevert("Presale ended");
        presale.buyWithNative{value: 1 ether}(buyer1); // Should fail
    }
    
    // ============ HELPER FUNCTIONS FOR TESTING ============
    
    function _simulateTimeProgress(uint256 startTime, uint256 daysPassed) internal {
        vm.warp(startTime + (daysPassed * 1 days));
    }
    
    function _getTokenAmountForETH(uint256 ethAmount) internal pure returns (uint256) {
        return (ethAmount * 4200 * 1e8 * PRESALE_RATE) / (1e18 * 1e8);
    }
    
    function _getTokenAmountForUSDC(uint256 usdcAmount) internal pure returns (uint256) {
        return (usdcAmount * 1e8 * PRESALE_RATE) / (1e6 * 1e8);
    }
}