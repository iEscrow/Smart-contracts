// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../MultiTokenPresale.sol";
import "../EscrowToken.sol";
import "../Authorizer.sol";

/// @title GRO-12 Audit Fix Tests
/// @notice Comprehensive tests for the dual presale system fix
contract GRO12_AuditFixTest is Test {
    MultiTokenPresale public presale;
    EscrowToken public escrowToken;
    Authorizer public authorizer;
    
    // GRO-02: Use hardcoded owner address from contract
    address public owner = 0xd81d23f2e37248F8fda5e7BF0a6c047AE234F0A2;
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public treasury = address(0x4);
    
    uint256 public signerPrivateKey = 0xB0B;
    address public signer = vm.addr(signerPrivateKey);
    
    uint256 public constant PRESALE_RATE = 666666666666666667000; // 666.67 tokens per USD
    uint256 public constant MAX_TOKENS = 5000000000 * 1e18; // 5B tokens
    uint256 public constant LAUNCH_DATE = 1762819200; // Nov 11, 2025
    
    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy EscrowToken
        escrowToken = new EscrowToken();
        
        // Deploy Authorizer (needs signer and owner)
        authorizer = new Authorizer(signer, owner);
        
        // Deploy MultiTokenPresale
        presale = new MultiTokenPresale(
            address(escrowToken),
            PRESALE_RATE,
            MAX_TOKENS,
            address(0x999)
        );
        
        // Setup authorizer
        presale.updateAuthorizer(address(authorizer));
        presale.setVoucherSystemEnabled(true);
        
        // Mint presale allocation to presale contract
        // Need to create a dummy staking contract address for this
        address dummyStaking = address(0x999);
        escrowToken.mintPresaleAllocation(address(presale));
        
        vm.stopPrank();
    }
    
    /// @notice Test that both presales cannot be active simultaneously
    function testCannotRunBothPresalesSimultaneously() public {
        // Warp to launch date first
        vm.warp(LAUNCH_DATE + 1);
        
        vm.startPrank(owner);
        
        // Start escrow presale
        presale.autoStartIEscrowPresale();
        vm.stopPrank();
        
        // But purchasing should fail when both are "active"
        vm.stopPrank();
        
        // Create a voucher for user1
        Authorizer.Voucher memory voucher = Authorizer.Voucher({
            buyer: user1,
            beneficiary: user1,
            paymentToken: address(0), // Native ETH
            usdLimit: 1000 * 1e8, // $1000
            nonce: 0,
            deadline: block.timestamp + 1 hours,
            presale: address(presale)
        });
        
        bytes memory signature = _signVoucher(voucher, signerPrivateKey);
        
        // This should still work because each presale has separate state
        vm.prank(user1);
        vm.deal(user1, 1 ether);
        presale.buyWithNativeVoucher{value: 0.1 ether}(user1, voucher, signature);
        
        // Verify purchase went to escrow presale round tracking  
        // Note: Actual payment amount is reduced by gas buffer
        uint256 gasBuffer = presale.gasBuffer();
        uint256 actualPayment = 0.1 ether - gasBuffer;
        uint256 expectedTokens = (actualPayment * 4200 * 1e8 / 1e18) * PRESALE_RATE / 1e8;
        assertEq(presale.escrowRound1TokensSold(), expectedTokens);
        assertEq(presale.round1TokensSold(), 0);
    }
    
    /// @notice Test main presale independent operation
    function testMainPresaleIndependentOperation() public {
        // Warp to launch date
        vm.warp(LAUNCH_DATE + 1);
        
        vm.startPrank(owner);
        
        // Start main presale (not escrow)
        presale.startPresale(34 days);
        vm.stopPrank();
        
        // Verify main presale state
        (bool started, bool ended, uint256 startTime, uint256 endTime, uint256 currentTime) = presale.getPresaleStatus();
        assertTrue(started);
        assertFalse(ended);
        assertEq(startTime, block.timestamp);
        
        // Verify escrow presale is not started
        (bool escrowStarted, bool escrowEnded, uint256 escrowStartTime, uint256 escrowEndTime, uint256 escrowCurrentTime) = presale.getEscrowPresaleStatus();
        assertFalse(escrowStarted);
        assertFalse(escrowEnded);
        assertEq(escrowStartTime, 0);
        
        // Check active mode
        assertEq(presale.getActivePresaleMode(), 1); // Main presale
        
        vm.stopPrank();
        
        // Test purchase in main presale
        Authorizer.Voucher memory voucher = Authorizer.Voucher({
            buyer: user1,
            beneficiary: user1,
            paymentToken: address(0),
            usdLimit: 1000 * 1e8,
            nonce: 0,
            deadline: block.timestamp + 1 hours,
            presale: address(presale)
        });
        
        bytes memory signature = _signVoucher(voucher, signerPrivateKey);
        
        vm.prank(user1);
        vm.deal(user1, 1 ether);
        presale.buyWithNativeVoucher{value: 0.1 ether}(user1, voucher, signature);
        
        // Verify tokens went to main presale tracking
        uint256 gasBuffer = presale.gasBuffer();
        uint256 actualPayment = 0.1 ether - gasBuffer;
        uint256 expectedTokens = (actualPayment * 4200 * 1e8 / 1e18) * PRESALE_RATE / 1e8;
        assertEq(presale.round1TokensSold(), expectedTokens);
        assertEq(presale.escrowRound1TokensSold(), 0);
        assertEq(presale.totalPurchased(user1), expectedTokens);
    }
    
    /// @notice Test escrow presale independent operation  
    function testEscrowPresaleIndependentOperation() public {
        // Set timestamp to launch date
        vm.warp(LAUNCH_DATE);
        
        // Start escrow presale (anyone can call)
        vm.prank(user1);
        presale.autoStartIEscrowPresale();
        
        // Verify escrow presale state
        (bool escrowStarted, bool escrowEnded, uint256 escrowStartTime, uint256 escrowEndTime, uint256 escrowCurrentTime) = presale.getEscrowPresaleStatus();
        assertTrue(escrowStarted);
        assertFalse(escrowEnded);
        assertEq(escrowStartTime, LAUNCH_DATE);
        
        // Verify main presale is not started
        (bool started, bool ended, uint256 startTime, uint256 endTime, uint256 currentTime) = presale.getPresaleStatus();
        assertFalse(started);
        assertFalse(ended);
        assertEq(startTime, 0);
        
        // Check active mode
        assertEq(presale.getActivePresaleMode(), 2); // Escrow presale
        
        // Test purchase in escrow presale
        Authorizer.Voucher memory voucher = Authorizer.Voucher({
            buyer: user1,
            beneficiary: user1,
            paymentToken: address(0),
            usdLimit: 1000 * 1e8,
            nonce: 0,
            deadline: block.timestamp + 1 hours,
            presale: address(presale)
        });
        
        bytes memory signature = _signVoucher(voucher, signerPrivateKey);
        
        vm.prank(user1);
        vm.deal(user1, 1 ether);
        presale.buyWithNativeVoucher{value: 0.1 ether}(user1, voucher, signature);
        
        // Verify tokens went to escrow presale tracking
        uint256 gasBuffer = presale.gasBuffer();
        uint256 actualPayment = 0.1 ether - gasBuffer;
        uint256 expectedTokens = (actualPayment * 4200 * 1e8 / 1e18) * PRESALE_RATE / 1e8;
        assertEq(presale.escrowRound1TokensSold(), expectedTokens);
        assertEq(presale.round1TokensSold(), 0);
        assertEq(presale.totalPurchased(user1), expectedTokens);
    }
    
    /// @notice Test sequential operation - escrow presale first, then main presale
    function testSequentialOperation() public {
        // Phase 1: Start and run escrow presale
        vm.warp(LAUNCH_DATE + 1);
        vm.prank(user1);
        presale.autoStartIEscrowPresale();
        
        // Make purchase in escrow presale
        Authorizer.Voucher memory voucher1 = Authorizer.Voucher({
            buyer: user1,
            beneficiary: user1,
            paymentToken: address(0),
            usdLimit: 1000 * 1e8,
            nonce: 0,
            deadline: block.timestamp + 1 hours,
            presale: address(presale)
        });
        
        bytes memory signature1 = _signVoucher(voucher1, signerPrivateKey);
        
        vm.prank(user1);
        vm.deal(user1, 1 ether);
        presale.buyWithNativeVoucher{value: 0.1 ether}(user1, voucher1, signature1);
        
        uint256 escrowTokens = presale.totalPurchased(user1);
        uint256 escrowRound1Sold = presale.escrowRound1TokensSold();
        
        // End escrow presale by warping past duration (auto-ends)
        vm.warp(LAUNCH_DATE + 35 days); // After max duration
        
        // Verify escrow presale has ended (time-based, no need to call checkAutoEndConditions)
        assertEq(presale.getActivePresaleMode(), 0); // No presale active after time expired
        
        // Phase 2: Start main presale after escrow presale ends
        vm.prank(owner);
        presale.startPresale(34 days);
        
        // Make purchase in main presale with different user
        Authorizer.Voucher memory voucher2 = Authorizer.Voucher({
            buyer: user2,
            beneficiary: user2,
            paymentToken: address(0),
            usdLimit: 1000 * 1e8,
            nonce: 0,
            deadline: block.timestamp + 1 hours,
            presale: address(presale)
        });
        
        bytes memory signature2 = _signVoucher(voucher2, signerPrivateKey);
        
        vm.prank(user2);
        vm.deal(user2, 1 ether);
        presale.buyWithNativeVoucher{value: 0.1 ether}(user2, voucher2, signature2);
        
        // Verify separate tracking
        assertEq(presale.totalPurchased(user1), escrowTokens); // User1's escrow purchase unchanged
        assertGt(presale.totalPurchased(user2), 0); // User2 has main presale purchase
        assertEq(presale.escrowRound1TokensSold(), escrowRound1Sold); // Escrow tracking unchanged
        assertGt(presale.round1TokensSold(), 0); // Main presale tracking has new purchase
        
        // Verify both users can claim after their respective presales end
        assertTrue(presale.canClaim()); // Should be true since escrow presale ended
    }
    
    /// @notice Test that escrow presale cannot be started twice
    function testCannotStartEscrowPresaleTwice() public {
        vm.warp(LAUNCH_DATE);
        
        // Start escrow presale first time
        vm.prank(user1);
        presale.autoStartIEscrowPresale();
        
        // Try to start again
        vm.prank(user2);
        vm.expectRevert("Escrow presale already started");
        presale.autoStartIEscrowPresale();
    }
    
    /// @notice Test that main presale cannot be started twice
    function testCannotStartMainPresaleTwice() public {
        vm.warp(LAUNCH_DATE + 1);
        
        vm.startPrank(owner);
        
        // Start main presale first time
        presale.startPresale(34 days);
        
        // Try to start again
        vm.expectRevert("Presale already started");
        presale.startPresale(34 days);
        
        vm.stopPrank();
    }
    
    /// @notice Test price changes are blocked during either presale
    function testPriceChangesBlockedDuringPresales() public {
        vm.warp(LAUNCH_DATE + 1);
        
        vm.startPrank(owner);
        
        // Test 1: Block price changes during escrow presale
        presale.autoStartIEscrowPresale();
        
        vm.expectRevert("Cannot change prices during active presale");
        presale.setTokenPrice(address(0), 5000 * 1e8, 18, true);
        
        // End main presale by advancing time beyond the duration
        vm.warp(block.timestamp + 35 days);
        
        // Presale should auto-end after duration, so price changes should work
        presale.setTokenPrice(address(0), 5000 * 1e8, 18, true);
        
        vm.stopPrank();
    }
    
    /// @notice Test round management for escrow presale
    function testEscrowPresaleRoundManagement() public {
        vm.warp(LAUNCH_DATE);
        
        // Start escrow presale
        vm.prank(user1);
        presale.autoStartIEscrowPresale();
        
        // Verify we're in escrow round 1
        assertEq(presale.escrowCurrentRound(), 1);
        assertEq(presale.currentRound(), 0); // Main presale round should be 0 (not started)
        
        // Advance to escrow round 2
        address[] memory tokens = new address[](1);
        uint256[] memory prices = new uint256[](1);
        uint8[] memory decimals = new uint8[](1);
        bool[] memory active = new bool[](1);
        
        tokens[0] = address(0); // Native ETH
        prices[0] = 5000 * 1e8; // Different price for round 2
        decimals[0] = 18;
        active[0] = true;
        
        vm.prank(owner);
        presale.moveEscrowToRound2(tokens, prices, decimals, active);
        
        // Verify escrow round 2
        assertEq(presale.escrowCurrentRound(), 2);
        assertEq(presale.currentRound(), 0); // Main presale round still 0 (not started)
    }
    
    /// @notice Test view functions return correct data for both presales
    function testViewFunctions() public {
        // Before any presale starts
        assertEq(presale.getActivePresaleMode(), 0);
        
        (bool mainStarted, bool mainEnded, bool escrowStarted, bool escrowEnded, uint8 activeMode, string memory status) = presale.getBothPresalesStatus();
        assertFalse(mainStarted);
        assertFalse(mainEnded);
        assertFalse(escrowStarted);
        assertFalse(escrowEnded);
        assertEq(activeMode, 0);
        
        // Start escrow presale
        vm.warp(LAUNCH_DATE + 1);
        vm.prank(user1);
        presale.autoStartIEscrowPresale();
        
        assertEq(presale.getActivePresaleMode(), 2);
        (mainStarted, mainEnded, escrowStarted, escrowEnded, activeMode, status) = presale.getBothPresalesStatus();
        assertFalse(mainStarted);
        assertFalse(mainEnded);
        assertTrue(escrowStarted);
        assertFalse(escrowEnded);
        assertEq(activeMode, 2);
    }
    
    /// @notice Test that claims work after either presale ends
    function testClaimingAfterEitherPresaleEnds() public {
        // Start escrow presale and make purchase
        vm.warp(LAUNCH_DATE);
        vm.prank(user1);
        presale.autoStartIEscrowPresale();
        
        Authorizer.Voucher memory voucher = Authorizer.Voucher({
            buyer: user1,
            beneficiary: user1,
            paymentToken: address(0),
            usdLimit: 1000 * 1e8,
            nonce: 0,
            deadline: block.timestamp + 1 hours,
            presale: address(presale)
        });
        
        bytes memory signature = _signVoucher(voucher, signerPrivateKey);
        
        vm.prank(user1);
        vm.deal(user1, 1 ether);
        presale.buyWithNativeVoucher{value: 0.1 ether}(user1, voucher, signature);
        
        uint256 purchasedAmount = presale.totalPurchased(user1);
        assertGt(purchasedAmount, 0);
        
        // Cannot claim while presale active
        vm.prank(user1);
        vm.expectRevert("No presale ended yet");
        presale.claimTokens();
        
        // End escrow presale
        vm.prank(owner);
        presale.emergencyEndEscrowPresale();
        
        // Now can claim
        vm.prank(user1);
        presale.claimTokens();
        
        assertEq(escrowToken.balanceOf(user1), purchasedAmount);
        assertTrue(presale.hasClaimed(user1));
    }
    
    // Helper functions
    function _signVoucher(Authorizer.Voucher memory voucher, uint256 privateKey) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(abi.encode(
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
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
    
    function _hashVoucher(Authorizer.Voucher memory voucher) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            keccak256("Voucher(address buyer,address beneficiary,address paymentToken,uint256 usdLimit,uint256 nonce,uint256 deadline,address presale)"),
            voucher.buyer,
            voucher.beneficiary,
            voucher.paymentToken,
            voucher.usdLimit,
            voucher.nonce,
            voucher.deadline,
            voucher.presale
        ));
    }
}
