// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {MultiTokenPresale} from "../contracts/MultiTokenPresale.sol";
import {EscrowToken} from "../contracts/EscrowToken.sol";
import {DevTreasury} from "../contracts/DevTreasury.sol";
import {Authorizer} from "../contracts/Authorizer.sol";

/**
 * @title DelayedClaimTest
 * @notice Test vesting calculations when users forget to claim for extended periods
 * @dev Scenarios: 1 month, 3 months, 6 months after presale end
 */
contract DelayedClaimTest is Test {
    MultiTokenPresale public presale;
    EscrowToken public token;
    DevTreasury public devTreasury;
    Authorizer public authorizer;
    
    address public owner = 0xd81d23f2e37248F8fda5e7BF0a6c047AE234F0A2;
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public user3 = address(0x3);
    uint256 public signerPrivateKey = 0x1234567890123456789012345678901234567890123456789012345678901234;
    address public signer;
    
    uint256 public constant PRESALE_RATE = 66666666666666666667; // 66.67 tokens per USD = $0.015 per token
    uint256 public constant MAX_TOKENS = 5_000_000_000 * 1e18; // 5 billion
    uint256 public constant PRESALE_LAUNCH_DATE = 1764068400; // Nov 25, 2025
    
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
        
        // Setup authorizer
        presale.updateAuthorizer(address(authorizer));
        presale.setVoucherSystemEnabled(true);
        
        // Mint tokens to presale
        token.mintPresaleAllocation(address(presale));
        
        vm.stopPrank();
        
        // Fund users
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(user3, 10 ether);
    }
    
    /// @notice Helper to make a purchase
    function _makePurchase(address user, uint256 amount) internal returns (uint256) {
        vm.warp(PRESALE_LAUNCH_DATE + 1 days);
        
        uint256 userNonce = authorizer.getNonce(user);
        
        Authorizer.Voucher memory voucher = Authorizer.Voucher({
            buyer: user,
            beneficiary: user,
            paymentToken: address(0),
            usdLimit: 1000000 * 1e8,
            nonce: userNonce,
            deadline: block.timestamp + 1 days,
            presale: address(presale)
        });
        
        // Generate signature
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
        
        return presale.totalPurchased(user);
    }
    
    /// @notice Test user claims 1 month after presale ends
    /// @dev User should get 50% (TGE 25% + 30 days 25%)
    function test_Claim1MonthAfterPresaleEnd() public {
        // User purchases during presale
        uint256 purchased = _makePurchase(user1, 1 ether);
        
        // End presale (TGE = presale end timestamp)
        vm.warp(PRESALE_LAUNCH_DATE + 35 days);
        vm.prank(owner);
        presale.endEscrowPresale();
        uint256 tgeTime = presale.escrowPresaleEndTime();
        
        // User forgets to claim for 1 month after presale end
        vm.warp(tgeTime + 30 days);
        
        // Check vesting info before claim
        (
            uint256 totalAllocation,
            uint256 claimedSoFar,
            uint256 claimableNow,
            uint256 nextUnlockTime,
            ,
            uint256 fullyVestedTime
        ) = presale.getVestingInfo(user1);
        
        assertEq(totalAllocation, purchased, "Total allocation should match");
        assertEq(claimedSoFar, 0, "Nothing claimed yet");
        assertEq(claimableNow, (purchased * 50) / 100, "Should have 50% claimable (TGE + 30 days)");
        assertEq(nextUnlockTime, tgeTime + 60 days, "Next unlock at 60 days");
        assertEq(fullyVestedTime, tgeTime + 90 days, "Fully vested at 90 days");
        
        // User claims now (should get 50% at once)
        vm.prank(user1);
        presale.claimTokens();
        
        uint256 claimed = presale.claimedAmount(user1);
        uint256 balance = token.balanceOf(user1);
        
        assertEq(claimed, (purchased * 50) / 100, "Should claim 50% total");
        assertEq(balance, claimed, "Token balance should match claimed amount");
    }
    
    /// @notice Test user claims 3 months after presale ends
    /// @dev User should get 100% (all vesting periods passed)
    function test_Claim3MonthsAfterPresaleEnd() public {
        // User purchases during presale
        uint256 purchased = _makePurchase(user2, 2 ether);
        
        // End presale
        vm.warp(PRESALE_LAUNCH_DATE + 35 days);
        vm.prank(owner);
        presale.endEscrowPresale();
        uint256 tgeTime = presale.escrowPresaleEndTime();
        
        // User forgets to claim for 3 months (90 days)
        vm.warp(tgeTime + 90 days);
        
        // Check vesting info before claim
        (
            uint256 totalAllocation,
            uint256 claimedSoFar,
            uint256 claimableNow,
            uint256 nextUnlockTime,
            ,
            uint256 fullyVestedTime
        ) = presale.getVestingInfo(user2);
        
        assertEq(totalAllocation, purchased, "Total allocation should match");
        assertEq(claimedSoFar, 0, "Nothing claimed yet");
        assertEq(claimableNow, purchased, "Should have 100% claimable (fully vested)");
        assertEq(nextUnlockTime, 0, "No next unlock (fully vested)");
        assertEq(fullyVestedTime, tgeTime + 90 days, "Fully vested at 90 days");
        
        // User claims now (should get 100% at once)
        vm.prank(user2);
        presale.claimTokens();
        
        uint256 claimed = presale.claimedAmount(user2);
        uint256 balance = token.balanceOf(user2);
        
        assertEq(claimed, purchased, "Should claim 100%");
        assertEq(balance, claimed, "Token balance should match claimed amount");
    }
    
    /// @notice Test user claims 6 months after presale ends
    /// @dev User should still get exactly 100% (not more)
    function test_Claim6MonthsAfterPresaleEnd() public {
        // User purchases during presale
        uint256 purchased = _makePurchase(user3, 0.5 ether);
        
        // End presale
        vm.warp(PRESALE_LAUNCH_DATE + 35 days);
        vm.prank(owner);
        presale.endEscrowPresale();
        uint256 tgeTime = presale.escrowPresaleEndTime();
        
        // User forgets to claim for 6 months (180 days)
        vm.warp(tgeTime + 180 days);
        
        // Check vesting info
        (
            uint256 totalAllocation,
            uint256 claimedSoFar,
            uint256 claimableNow,
            ,
            ,
            
        ) = presale.getVestingInfo(user3);
        
        assertEq(totalAllocation, purchased, "Total allocation should match");
        assertEq(claimedSoFar, 0, "Nothing claimed yet");
        assertEq(claimableNow, purchased, "Should have exactly 100% claimable (capped)");
        
        // User claims
        vm.prank(user3);
        presale.claimTokens();
        
        uint256 claimed = presale.claimedAmount(user3);
        
        assertEq(claimed, purchased, "Should claim exactly 100%, not more");
    }
    
    /// @notice Test user claims at TGE, then forgets for 3 months
    /// @dev User already claimed 25%, should get remaining 75%
    function test_ClaimAtTGEThenForget3Months() public {
        // User purchases during presale
        uint256 purchased = _makePurchase(user1, 1 ether);
        
        // End presale
        vm.warp(PRESALE_LAUNCH_DATE + 35 days);
        vm.prank(owner);
        presale.endEscrowPresale();
        uint256 tgeTime = presale.escrowPresaleEndTime();
        
        // User claims immediately at TGE
        vm.prank(user1);
        presale.claimTokens();
        
        uint256 firstClaim = presale.claimedAmount(user1);
        assertEq(firstClaim, (purchased * 25) / 100, "First claim should be 25%");
        
        // User forgets for 3 months
        vm.warp(tgeTime + 90 days);
        
        // Check vesting info
        (
            ,
            uint256 claimedSoFar,
            uint256 claimableNow,
            ,
            ,
            
        ) = presale.getVestingInfo(user1);
        
        assertEq(claimedSoFar, (purchased * 25) / 100, "Should show 25% already claimed");
        // Allow 1 wei tolerance for rounding
        assertApproxEqAbs(claimableNow, (purchased * 75) / 100, 1, "Should have 75% claimable");
        
        // User claims remaining tokens
        vm.prank(user1);
        presale.claimTokens();
        
        uint256 totalClaimed = presale.claimedAmount(user1);
        assertEq(totalClaimed, purchased, "Should have claimed 100% total");
    }
    
    /// @notice Test user claims after 45 days (between vesting periods)
    /// @dev User should get 50% (TGE + 30 days unlock, but not 60 days yet)
    function test_ClaimBetweenVestingPeriods() public {
        // User purchases during presale
        uint256 purchased = _makePurchase(user1, 1 ether);
        
        // End presale
        vm.warp(PRESALE_LAUNCH_DATE + 35 days);
        vm.prank(owner);
        presale.endEscrowPresale();
        uint256 tgeTime = presale.escrowPresaleEndTime();
        
        // User waits 45 days (between 30 and 60 day unlocks)
        vm.warp(tgeTime + 45 days);
        
        // Check vesting info
        (
            ,
            ,
            uint256 claimableNow,
            uint256 nextUnlockTime,
            uint256 nextUnlockAmount,
            
        ) = presale.getVestingInfo(user1);
        
        assertEq(claimableNow, (purchased * 50) / 100, "Should have 50% claimable");
        assertEq(nextUnlockTime, tgeTime + 60 days, "Next unlock at 60 days");
        // Allow 1 wei tolerance for rounding
        assertApproxEqAbs(nextUnlockAmount, (purchased * 25) / 100, 1, "Next unlock is 25%");
        
        // Claim
        vm.prank(user1);
        presale.claimTokens();
        
        assertEq(presale.claimedAmount(user1), (purchased * 50) / 100, "Should claim 50%");
    }
    
    /// @notice Test multiple delayed claims at different times
    function test_MultipleUsersDelayedClaims() public {
        // All users purchase
        uint256 purchased1 = _makePurchase(user1, 1 ether);
        uint256 purchased2 = _makePurchase(user2, 2 ether);
        uint256 purchased3 = _makePurchase(user3, 3 ether);
        
        // End presale
        vm.warp(PRESALE_LAUNCH_DATE + 35 days);
        vm.prank(owner);
        presale.endEscrowPresale();
        uint256 tgeTime = presale.escrowPresaleEndTime();
        
        // User1 claims after 1 month (50%)
        vm.warp(tgeTime + 30 days);
        vm.prank(user1);
        presale.claimTokens();
        assertEq(presale.claimedAmount(user1), (purchased1 * 50) / 100, "User1: 50%");
        
        // User2 claims after 2 months (75%)
        vm.warp(tgeTime + 60 days);
        vm.prank(user2);
        presale.claimTokens();
        assertEq(presale.claimedAmount(user2), (purchased2 * 75) / 100, "User2: 75%");
        
        // User3 claims after 3 months (100%)
        vm.warp(tgeTime + 90 days);
        vm.prank(user3);
        presale.claimTokens();
        assertEq(presale.claimedAmount(user3), purchased3, "User3: 100%");
        
        // User1 now claims remaining (50% more)
        vm.prank(user1);
        presale.claimTokens();
        assertEq(presale.claimedAmount(user1), purchased1, "User1: 100% total");
        
        // User2 now claims remaining (25% more)
        vm.prank(user2);
        presale.claimTokens();
        assertEq(presale.claimedAmount(user2), purchased2, "User2: 100% total");
    }
    
    /// @notice Test vesting calculation is consistent regardless of when user claims
    /// @dev Two users with same purchase, one claims regularly, one delays
    function test_VestingConsistentRegardlessOfClaimTime() public {
        // Both users purchase same amount
        uint256 purchased1 = _makePurchase(user1, 1 ether);
        uint256 purchased2 = _makePurchase(user2, 1 ether);
        
        assertEq(purchased1, purchased2, "Same purchase amount");
        
        // End presale
        vm.warp(PRESALE_LAUNCH_DATE + 35 days);
        vm.prank(owner);
        presale.endEscrowPresale();
        uint256 tgeTime = presale.escrowPresaleEndTime();
        
        // User1 claims at each vesting period
        vm.warp(tgeTime);
        vm.prank(user1);
        presale.claimTokens(); // 25%
        
        vm.warp(tgeTime + 30 days);
        vm.prank(user1);
        presale.claimTokens(); // +25%
        
        vm.warp(tgeTime + 60 days);
        vm.prank(user1);
        presale.claimTokens(); // +25%
        
        vm.warp(tgeTime + 90 days);
        vm.prank(user1);
        presale.claimTokens(); // +25%
        
        // User2 delays and claims all at once after 90 days
        vm.prank(user2);
        presale.claimTokens(); // 100%
        
        // Both should have same amounts
        assertEq(
            presale.claimedAmount(user1), 
            presale.claimedAmount(user2), 
            "Both users should claim same total"
        );
        assertEq(
            token.balanceOf(user1), 
            token.balanceOf(user2), 
            "Both users should have same token balance"
        );
        assertEq(presale.claimedAmount(user1), purchased1, "Should be 100%");
    }
}
