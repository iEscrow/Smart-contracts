// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../Authorizer.sol";
import "../MultiTokenPresale.sol";
import "../EscrowToken.sol";

/// @title MultiTokenPresale Test Suite
/// @notice Tests core presale functionality (rounds, timing, purchases) using voucher system
contract MultiTokenPresaleTest is Test {
    Authorizer public authorizer;
    MultiTokenPresale public presale;
    EscrowToken public escrowToken;
    
    address public owner = address(0x1);
    address public buyer1 = address(0x3);
    address public buyer2 = address(0x4);
    
    uint256 public signerPrivateKey = 0xB0B;
    address public signer = vm.addr(signerPrivateKey);
    
    // Test constants
    uint256 constant PRESALE_RATE = 666666666666666666; // 666.666... tokens per USD
    uint256 constant MAX_TOKENS = 5000000000 * 1e18; // 5B tokens
    uint256 constant PRESALE_LAUNCH_DATE = 1762819200; // Nov 11, 2025
    uint256 constant VOUCHER_LIMIT = 10000 * 1e8; // $10000 limit
    
    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy contracts
        escrowToken = new EscrowToken();
        authorizer = new Authorizer(signer, owner);
        
        presale = new MultiTokenPresale(
            address(escrowToken),
            PRESALE_RATE,
            MAX_TOKENS
        );
        
        // Set up presale
        escrowToken.mint(address(presale), MAX_TOKENS);
        presale.updateAuthorizer(address(authorizer));
        presale.setVoucherSystemEnabled(true);
        
        vm.stopPrank();
        
        // Give buyers ETH
        vm.deal(buyer1, 100 ether);
        vm.deal(buyer2, 100 ether);
    }
    
    // ========== PRESALE LIFECYCLE TESTS ==========
    
    function testPresaleNotStartedInitially() public {
        (bool started, bool ended,,,) = presale.getPresaleStatus();
        assertFalse(started);
        assertFalse(ended);
        assertEq(presale.currentRound(), 0);
    }
    
    function testAutoStartPresale() public {
        // Warp to launch date
        vm.warp(PRESALE_LAUNCH_DATE + 1);
        
        // Anyone can trigger auto-start
        vm.prank(buyer1);
        presale.autoStartIEscrowPresale();
        
        // Verify presale started
        (bool started, bool ended,,,) = presale.getPresaleStatus();
        assertTrue(started);
        assertFalse(ended);
        assertEq(presale.currentRound(), 1);
    }
    
    function testCannotStartBeforeLaunchDate() public {
        vm.warp(PRESALE_LAUNCH_DATE - 1);
        
        vm.expectRevert("Too early - presale starts Nov 11, 2025");
        presale.autoStartIEscrowPresale();
    }
    
    function testCannotPurchaseBeforeStart() public {
        Authorizer.Voucher memory voucher = _createVoucher(buyer1, buyer1, address(0), 0);
        bytes memory signature = _signVoucher(voucher);
        
        vm.expectRevert("Presale not started");
        vm.prank(buyer1);
        presale.buyWithNativeVoucher{value: 0.01 ether}(buyer1, voucher, signature);
    }
    
    // ========== ROUND MANAGEMENT TESTS ==========
    
    function testRound1Duration() public {
        _startPresale();
        
        // Check we're in round 1
        assertEq(presale.currentRound(), 1);
        
        // Warp to end of round 1
        vm.warp(block.timestamp + 23 days);
        
        // Make a purchase to trigger round check
        _makePurchase(buyer1, 0.001 ether, 0);
        
        // Should auto-advance to round 2
        assertEq(presale.currentRound(), 2);
    }
    
    function testManualRoundAdvancement() public {
        _startPresale();
        
        assertEq(presale.currentRound(), 1);
        
        // Owner can manually advance
        vm.prank(owner);
        presale.moveToRound2();
        
        assertEq(presale.currentRound(), 2);
    }
    
    function testPresaleAutoEndsAfter34Days() public {
        _startPresale();
        uint256 startTime = block.timestamp;
        
        // Presale should be active
        assertTrue(presale.isPresaleActive());
        
        // Warp past 34 days
        vm.warp(startTime + 34 days + 1);
        
        // Check presale is considered ended
        assertFalse(presale.isPresaleActive());
    }
    
    // ========== PURCHASE TESTS ==========
    
    function testSuccessfulPurchaseRound1() public {
        _startPresale();
        
        uint256 purchaseAmount = 0.01 ether;
        _makePurchase(buyer1, purchaseAmount, 0);
        
        // Verify tokens allocated
        assertTrue(presale.totalPurchased(buyer1) > 0);
        
        // Verify round 1 tracking
        assertTrue(presale.round1TokensSold() > 0);
        assertEq(presale.round2TokensSold(), 0);
    }
    
    function testSuccessfulPurchaseRound2() public {
        _startPresale();
        
        // Move to round 2
        vm.prank(owner);
        presale.moveToRound2();
        
        _makePurchase(buyer1, 0.01 ether, 0);
        
        // Verify round 2 tracking
        assertTrue(presale.round2TokensSold() > 0);
    }
    
    function testMultipleBuyers() public {
        _startPresale();
        
        // Buyer 1 purchases
        _makePurchase(buyer1, 0.001 ether, 0);
        uint256 buyer1Tokens = presale.totalPurchased(buyer1);
        
        // Buyer 2 purchases
        _makePurchase(buyer2, 0.001 ether, 0);
        uint256 buyer2Tokens = presale.totalPurchased(buyer2);
        
        // Both should have tokens
        assertTrue(buyer1Tokens > 0);
        assertTrue(buyer2Tokens > 0);
        
        // Total minted should equal sum
        assertEq(presale.totalTokensMinted(), buyer1Tokens + buyer2Tokens);
    }
    
    function testMultiplePurchasesSameBuyer() public {
        _startPresale();
        
        // First purchase
        _makePurchase(buyer1, 0.001 ether, 0);
        uint256 tokensAfterFirst = presale.totalPurchased(buyer1);
        
        // Second purchase (nonce 1)
        _makePurchase(buyer1, 0.001 ether, 1);
        uint256 tokensAfterSecond = presale.totalPurchased(buyer1);
        
        // Tokens should accumulate
        assertTrue(tokensAfterSecond > tokensAfterFirst);
    }
    
    // ========== TOKEN LIMITS TESTS ==========
    
    function testRemainingTokens() public {
        _startPresale();
        
        assertEq(presale.getRemainingTokens(), MAX_TOKENS);
        
        _makePurchase(buyer1, 0.01 ether, 0);
        
        assertTrue(presale.getRemainingTokens() < MAX_TOKENS);
    }
    
    function testTotalTokensMinted() public {
        _startPresale();
        
        assertEq(presale.totalTokensMinted(), 0);
        
        _makePurchase(buyer1, 0.01 ether, 0);
        
        assertTrue(presale.totalTokensMinted() > 0);
    }
    
    // ========== CLAIM TESTS ==========
    
    function testCannotClaimBeforePresaleEnds() public {
        _startPresale();
        _makePurchase(buyer1, 0.01 ether, 0);
        
        vm.expectRevert("Presale not ended yet");
        vm.prank(buyer1);
        presale.claimTokens();
    }
    
    function testClaimAfterPresaleEnds() public {
        _startPresale();
        _makePurchase(buyer1, 0.01 ether, 0);
        
        uint256 purchasedTokens = presale.totalPurchased(buyer1);
        
        // End presale
        vm.warp(block.timestamp + 34 days + 1);
        vm.prank(owner);
        presale.endPresale();
        
        // Claim tokens
        vm.prank(buyer1);
        presale.claimTokens();
        
        // Verify tokens received
        assertEq(escrowToken.balanceOf(buyer1), purchasedTokens);
        assertTrue(presale.hasClaimed(buyer1));
    }
    
    function testCannotClaimTwice() public {
        _startPresale();
        _makePurchase(buyer1, 0.01 ether, 0);
        
        // End and claim
        vm.warp(block.timestamp + 34 days + 1);
        vm.prank(owner);
        presale.endPresale();
        
        vm.prank(buyer1);
        presale.claimTokens();
        
        // Try to claim again
        vm.expectRevert("Already claimed");
        vm.prank(buyer1);
        presale.claimTokens();
    }
    
    // ========== ADMIN TESTS ==========
    
    function testEmergencyEndPresale() public {
        _startPresale();
        
        vm.prank(owner);
        presale.emergencyEndPresale();
        
        (, bool ended,,,) = presale.getPresaleStatus();
        assertTrue(ended);
    }
    
    function testPauseAndUnpause() public {
        _startPresale();
        
        // Pause
        vm.prank(owner);
        presale.pause();
        
        // Cannot purchase when paused
        Authorizer.Voucher memory voucher = _createVoucher(buyer1, buyer1, address(0), 0);
        bytes memory signature = _signVoucher(voucher);
        
        vm.expectRevert();
        vm.prank(buyer1);
        presale.buyWithNativeVoucher{value: 0.01 ether}(buyer1, voucher, signature);
        
        // Unpause
        vm.prank(owner);
        presale.unpause();
        
        // Can purchase again
        _makePurchase(buyer1, 0.001 ether, 0);
        assertTrue(presale.totalPurchased(buyer1) > 0);
    }
    
    // ========== HELPER FUNCTIONS ==========
    
    function _startPresale() internal {
        vm.warp(PRESALE_LAUNCH_DATE + 1);
        presale.autoStartIEscrowPresale();
    }
    
    function _createVoucher(
        address buyer,
        address beneficiary,
        address paymentToken,
        uint256 nonce
    ) internal view returns (Authorizer.Voucher memory) {
        return Authorizer.Voucher({
            buyer: buyer,
            beneficiary: beneficiary,
            paymentToken: paymentToken,
            usdLimit: VOUCHER_LIMIT,
            nonce: nonce,
            deadline: type(uint256).max,
            presale: address(presale)
        });
    }
    
    function _signVoucher(Authorizer.Voucher memory voucher) internal view returns (bytes memory) {
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
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        return abi.encodePacked(r, s, v);
    }
    
    function _makePurchase(address buyer, uint256 amount, uint256 nonce) internal {
        Authorizer.Voucher memory voucher = _createVoucher(buyer, buyer, address(0), nonce);
        bytes memory signature = _signVoucher(voucher);
        
        vm.prank(buyer);
        presale.buyWithNativeVoucher{value: amount}(buyer, voucher, signature);
    }
}