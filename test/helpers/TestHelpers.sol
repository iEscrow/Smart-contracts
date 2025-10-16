// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../MultiTokenPresale.sol";

/// @title TestHelpers
/// @notice Helper functions and utilities for comprehensive presale testing
contract TestHelpers is Test {
    
    // Known whale addresses for different tokens on mainnet
    mapping(address => address) public whales;
    
    constructor() {
        // Initialize known whale addresses
        whales[0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48] = 0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503; // USDC - Binance
        whales[0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2] = 0x8EB8a3b98659Cce290402893d0123abb75E3ab28; // WETH - Avalanche Bridge
        whales[0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599] = 0x9ff58f4fFB29fA2266Ab25e75e2A8b3503311656; // WBTC - Aave
        whales[0xdAC17F958D2ee523a2206206994597C13D831ec7] = 0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503; // USDT - Binance
        whales[0x514910771AF9Ca656af840dff83E8264EcF986CA] = 0x1985365e9f78359a9B6AD760e32412f4a445E862; // LINK - Random DeFi address
        whales[0x418D75f65a02b3D53B2418FB8E1fe493759c7605] = 0x1985365e9f78359a9B6AD760e32412f4a445E862; // WBNB - Random DeFi address
    }
    
    /// @notice Deal tokens to an address by transferring from a whale
    /// @param token The token contract address
    /// @param to The recipient address
    /// @param amount The amount to transfer
    function dealToken(address token, address to, uint256 amount) public {
        address whale = whales[token];
        require(whale != address(0), "No whale found for token");
        
        vm.startPrank(whale);
        IERC20(token).transfer(to, amount);
        vm.stopPrank();
    }
    
    /// @notice Setup multiple test accounts with ETH and various tokens
    /// @param accounts Array of accounts to fund
    /// @param ethAmount Amount of ETH to give each account
    /// @param usdcAmount Amount of USDC to give each account
    function setupTestAccounts(
        address[] memory accounts,
        uint256 ethAmount,
        uint256 usdcAmount
    ) public {
        for (uint256 i = 0; i < accounts.length; i++) {
            // Give ETH
            vm.deal(accounts[i], ethAmount);
            
            // Give USDC
            if (usdcAmount > 0) {
                dealToken(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, accounts[i], usdcAmount);
            }
        }
    }
    
    /// @notice Calculate expected token amount for ETH purchase
    /// @param ethAmount Amount of ETH being spent
    /// @param presaleRate The presale rate (tokens per USD)
    /// @param gasBuffer Gas buffer to subtract from ETH amount
    /// @return expectedTokens Expected token amount accounting for gas buffer
    function calculateExpectedTokensForETH(
        uint256 ethAmount,
        uint256 presaleRate,
        uint256 gasBuffer
    ) public pure returns (uint256 expectedTokens) {
        uint256 ethPrice = 4200 * 1e8; // $4200 with 8 decimals
        uint256 paymentAmount = ethAmount - gasBuffer;
        
        // Calculate USD value: ETH amount * ETH price / (ETH decimals * USD decimals)
        uint256 usdValue = (paymentAmount * ethPrice) / (1e18 * 1e8);
        
        // Calculate tokens: USD value * presale rate
        expectedTokens = usdValue * presaleRate;
    }
    
    /// @notice Calculate expected token amount for USDC purchase
    /// @param usdcAmount Amount of USDC being spent
    /// @param presaleRate The presale rate (tokens per USD)
    /// @return expectedTokens Expected token amount
    function calculateExpectedTokensForUSDC(
        uint256 usdcAmount,
        uint256 presaleRate
    ) public pure returns (uint256 expectedTokens) {
        // USDC has 6 decimals, need to convert to 8 decimals for USD calculation
        uint256 usdValue = usdcAmount * 1e8 / 1e6;
        expectedTokens = (usdValue * presaleRate) / 1e8;
    }
    
    /// @notice Simulate passage of time and verify presale state
    /// @param presale The presale contract
    /// @param startTime The presale start timestamp
    /// @param daysToAdvance Number of days to advance
    /// @param expectedRound Expected round after time advancement
    function advanceTimeAndVerifyRound(
        MultiTokenPresale presale,
        uint256 startTime,
        uint256 daysToAdvance,
        uint256 expectedRound
    ) public {
        vm.warp(startTime + (daysToAdvance * 1 days));
        
        // Make a small transaction to trigger any round advancement logic
        vm.deal(address(this), 1 ether);
        if (presale.isPresaleActive()) {
            try presale.buyWithNative{value: 0.01 ether}(address(this)) {
                // Purchase successful, check round
            } catch {
                // Purchase might fail if presale ended, that's okay
            }
        }
        
        if (presale.isPresaleActive()) {
            assertEq(presale.currentRound(), expectedRound, "Round mismatch after time advancement");
        }
    }
    
    /// @notice Verify user's purchase tracking across multiple tokens
    /// @param presale The presale contract
    /// @param user The user address
    /// @param expectedETHAmount Expected ETH amount purchased
    /// @param expectedUSDCAmount Expected USDC amount purchased
    /// @param expectedTotalTokens Expected total tokens allocated
    function verifyUserPurchaseTracking(
        MultiTokenPresale presale,
        address user,
        uint256 expectedETHAmount,
        uint256 expectedUSDCAmount,
        uint256 expectedTotalTokens
    ) public view {
        // Check individual token purchases
        uint256[] memory amounts;
        (amounts,) = presale.getUserAllPurchases(user);
        
        if (expectedETHAmount > 0) {
            assertGt(amounts[0], 0, "ETH purchase not tracked");
            assertApproxEqRel(amounts[0], expectedETHAmount, 0.05e18, "ETH amount tracking incorrect");
        }
        
        if (expectedUSDCAmount > 0) {
            assertGt(amounts[5], 0, "USDC purchase not tracked"); // USDC is index 5
            assertEq(amounts[5], expectedUSDCAmount, "USDC amount tracking incorrect");
        }
        
        // Check total token allocation
        (, uint256 totalTokens,) = presale.getUserPurchases(user);
        assertApproxEqRel(totalTokens, expectedTotalTokens, 0.05e18, "Total token tracking incorrect");
    }
    
    /// @notice Execute a complete presale simulation with multiple users and time progression
    /// @param presale The presale contract
    /// @param users Array of user addresses
    /// @return Total tokens sold during simulation
    function executePresaleSimulation(
        MultiTokenPresale presale,
        address[] memory users
    ) public returns (uint256) {
        require(users.length >= 3, "Need at least 3 users for simulation");
        
        // Start presale
        uint256 startTime = block.timestamp;
        presale.startPresale(34 days);
        
        uint256 totalTokensBefore = presale.totalTokensMinted();
        
        // === ROUND 1 SIMULATION ===
        console.log("=== Round 1 Simulation ===");
        
        // User 1: ETH purchase early in round 1
        vm.deal(users[0], 10 ether);
        vm.prank(users[0]);
        presale.buyWithNative{value: 1 ether}(users[0]);
        
        // User 2: USDC purchase mid round 1
        vm.warp(startTime + 10 days);
        dealToken(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, users[1], 5000 * 1e6);
        vm.startPrank(users[1]);
        IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48).approve(address(presale), 3000 * 1e6);
        presale.buyWithUSDC(3000 * 1e6, users[1]);
        vm.stopPrank();
        
        // User 3: Mixed purchase late round 1
        vm.warp(startTime + 20 days);
        vm.deal(users[2], 10 ether);
        dealToken(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, users[2], 5000 * 1e6);
        vm.startPrank(users[2]);
        presale.buyWithNative{value: 0.5 ether}(users[2]);
        IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48).approve(address(presale), 1000 * 1e6);
        presale.buyWithUSDC(1000 * 1e6, users[2]);
        vm.stopPrank();
        
        // Verify still in round 1
        assertEq(presale.currentRound(), 1, "Should still be in round 1");
        
        // === ROUND 2 TRANSITION ===
        console.log("=== Round 2 Transition ===");
        vm.warp(startTime + 23 days + 1 hours);
        
        // Trigger round 2 with purchase
        vm.prank(users[0]);
        presale.buyWithNative{value: 0.2 ether}(users[0]);
        assertEq(presale.currentRound(), 2, "Should be in round 2");
        
        // === ROUND 2 SIMULATION ===
        console.log("=== Round 2 Simulation ===");
        
        // More purchases in round 2
        vm.warp(startTime + 25 days);
        vm.prank(users[1]);
        presale.buyWithNative{value: 0.3 ether}(users[1]);
        
        vm.warp(startTime + 30 days);
        vm.startPrank(users[2]);
        IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48).approve(address(presale), 500 * 1e6);
        presale.buyWithUSDC(500 * 1e6, users[2]);
        vm.stopPrank();
        
        // === NATURAL END ===
        console.log("=== Natural End Simulation ===");
        vm.warp(startTime + 34 days + 1 hours);
        
        // Trigger auto-end
        vm.prank(users[0]);
        presale.buyWithNative{value: 0.1 ether}(users[0]);
        
        assertTrue(presale.presaleEnded(), "Presale should have ended naturally");
        
        uint256 totalTokensAfter = presale.totalTokensMinted();
        return totalTokensAfter - totalTokensBefore;
    }
    
    /// @notice Test that all users can claim their tokens correctly after presale ends
    /// @param presale The presale contract
    /// @param users Array of user addresses to test claiming
    /// @param presaleToken The presale token contract
    function verifyAllUsersClaim(
        MultiTokenPresale presale,
        address[] memory users,
        IERC20 presaleToken
    ) public {
        require(presale.presaleEnded(), "Presale must be ended to test claiming");
        
        for (uint256 i = 0; i < users.length; i++) {
            (, uint256 expectedTokens, bool alreadyClaimed) = presale.getUserPurchases(users[i]);
            
            if (expectedTokens > 0 && !alreadyClaimed) {
                uint256 balanceBefore = presaleToken.balanceOf(users[i]);
                
                vm.prank(users[i]);
                presale.claimTokens();
                
                uint256 balanceAfter = presaleToken.balanceOf(users[i]);
                assertEq(balanceAfter - balanceBefore, expectedTokens, "Claim amount incorrect");
                assertTrue(presale.hasClaimed(users[i]), "Claim status not updated");
                
                console.log("User claimed tokens:", expectedTokens);
            }
        }
    }
    
    /// @notice Stress test the presale with many users and transactions
    /// @param presale The presale contract
    /// @param numUsers Number of users to create for stress testing
    function stressTestPresale(
        MultiTokenPresale presale,
        uint256 numUsers
    ) public {
        require(numUsers <= 50, "Too many users for test efficiency");
        
        // Start presale
        presale.startPresale(34 days);
        uint256 startTime = block.timestamp;
        
        // Create users and make purchases
        for (uint256 i = 0; i < numUsers; i++) {
            address user = makeAddr(string(abi.encodePacked("stressUser", i)));
            vm.deal(user, 1 ether);
            
            // Randomly choose purchase size (small amounts to avoid USD limits)
            uint256 ethAmount = 0.01 ether + (i % 10) * 0.001 ether;
            
            vm.prank(user);
            presale.buyWithNative{value: ethAmount}(user);
            
            // Verify user has tokens tracked
            (, uint256 tokens,) = presale.getUserPurchases(user);
            assertGt(tokens, 0, "User should have tokens allocated");
        }
        
        // Time travel to end
        vm.warp(startTime + 34 days + 1);
        presale.emergencyEndPresale();
        
        // Verify all users can claim
        for (uint256 i = 0; i < numUsers; i++) {
            address user = makeAddr(string(abi.encodePacked("stressUser", i)));
            (, uint256 tokens,) = presale.getUserPurchases(user);
            
            if (tokens > 0) {
                vm.prank(user);
                presale.claimTokens();
                assertTrue(presale.hasClaimed(user), "User should have claimed");
            }
        }
        
        console.log("Stress test completed with users:", numUsers);
    }
}