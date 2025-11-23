// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {MultiTokenPresale} from "../contracts/MultiTokenPresale.sol";
import {EscrowToken} from "../contracts/EscrowToken.sol";
import {DevTreasury} from "../contracts/DevTreasury.sol";
import {Authorizer} from "../contracts/Authorizer.sol";

contract AutoStartAndVestingTest is Test {
    MultiTokenPresale public presale;
    EscrowToken public token;
    DevTreasury public devTreasury;
    Authorizer public authorizer;
    
    address public owner = 0xd81d23f2e37248F8fda5e7BF0a6c047AE234F0A2;
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    uint256 public signerPrivateKey = 0x1234567890123456789012345678901234567890123456789012345678901234;
    address public signer;
    
    uint256 public constant PRESALE_RATE = 66666666666666666667; // 66.67 tokens per USD = $0.015 per token
    uint256 public constant MAX_TOKENS = 5_000_000_000 * 1e18; // 5 billion
    uint256 public constant PRESALE_LAUNCH_DATE = 1763856000; // Nov 23, 2025 00:00 UTC
    
    function setUp() public {
        signer = vm.addr(signerPrivateKey);
        
        vm.startPrank(owner);
        
        // Deploy contracts
        token = new EscrowToken();
        devTreasury = new DevTreasury(owner);
        authorizer = new Authorizer(signer, owner);
        
        presale = new MultiTokenPresale(
            address(token),
            PRESALE_RATE,
            MAX_TOKENS,
            address(devTreasury)
        );
        
        // Update authorizer with presale address
        presale.updateAuthorizer(address(authorizer));
        presale.setVoucherSystemEnabled(true);
        
        // Mint and send tokens to presale
        token.mintPresaleAllocation(address(presale));
        
        vm.stopPrank();
        
        // Fund users
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
    }
    
    // ============ AUTO-START TESTS ============
    
    /// @notice Test that presale auto-starts at deployment
    function test_AutoStartPresaleAtDeployment() public {
        assertEq(presale.escrowPresaleStartTime(), PRESALE_LAUNCH_DATE, "Start time should be set");
        assertEq(presale.escrowCurrentRound(), 1, "Should be in round 1");
        assertEq(presale.escrowPresaleEnded(), false, "Should not be ended");
        assertEq(
            presale.escrowPresaleEndTime(), 
            PRESALE_LAUNCH_DATE + 34 days, 
            "End time should be start + 34 days"
        );
        assertEq(
            presale.escrowRound1EndTime(),
            PRESALE_LAUNCH_DATE + 23 days,
            "Round 1 should end after 23 days"
        );
    }
    
    /// @notice Test that presale is active after launch date
    function test_PresaleActiveAfterLaunchDate() public {
        // Warp to launch date
        vm.warp(PRESALE_LAUNCH_DATE + 1);
        
        assertTrue(presale.isPresaleActive(), "Presale should be active");
    }
    
    /// @notice Test that presale is not active before launch date
    function test_PresaleNotActiveBeforeLaunchDate() public {
        // Warp to before launch date
        vm.warp(PRESALE_LAUNCH_DATE - 1 days);
        
        assertFalse(presale.isPresaleActive(), "Presale should not be active yet");
    }
    
    // ============ VESTING TESTS ============
    
    /// @notice Test TGE auto-set when presale ends
    function test_TGEAutoSetOnPresaleEnd() public {
        vm.warp(PRESALE_LAUNCH_DATE + 35 days);
        
        vm.prank(owner);
        presale.endEscrowPresale();
        
        uint256 tgeTimestamp = presale.escrowPresaleEndTime();
        assertGt(tgeTimestamp, 0, "TGE timestamp should be set");
        assertEq(tgeTimestamp, block.timestamp, "TGE should equal block timestamp");
    }
    
    /// @notice Test TGE auto-set on emergency end
    function test_TGEAutoSetOnEmergencyEnd() public {
        vm.warp(PRESALE_LAUNCH_DATE + 1 days);
        
        vm.prank(owner);
        presale.emergencyEndEscrowPresale();
        
        uint256 tgeTimestamp = presale.escrowPresaleEndTime();
        assertGt(tgeTimestamp, 0, "TGE timestamp should be set");
    }
    
    /// @notice Helper function to make a purchase for testing
    function _makePurchase(address user, uint256 amount) internal {
        vm.warp(PRESALE_LAUNCH_DATE + 1 days);
        
        uint256 userNonce = authorizer.getNonce(user);
        
        Authorizer.Voucher memory voucher = Authorizer.Voucher({
            buyer: user,
            beneficiary: user,
            paymentToken: address(0), // Native ETH
            usdLimit: 1000000 * 1e8, // $1M limit
            nonce: userNonce,
            deadline: block.timestamp + 1 days,
            presale: address(presale)
        });
        
        // Generate EIP-712 signature
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
        bytes memory signature = abi.encodePacked(r, s, v);
        
        vm.prank(user);
        presale.buyWithNativeVoucher{value: amount}(user, voucher, signature);
    }
    
    /// @notice Test 25% claimable at TGE
    function test_Claim25PercentAtTGE() public {
        // Make purchase
        _makePurchase(user1, 1 ether);
        
        uint256 purchased = presale.totalPurchased(user1);
        
        // End presale (auto-sets TGE)
        vm.warp(PRESALE_LAUNCH_DATE + 35 days);
        vm.prank(owner);
        presale.endEscrowPresale();
        
        // Claim at TGE
        vm.prank(user1);
        presale.claimTokens();
        
        uint256 claimed = presale.claimedAmount(user1);
        uint256 expected = (purchased * 25) / 100;
        
        assertEq(claimed, expected, "Should claim 25% at TGE");
        assertEq(token.balanceOf(user1), expected, "Token balance should match claimed amount");
    }
    
    /// @notice Test cannot claim before TGE
    function test_CannotClaimBeforeTGE() public {
        _makePurchase(user1, 1 ether);
        
        // Don't end presale, so TGE not set
        vm.warp(PRESALE_LAUNCH_DATE + 35 days);
        
        vm.prank(user1);
        vm.expectRevert("No presale ended yet");
        presale.claimTokens();
    }
    
    /// @notice Test 50% claimable after 30 days
    function test_Claim50PercentAfter30Days() public {
        _makePurchase(user1, 1 ether);
        
        uint256 purchased = presale.totalPurchased(user1);
        
        // End presale
        vm.warp(PRESALE_LAUNCH_DATE + 35 days);
        vm.prank(owner);
        presale.endEscrowPresale();
        uint256 tgeTime = presale.escrowPresaleEndTime();
        
        // Claim at TGE (25%)
        vm.prank(user1);
        presale.claimTokens();
        
        // Wait 30 days
        vm.warp(tgeTime + 30 days);
        
        // Claim again (should get another 25%)
        vm.prank(user1);
        presale.claimTokens();
        
        uint256 claimed = presale.claimedAmount(user1);
        uint256 expected = (purchased * 50) / 100;
        
        assertEq(claimed, expected, "Should have claimed 50% total after 30 days");
    }
    
    /// @notice Test 75% claimable after 60 days
    function test_Claim75PercentAfter60Days() public {
        _makePurchase(user1, 1 ether);
        
        uint256 purchased = presale.totalPurchased(user1);
        
        // End presale
        vm.warp(PRESALE_LAUNCH_DATE + 35 days);
        vm.prank(owner);
        presale.endEscrowPresale();
        uint256 tgeTime = presale.escrowPresaleEndTime();
        
        // Claim at TGE
        vm.prank(user1);
        presale.claimTokens();
        
        // Wait 60 days and claim all at once
        vm.warp(tgeTime + 60 days);
        
        vm.prank(user1);
        presale.claimTokens();
        
        uint256 claimed = presale.claimedAmount(user1);
        uint256 expected = (purchased * 75) / 100;
        
        assertEq(claimed, expected, "Should have claimed 75% total after 60 days");
    }
    
    /// @notice Test 100% claimable after 90 days
    function test_Claim100PercentAfter90Days() public {
        _makePurchase(user1, 1 ether);
        
        uint256 purchased = presale.totalPurchased(user1);
        
        // End presale
        vm.warp(PRESALE_LAUNCH_DATE + 35 days);
        vm.prank(owner);
        presale.endEscrowPresale();
        uint256 tgeTime = presale.escrowPresaleEndTime();
        
        // Wait 90 days and claim all
        vm.warp(tgeTime + 90 days);
        
        vm.prank(user1);
        presale.claimTokens();
        
        uint256 claimed = presale.claimedAmount(user1);
        
        assertEq(claimed, purchased, "Should claim 100% after 90 days");
        assertEq(token.balanceOf(user1), purchased, "Should have all tokens");
    }
    
    /// @notice Test cannot claim more than available
    function test_CannotClaimMoreThanAvailable() public {
        _makePurchase(user1, 1 ether);
        
        // End presale
        vm.warp(PRESALE_LAUNCH_DATE + 35 days);
        vm.prank(owner);
        presale.endEscrowPresale();
        
        // Claim at TGE
        vm.prank(user1);
        presale.claimTokens();
        
        // Try to claim again immediately (nothing available)
        vm.prank(user1);
        vm.expectRevert("No tokens available to claim yet");
        presale.claimTokens();
    }
    
    /// @notice Test getVestingInfo returns correct data
    function test_GetVestingInfo() public {
        _makePurchase(user1, 1 ether);
        
        uint256 purchased = presale.totalPurchased(user1);
        
        // End presale
        vm.warp(PRESALE_LAUNCH_DATE + 35 days);
        vm.prank(owner);
        presale.endEscrowPresale();
        uint256 tgeTime = presale.escrowPresaleEndTime();
        
        // Check vesting info at TGE
        (
            uint256 totalAllocation,
            uint256 claimedSoFar,
            uint256 claimableNow,
            uint256 nextUnlockTime,
            uint256 nextUnlockAmount,
            uint256 fullyVestedTime
        ) = presale.getVestingInfo(user1);
        
        assertEq(totalAllocation, purchased, "Total allocation should match purchased");
        assertEq(claimedSoFar, 0, "Nothing claimed yet");
        assertEq(claimableNow, (purchased * 25) / 100, "25% claimable at TGE");
        assertEq(nextUnlockTime, tgeTime + 30 days, "Next unlock in 30 days");
        assertEq(fullyVestedTime, tgeTime + 90 days, "Fully vested in 90 days");
    }
    
    /// @notice Test multiple users can claim independently
    function test_MultipleUsersVestingIndependent() public {
        _makePurchase(user1, 1 ether);
        _makePurchase(user2, 2 ether);
        
        uint256 purchased1 = presale.totalPurchased(user1);
        uint256 purchased2 = presale.totalPurchased(user2);
        
        // End presale
        vm.warp(PRESALE_LAUNCH_DATE + 35 days);
        vm.prank(owner);
        presale.endEscrowPresale();
        
        // User1 claims at TGE
        vm.prank(user1);
        presale.claimTokens();
        
        // User2 waits 30 days
        vm.warp(presale.escrowPresaleEndTime() + 30 days);
        vm.prank(user2);
        presale.claimTokens();
        
        // Check balances
        assertEq(presale.claimedAmount(user1), (purchased1 * 25) / 100, "User1 claimed 25%");
        assertEq(presale.claimedAmount(user2), (purchased2 * 50) / 100, "User2 claimed 50%");
    }
    
    /// @notice Test claiming after each vesting period
    function test_ClaimAtEachVestingPeriod() public {
        _makePurchase(user1, 1 ether);
        
        uint256 purchased = presale.totalPurchased(user1);
        
        // End presale
        vm.warp(PRESALE_LAUNCH_DATE + 35 days);
        vm.prank(owner);
        presale.endEscrowPresale();
        uint256 tgeTime = presale.escrowPresaleEndTime();
        
        // Claim at TGE (25%)
        vm.prank(user1);
        presale.claimTokens();
        assertEq(presale.claimedAmount(user1), (purchased * 25) / 100, "25% after TGE");
        
        // Claim after 30 days (another 25%)
        vm.warp(tgeTime + 30 days);
        vm.prank(user1);
        presale.claimTokens();
        assertEq(presale.claimedAmount(user1), (purchased * 50) / 100, "50% after 30 days");
        
        // Claim after 60 days (another 25%)
        vm.warp(tgeTime + 60 days);
        vm.prank(user1);
        presale.claimTokens();
        assertEq(presale.claimedAmount(user1), (purchased * 75) / 100, "75% after 60 days");
        
        // Claim after 90 days (final 25%)
        vm.warp(tgeTime + 90 days);
        vm.prank(user1);
        presale.claimTokens();
        assertEq(presale.claimedAmount(user1), purchased, "100% after 90 days");
    }
    
    /// @notice Test cannot claim after all tokens claimed
    function test_CannotClaimAfterFullyClaimed() public {
        _makePurchase(user1, 1 ether);
        
        // End presale
        vm.warp(PRESALE_LAUNCH_DATE + 35 days);
        vm.prank(owner);
        presale.endEscrowPresale();
        
        // Wait 90 days and claim all
        vm.warp(presale.escrowPresaleEndTime() + 90 days);
        vm.prank(user1);
        presale.claimTokens();
        
        // Try to claim again
        vm.prank(user1);
        vm.expectRevert("All tokens already claimed");
        presale.claimTokens();
    }
    
    /// @notice Test vesting info after partial claims
    function test_VestingInfoAfterPartialClaims() public {
        _makePurchase(user1, 1 ether);
        
        uint256 purchased = presale.totalPurchased(user1);
        
        // End presale
        vm.warp(PRESALE_LAUNCH_DATE + 35 days);
        vm.prank(owner);
        presale.endEscrowPresale();
        uint256 tgeTime = presale.escrowPresaleEndTime();
        
        // Claim at TGE
        vm.prank(user1);
        presale.claimTokens();
        
        // Check vesting info after first claim
        vm.warp(tgeTime + 15 days); // Halfway to next unlock
        
        (
            uint256 totalAllocation,
            uint256 claimedSoFar,
            uint256 claimableNow,
            ,
            ,
            
        ) = presale.getVestingInfo(user1);
        
        assertEq(totalAllocation, purchased, "Total allocation unchanged");
        assertEq(claimedSoFar, (purchased * 25) / 100, "25% claimed");
        assertEq(claimableNow, 0, "Nothing claimable yet");
    }
}
