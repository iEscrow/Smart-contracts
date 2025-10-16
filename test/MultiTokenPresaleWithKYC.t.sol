// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../MultiTokenPresale.sol";
import "../SimpleKYC.sol";
import "../contracts/mocks/MockERC20.sol";

/// @title MultiTokenPresaleWithKYCTest
/// @notice Comprehensive test suite for presale with KYC integration
contract MultiTokenPresaleWithKYCTest is Test {
    
    MultiTokenPresale public presale;
    SimpleKYC public kycContract;
    MockERC20 public presaleToken;
    
    address public owner;
    address public kycSigner;
    address public user1;
    address public user2;
    address public user3;
    address public nonKYCUser;
    
    // Presale parameters
    uint256 public constant PRESALE_RATE = 666666666666666666; // 0.67 tokens per USD (18 decimals)
    uint256 public constant MAX_TOKENS = 5000000000 * 1e18; // 5B tokens
    
    function setUp() public {
        console.log("=== MultiTokenPresale with KYC Integration Test Setup ===");
        
        // Set up addresses
        owner = address(this);
        kycSigner = makeAddr("kycSigner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        nonKYCUser = makeAddr("nonKYCUser");
        
        // Deploy presale token
        presaleToken = new MockERC20("Test Presale Token", "TPT", 18, 0);
        presaleToken.mint(address(this), MAX_TOKENS);
        
        // Deploy KYC contract
        kycContract = new SimpleKYC(kycSigner);
        
        // Deploy presale contract
        presale = new MultiTokenPresale(
            address(presaleToken),
            PRESALE_RATE,
            MAX_TOKENS,
            address(kycContract)
        );
        
        // Transfer tokens to presale contract
        presaleToken.transfer(address(presale), MAX_TOKENS);
        
        console.log("Presale deployed at:", address(presale));
        console.log("KYC contract deployed at:", address(kycContract));
        console.log("Presale token deployed at:", address(presaleToken));
        
        // Give users some ETH for testing
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);
        vm.deal(nonKYCUser, 100 ether);
    }
    
    /// @notice Test basic deployment and initial state
    function test_DeploymentWithKYC() public {
        // Check presale parameters
        assertEq(address(presale.presaleToken()), address(presaleToken));
        assertEq(presale.presaleRate(), PRESALE_RATE);
        assertEq(presale.maxTokensToMint(), MAX_TOKENS);
        
        // Check KYC integration
        (address kycAddress, bool required) = presale.getKYCInfo();
        assertEq(kycAddress, address(kycContract));
        assertTrue(required);
        
        console.log("[PASS] Deployment with KYC test passed");
    }
    
    /// @notice Test KYC requirement enforcement
    function test_KYCRequirementEnforcement() public {
        // Start presale
        presale.startPresale(34 days);
        
        // Non-KYC user should not be able to purchase
        vm.prank(nonKYCUser);
        vm.expectRevert("KYC verification required");
        presale.buyWithNative{value: 1 ether}(nonKYCUser);
        
        console.log("[PASS] KYC requirement enforcement test passed");
    }
    
    /// @notice Test successful purchase with KYC verification
    function test_SuccessfulPurchaseWithKYC() public {
        // Start presale
        presale.startPresale(34 days);
        
        // Verify user1 KYC
        vm.prank(kycContract.admin());
        kycContract.adminSetVerified(user1);
        
        // Check KYC status
        assertTrue(presale.isUserKYCVerified(user1));
        
        // User1 should be able to purchase
        uint256 purchaseAmount = 1 ether;
        uint256 balanceBefore = presaleToken.balanceOf(address(presale));
        
        vm.prank(user1);
        presale.buyWithNative{value: purchaseAmount}(user1);
        
        // Verify purchase was successful
        (, uint256 totalTokens,) = presale.getUserPurchases(user1);
        assertGt(totalTokens, 0);
        assertLe(presaleToken.balanceOf(address(presale)), balanceBefore);
        
        console.log("User1 purchased tokens:", totalTokens);
        console.log("[PASS] Successful purchase with KYC test passed");
    }
    
    /// @notice Test KYC contract update functionality
    function test_KYCContractUpdate() public {
        // Deploy new KYC contract
        SimpleKYC newKYCContract = new SimpleKYC(kycSigner);
        
        // Update KYC contract
        vm.expectEmit(true, true, false, false);
        emit KYCContractUpdated(address(kycContract), address(newKYCContract));
        presale.updateKYCContract(address(newKYCContract));
        
        // Verify update
        (address kycAddress,) = presale.getKYCInfo();
        assertEq(kycAddress, address(newKYCContract));
        
        console.log("[PASS] KYC contract update test passed");
    }
    
    /// @notice Test KYC requirement toggle
    function test_KYCRequirementToggle() public {
        // Start presale
        presale.startPresale(34 days);
        
        // Initially KYC is required
        (, bool required) = presale.getKYCInfo();
        assertTrue(required);
        
        // Non-KYC user should fail
        vm.prank(nonKYCUser);
        vm.expectRevert("KYC verification required");
        presale.buyWithNative{value: 1 ether}(nonKYCUser);
        
        // Disable KYC requirement
        vm.expectEmit(false, false, false, true);
        emit KYCRequirementUpdated(false);
        presale.setKYCRequired(false);
        
        // Now non-KYC user should succeed
        vm.prank(nonKYCUser);
        presale.buyWithNative{value: 1 ether}(nonKYCUser);
        
        // Verify purchase
        (, uint256 totalTokens,) = presale.getUserPurchases(nonKYCUser);
        assertGt(totalTokens, 0);
        
        console.log("[PASS] KYC requirement toggle test passed");
    }
    
    /// @notice Test multiple users with KYC verification
    function test_MultipleUsersWithKYC() public {
        // Start presale
        presale.startPresale(34 days);
        
        // Verify multiple users
        vm.startPrank(kycContract.admin());
        kycContract.adminSetVerified(user1);
        kycContract.adminSetVerified(user2);
        kycContract.adminSetVerified(user3);
        vm.stopPrank();
        
        // All users make purchases
        vm.prank(user1);
        presale.buyWithNative{value: 1 ether}(user1);
        
        vm.prank(user2);
        presale.buyWithNative{value: 2 ether}(user2);
        
        vm.prank(user3);
        presale.buyWithNative{value: 0.5 ether}(user3);
        
        // Verify all purchases
        (, uint256 tokens1,) = presale.getUserPurchases(user1);
        (, uint256 tokens2,) = presale.getUserPurchases(user2);
        (, uint256 tokens3,) = presale.getUserPurchases(user3);
        
        assertGt(tokens1, 0);
        assertGt(tokens2, 0);
        assertGt(tokens3, 0);
        assertGt(tokens2, tokens1); // user2 should have more tokens
        assertLt(tokens3, tokens1); // user3 should have fewer tokens
        
        console.log("[PASS] Multiple users with KYC test passed");
    }
    
    /// @notice Test KYC verification with ERC20 token purchases
    function test_KYCWithERC20Purchase() public {
        // Start presale
        presale.startPresale(34 days);
        
        // Create mock USDC
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6, 0);
        usdc.mint(user1, 10000 * 1e6); // 10,000 USDC
        
        // Update USDC price in presale
        presale.setTokenPrice(address(usdc), 1 * 1e8, 6, true); // $1
        
        // Try purchase without KYC - should fail
        vm.startPrank(user1);
        usdc.approve(address(presale), 1000 * 1e6);
        vm.expectRevert("KYC verification required");
        presale.buyWithToken(address(usdc), 1000 * 1e6, user1);
        vm.stopPrank();
        
        // Verify user1 KYC
        vm.prank(kycContract.admin());
        kycContract.adminSetVerified(user1);
        
        // Now purchase should succeed
        vm.startPrank(user1);
        usdc.approve(address(presale), 1000 * 1e6);
        presale.buyWithToken(address(usdc), 1000 * 1e6, user1);
        vm.stopPrank();
        
        // Verify purchase
        (, uint256 totalTokens,) = presale.getUserPurchases(user1);
        assertGt(totalTokens, 0);
        
        console.log("[PASS] KYC with ERC20 purchase test passed");
    }
    
    /// @notice Test KYC revocation functionality
    function test_KYCRevocation() public {
        // Start presale
        presale.startPresale(34 days);
        
        // Verify user1 KYC
        vm.prank(kycContract.admin());
        kycContract.adminSetVerified(user1);
        
        // User1 makes successful purchase
        vm.prank(user1);
        presale.buyWithNative{value: 1 ether}(user1);
        
        // Revoke user1 KYC
        vm.prank(kycContract.admin());
        kycContract.adminRevokeVerified(user1);
        
        // User1 should no longer be able to purchase
        assertFalse(presale.isUserKYCVerified(user1));
        
        vm.prank(user1);
        vm.expectRevert("KYC verification required");
        presale.buyWithNative{value: 1 ether}(user1);
        
        console.log("[PASS] KYC revocation test passed");
    }
    
    /// @notice Test presale end-to-end with KYC
    function test_EndToEndPresaleWithKYC() public {
        // Deploy and setup
        assertTrue(address(presale) != address(0));
        assertTrue(address(kycContract) != address(0));
        
        // Start presale
        presale.startPresale(34 days);
        assertTrue(presale.isPresaleActive());
        
        // Verify users
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;  
        users[2] = user3;
        
        vm.startPrank(kycContract.admin());
        for (uint256 i = 0; i < users.length; i++) {
            kycContract.adminSetVerified(users[i]);
        }
        vm.stopPrank();
        
        // Users make purchases
        for (uint256 i = 0; i < users.length; i++) {
            vm.prank(users[i]);
            presale.buyWithNative{value: (i + 1) * 0.5 ether}(users[i]);
        }
        
        // Verify all have tokens
        uint256 totalTokensSold = 0;
        for (uint256 i = 0; i < users.length; i++) {
            (, uint256 tokens,) = presale.getUserPurchases(users[i]);
            assertGt(tokens, 0);
            totalTokensSold += tokens;
        }
        
        assertEq(presale.totalTokensMinted(), totalTokensSold);
        console.log("Total tokens sold:", totalTokensSold);
        
        // End presale
        vm.warp(block.timestamp + 35 days);
        presale.checkAutoEndConditions();
        assertTrue(presale.presaleEnded());
        
        // Users can claim tokens
        for (uint256 i = 0; i < users.length; i++) {
            uint256 balanceBefore = presaleToken.balanceOf(users[i]);
            vm.prank(users[i]);
            presale.claimTokens();
            uint256 balanceAfter = presaleToken.balanceOf(users[i]);
            assertGt(balanceAfter, balanceBefore);
        }
        
        console.log("[PASS] End-to-end presale with KYC test passed");
    }
    
    /// @notice Test admin access control for KYC functions
    function test_AdminAccessControlForKYC() public {
        // Non-owner should not be able to update KYC contract
        vm.prank(user1);
        vm.expectRevert();
        presale.updateKYCContract(makeAddr("newKYC"));
        
        // Non-owner should not be able to toggle KYC requirement
        vm.prank(user1);
        vm.expectRevert();
        presale.setKYCRequired(false);
        
        console.log("[PASS] Admin access control for KYC test passed");
    }
    
    // Events for testing
    event KYCContractUpdated(address indexed oldContract, address indexed newContract);
    event KYCRequirementUpdated(bool required);
}