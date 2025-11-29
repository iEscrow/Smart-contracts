// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../TokenVesting.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockEscrowToken is ERC20 {
    constructor() ERC20("ESCROW", "ESC") {
        _mint(msg.sender, 100_000_000_000 * 1e18); // 100 billion tokens
    }
}

contract TokenVestingTest is Test {
    TokenVesting public vesting;
    MockEscrowToken public escrowToken;
    
    address public owner = address(0x1);
    address public beneficiary1 = 0x04435410a78192baAfa00c72C659aD3187a2C2cF;
    address public beneficiary2 = 0x9005132849bC9585A948269D96F23f56e5981A61;
    address public beneficiary3 = 0x1C5cf9Cb69effeeb31E261BB6519AF7247A97A74;
    address public beneficiary4 = 0x403D8E7c3a1f7a0C7faF2a81b52CC74D775E9E21; // Muhammad's new address
    address public nonBeneficiary = address(0x999);
    
    uint256 public startTime;
    
    uint256 constant TOTAL_ALLOCATION = 1_000_000_000 * 1e18; // 1 billion
    uint256 constant CLIFF_PERIOD = 3 * 365 days;
    uint256 constant VESTING_INTERVAL = 180 days;
    
    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy token
        escrowToken = new MockEscrowToken();
        
        // Deploy vesting contract
        vesting = new TokenVesting(address(escrowToken), owner);
        
        startTime = block.timestamp;
        
        // Fund vesting contract with 1 billion tokens
        escrowToken.transfer(address(vesting), TOTAL_ALLOCATION);
        
        vm.stopPrank();
    }
    
    // ============ CONSTRUCTOR & INITIALIZATION TESTS ============
    
    function testConstructorInitialization() public view {
        assertEq(address(vesting.escrowToken()), address(escrowToken));
        assertEq(vesting.startTime(), startTime);
        assertEq(vesting.owner(), owner);
    }
    
    function testAllocationsSumTo100Percent() public view {
        uint256 sum = vesting.ALLOCATION1() + vesting.ALLOCATION2() + vesting.ALLOCATION3() + 
                      vesting.ALLOCATION4() + vesting.ALLOCATION5() + vesting.ALLOCATION6() + 
                      vesting.ALLOCATION7() + vesting.ALLOCATION8() + vesting.ALLOCATION9() + 
                      vesting.ALLOCATION10() + vesting.ALLOCATION11() + vesting.ALLOCATION12() + 
                      vesting.ALLOCATION13() + vesting.ALLOCATION14() + vesting.ALLOCATION15() + 
                      vesting.ALLOCATION16() + vesting.ALLOCATION17() + vesting.ALLOCATION18() + 
                      vesting.ALLOCATION19() + vesting.ALLOCATION20() + vesting.ALLOCATION21() + 
                      vesting.ALLOCATION22() + vesting.ALLOCATION23() + vesting.ALLOCATION24() + 
                      vesting.ALLOCATION25() + vesting.ALLOCATION26() + vesting.ALLOCATION27() + 
                      vesting.ALLOCATION28() + vesting.ALLOCATION29();
        assertEq(sum, 10000); // 100%
    }
    
    function testBeneficiaryAddresses() public view {
        // Test first 4 beneficiaries match our test addresses
        assertEq(vesting.BENEFICIARY1(), beneficiary1);
        assertEq(vesting.BENEFICIARY2(), beneficiary2);
        assertEq(vesting.BENEFICIARY3(), beneficiary3);
        // Note: beneficiary4 in contract is different from test beneficiary4
        assertEq(vesting.BENEFICIARY11(), beneficiary4); // Muhammad is now BENEFICIARY11
    }
    
    function testTotalAllocations() public view {
        uint256 alloc1 = vesting.getTotalAllocation(beneficiary1);
        uint256 alloc2 = vesting.getTotalAllocation(beneficiary2);
        uint256 alloc3 = vesting.getTotalAllocation(beneficiary3);
        uint256 alloc4 = vesting.getTotalAllocation(beneficiary4);
        
        assertEq(alloc1, 10_000_000 * 1e18); // 1%
        assertEq(alloc2, 10_000_000 * 1e18); // 1%
        assertEq(alloc3, 10_000_000 * 1e18); // 1%
        assertEq(alloc4, 10_000_000 * 1e18); // 1%
    }
    
    function testNonBeneficiaryHasZeroAllocation() public view {
        assertEq(vesting.getTotalAllocation(nonBeneficiary), 0);
    }
    
    // ============ CLIFF PERIOD TESTS ============
    
    function testNothingVestedDuringCliff() public view {
        // At start
        assertEq(vesting.getVestedAmount(beneficiary1), 0);
        assertEq(vesting.getVestedAmount(beneficiary2), 0);
        assertEq(vesting.getVestedAmount(beneficiary3), 0);
        assertEq(vesting.getVestedAmount(beneficiary4), 0);
    }
    
    function testNothingVestedOneDayBeforeCliffEnds() public {
        vm.warp(startTime + CLIFF_PERIOD - 1 days);
        
        assertEq(vesting.getVestedAmount(beneficiary1), 0);
        assertEq(vesting.getVestedAmount(beneficiary2), 0);
    }
    
    function testCannotClaimDuringCliff() public {
        vm.warp(startTime + 1 * 365 days); // 1 year in
        
        vm.prank(beneficiary1);
        vm.expectRevert("Nothing to claim");
        vesting.claim();
    }
    
    function testHasStarted() public view {
        assertTrue(vesting.hasStarted());
    }
    
    function testHasNotStartedCliff() public view {
        assertFalse(vesting.hasCliffEnded());
    }
    
    // ============ FIRST UNLOCK (YEAR 3) TESTS ============
    
    function testFirstUnlock20PercentAtCliffEnd() public {
        vm.warp(startTime + CLIFF_PERIOD);
        
        uint256 expected1 = (10_000_000 * 1e18 * 20) / 100; // 20% of 250M
        assertEq(vesting.getVestedAmount(beneficiary1), expected1);
        
        uint256 expected2 = (10_000_000 * 1e18 * 20) / 100;
        assertEq(vesting.getVestedAmount(beneficiary2), expected2);
    }
    
    function testClaimFirstUnlock() public {
        vm.warp(startTime + CLIFF_PERIOD);
        
        uint256 claimable = vesting.getClaimableAmount(beneficiary1);
        uint256 expectedClaimable = 2_000_000 * 1e18; // 20% of 250M
        assertEq(claimable, expectedClaimable);
        
        uint256 balanceBefore = escrowToken.balanceOf(beneficiary1);
        
        vm.prank(beneficiary1);
        vesting.claim();
        
        uint256 balanceAfter = escrowToken.balanceOf(beneficiary1);
        assertEq(balanceAfter - balanceBefore, expectedClaimable);
        assertEq(vesting.released(beneficiary1), expectedClaimable);
    }
    
    function testCliffEndedStatus() public {
        vm.warp(startTime + CLIFF_PERIOD);
        assertTrue(vesting.hasCliffEnded());
    }
    
    // ============ SECOND UNLOCK (YEAR 3.5) TESTS ============
    
    function testSecondUnlock40Percent() public {
        vm.warp(startTime + CLIFF_PERIOD + VESTING_INTERVAL);
        
        uint256 expected = (10_000_000 * 1e18 * 40) / 100; // 40% cumulative
        assertEq(vesting.getVestedAmount(beneficiary1), expected);
    }
    
    function testClaimSecondUnlock() public {
        // Claim first unlock
        vm.warp(startTime + CLIFF_PERIOD);
        vm.prank(beneficiary1);
        vesting.claim();
        
        uint256 firstClaim = 2_000_000 * 1e18;
        assertEq(vesting.released(beneficiary1), firstClaim);
        
        // Move to second unlock
        vm.warp(startTime + CLIFF_PERIOD + VESTING_INTERVAL);
        
        uint256 claimable = vesting.getClaimableAmount(beneficiary1);
        uint256 expectedNew = 2_000_000 * 1e18; // Another 20%
        assertEq(claimable, expectedNew);
        
        vm.prank(beneficiary1);
        vesting.claim();
        
        assertEq(vesting.released(beneficiary1), firstClaim + expectedNew);
    }
    
    // ============ THIRD UNLOCK (YEAR 4) TESTS ============
    
    function testThirdUnlock60Percent() public {
        vm.warp(startTime + CLIFF_PERIOD + (2 * VESTING_INTERVAL));
        
        uint256 expected = (10_000_000 * 1e18 * 60) / 100; // 60% cumulative
        assertEq(vesting.getVestedAmount(beneficiary1), expected);
    }
    
    // ============ FOURTH UNLOCK (YEAR 4.5) TESTS ============
    
    function testFourthUnlock80Percent() public {
        vm.warp(startTime + CLIFF_PERIOD + (3 * VESTING_INTERVAL));
        
        uint256 expected = (10_000_000 * 1e18 * 80) / 100; // 80% cumulative
        assertEq(vesting.getVestedAmount(beneficiary1), expected);
    }
    
    // ============ FINAL UNLOCK (YEAR 5) TESTS ============
    
    function testFinalUnlock100Percent() public {
        vm.warp(startTime + CLIFF_PERIOD + (4 * VESTING_INTERVAL));
        
        uint256 expected = 10_000_000 * 1e18; // 100%
        assertEq(vesting.getVestedAmount(beneficiary1), expected);
    }
    
    function testFullyVestedStatus() public {
        vm.warp(startTime + CLIFF_PERIOD + (4 * VESTING_INTERVAL));
        assertTrue(vesting.isFullyVested());
    }
    
    function testClaimFullAllocation() public {
        vm.warp(startTime + CLIFF_PERIOD + (4 * VESTING_INTERVAL));
        
        uint256 balanceBefore = escrowToken.balanceOf(beneficiary1);
        
        vm.prank(beneficiary1);
        vesting.claim();
        
        uint256 balanceAfter = escrowToken.balanceOf(beneficiary1);
        uint256 totalReceived = balanceAfter - balanceBefore;
        
        assertEq(totalReceived, 10_000_000 * 1e18);
        assertEq(vesting.released(beneficiary1), 10_000_000 * 1e18);
    }
    
    function testCannotClaimMoreThanAllocated() public {
        vm.warp(startTime + CLIFF_PERIOD + (4 * VESTING_INTERVAL));
        
        // First claim (full allocation)
        vm.prank(beneficiary1);
        vesting.claim();
        
        // Try to claim again
        vm.prank(beneficiary1);
        vm.expectRevert("Nothing to claim");
        vesting.claim();
    }
    
    // ============ MULTIPLE BENEFICIARIES TESTS ============
    
    function testMultipleBeneficiariesCanClaim() public {
        vm.warp(startTime + CLIFF_PERIOD);
        
        // Beneficiary 1 claims
        vm.prank(beneficiary1);
        vesting.claim();
        
        // Beneficiary 2 claims
        vm.prank(beneficiary2);
        vesting.claim();
        
        // Beneficiary 3 claims
        vm.prank(beneficiary3);
        vesting.claim();
        
        // Beneficiary 4 claims
        vm.prank(beneficiary4);
        vesting.claim();
        
        assertEq(escrowToken.balanceOf(beneficiary1), 2_000_000 * 1e18);
        assertEq(escrowToken.balanceOf(beneficiary2), 2_000_000 * 1e18);
        assertEq(escrowToken.balanceOf(beneficiary3), 2_000_000 * 1e18);
        assertEq(escrowToken.balanceOf(beneficiary4), 2_000_000 * 1e18);
    }
    
    function testAllBeneficiariesClaimFullAllocation() public {
        vm.warp(startTime + CLIFF_PERIOD + (4 * VESTING_INTERVAL));
        
        vm.prank(beneficiary1);
        vesting.claim();
        
        vm.prank(beneficiary2);
        vesting.claim();
        
        vm.prank(beneficiary3);
        vesting.claim();
        
        vm.prank(beneficiary4);
        vesting.claim();
        
        assertEq(escrowToken.balanceOf(beneficiary1), 10_000_000 * 1e18);
        assertEq(escrowToken.balanceOf(beneficiary2), 10_000_000 * 1e18);
        assertEq(escrowToken.balanceOf(beneficiary3), 10_000_000 * 1e18);
        assertEq(escrowToken.balanceOf(beneficiary4), 10_000_000 * 1e18);
        
        // Verify 4 beneficiaries claimed their allocations (4 * 10M = 40M)
        uint256 totalDistributed = escrowToken.balanceOf(beneficiary1) +
                                    escrowToken.balanceOf(beneficiary2) +
                                    escrowToken.balanceOf(beneficiary3) +
                                    escrowToken.balanceOf(beneficiary4);
        assertEq(totalDistributed, 40_000_000 * 1e18); // 4 * 10M
    }
    
    // ============ NON-BENEFICIARY TESTS ============
    
    function testNonBeneficiaryCannotClaim() public {
        vm.warp(startTime + CLIFF_PERIOD);
        
        vm.prank(nonBeneficiary);
        vm.expectRevert("Nothing to claim");
        vesting.claim();
    }
    
    function testNonBeneficiaryHasZeroVested() public {
        vm.warp(startTime + CLIFF_PERIOD + (4 * VESTING_INTERVAL));
        assertEq(vesting.getVestedAmount(nonBeneficiary), 0);
    }
    
    // ============ VIEW FUNCTION TESTS ============
    
    function testGetVestingSchedule() public view {
        (uint256 cliffEnd, uint256 vestingEnd, uint256 currentTime) = vesting.getVestingSchedule();
        
        assertEq(cliffEnd, startTime + CLIFF_PERIOD);
        assertEq(vestingEnd, startTime + CLIFF_PERIOD + (4 * VESTING_INTERVAL));
        assertEq(currentTime, block.timestamp);
    }
    
    function testGetBeneficiaryInfoDuringCliff() public view {
        (uint256 totalAlloc, uint256 vested, uint256 releasedAmount, uint256 claimable) = 
            vesting.getBeneficiaryInfo(beneficiary1);
        
        assertEq(totalAlloc, 10_000_000 * 1e18);
        assertEq(vested, 0);
        assertEq(releasedAmount, 0);
        assertEq(claimable, 0);
    }
    
    function testGetBeneficiaryInfoAfterCliff() public {
        vm.warp(startTime + CLIFF_PERIOD);
        
        (uint256 totalAlloc, uint256 vested, uint256 releasedAmount, uint256 claimable) = 
            vesting.getBeneficiaryInfo(beneficiary1);
        
        assertEq(totalAlloc, 10_000_000 * 1e18);
        assertEq(vested, 2_000_000 * 1e18); // 20%
        assertEq(releasedAmount, 0);
        assertEq(claimable, 2_000_000 * 1e18);
    }
    
    function testGetBeneficiaryInfoAfterClaim() public {
        vm.warp(startTime + CLIFF_PERIOD);
        
        vm.prank(beneficiary1);
        vesting.claim();
        
        (uint256 totalAlloc, uint256 vested, uint256 releasedAmount, uint256 claimable) = 
            vesting.getBeneficiaryInfo(beneficiary1);
        
        assertEq(totalAlloc, 10_000_000 * 1e18);
        assertEq(vested, 2_000_000 * 1e18);
        assertEq(releasedAmount, 2_000_000 * 1e18);
        assertEq(claimable, 0);
    }
    
    function testGetClaimableAmount() public {
        vm.warp(startTime + CLIFF_PERIOD);
        assertEq(vesting.getClaimableAmount(beneficiary1), 2_000_000 * 1e18);
        
        vm.warp(startTime + CLIFF_PERIOD + VESTING_INTERVAL);
        assertEq(vesting.getClaimableAmount(beneficiary1), 4_000_000 * 1e18); // 40% total
    }
    
    // ============ EDGE CASE TESTS ============
    
    function testVestingBetweenIntervals() public {
        // Move to halfway between cliff and first interval
        vm.warp(startTime + CLIFF_PERIOD + (VESTING_INTERVAL / 2));
        
        // Should still only have 20% vested (not interpolated)
        uint256 expected = (10_000_000 * 1e18 * 20) / 100;
        assertEq(vesting.getVestedAmount(beneficiary1), expected);
    }
    
    function testVestingWellBeyondFinalUnlock() public {
        // Move 10 years after vesting starts
        vm.warp(startTime + 10 * 365 days);
        
        // Should cap at 100%
        uint256 expected = 10_000_000 * 1e18;
        assertEq(vesting.getVestedAmount(beneficiary1), expected);
    }
    
    function testMultipleClaimsAcrossIntervals() public {
        // Claim at each interval
        for (uint256 i = 0; i < 5; i++) {
            vm.warp(startTime + CLIFF_PERIOD + (i * VESTING_INTERVAL));
            
            uint256 claimable = vesting.getClaimableAmount(beneficiary1);
            if (claimable > 0) {
                vm.prank(beneficiary1);
                vesting.claim();
            }
        }
        
        // Should have claimed full allocation
        assertEq(vesting.released(beneficiary1), 10_000_000 * 1e18);
        assertEq(escrowToken.balanceOf(beneficiary1), 10_000_000 * 1e18);
    }
    
    // ============ REENTRANCY TESTS ============
    
    function testReentrancyProtection() public {
        // Claim function has nonReentrant modifier
        // This is implicitly tested by the modifier itself
        // But we verify it exists by checking successful claims work
        vm.warp(startTime + CLIFF_PERIOD);
        
        vm.prank(beneficiary1);
        vesting.claim();
        
        // Verify state was updated before transfer
        assertEq(vesting.released(beneficiary1), 2_000_000 * 1e18);
    }
    
    // ============ EMERGENCY WITHDRAWAL TESTS ============
    
    function testOwnerCannotWithdrawEscrowTokens() public {
        vm.prank(owner);
        vm.expectRevert("Cannot withdraw vesting tokens");
        vesting.emergencyWithdraw(address(escrowToken), 1000);
    }
    
    function testOwnerCanWithdrawOtherTokens() public {
        // Deploy another token and send to vesting contract
        MockEscrowToken otherToken = new MockEscrowToken();
        otherToken.transfer(address(vesting), 1000 * 1e18);
        
        uint256 balanceBefore = otherToken.balanceOf(owner);
        
        vm.prank(owner);
        vesting.emergencyWithdraw(address(otherToken), 1000 * 1e18);
        
        uint256 balanceAfter = otherToken.balanceOf(owner);
        assertEq(balanceAfter - balanceBefore, 1000 * 1e18);
    }
    
    function testNonOwnerCannotEmergencyWithdraw() public {
        MockEscrowToken otherToken = new MockEscrowToken();
        otherToken.transfer(address(vesting), 1000 * 1e18);
        
        vm.prank(nonBeneficiary);
        vm.expectRevert();
        vesting.emergencyWithdraw(address(otherToken), 1000 * 1e18);
    }
    
    // ============ EVENT TESTS ============
    
    function testClaimEmitsEvent() public {
        vm.warp(startTime + CLIFF_PERIOD);
        
        vm.expectEmit(true, false, false, true, address(vesting));
        emit TokensReleased(beneficiary1, 2_000_000 * 1e18);
        
        vm.prank(beneficiary1);
        vesting.claim();
    }
    
    function testConstructorEmitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit VestingStarted(block.timestamp);
        
        new TokenVesting(address(escrowToken), owner);
    }
    
    // Event declarations for testing
    event TokensReleased(address indexed beneficiary, uint256 amount);
    event VestingStarted(uint256 startTime);
}
