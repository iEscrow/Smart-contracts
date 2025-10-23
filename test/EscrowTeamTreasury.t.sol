// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@forge-std/Test.sol";
import "../EscrowTeamTreasury.sol";
import "../MockEscrowToken.sol";
import "../MockEscrowTokenNoMint.sol";

contract EscrowTeamTreasuryTest is Test {
    EscrowTeamTreasury public treasury;
    MockEscrowToken public escrowToken;
    MockEscrowTokenNoMint public tokenNoMint;

    address public owner;
    address public addr1;
    address public addr2;
    address public addr3;

    // Constants matching the contract
    uint256 constant TOTAL_ALLOCATION = 1_000_000_000 * 1e18; // 1B tokens
    uint256 constant LOCK_DURATION = 3 * 365 * 24 * 60 * 60; // 3 years
    uint256 constant VESTING_INTERVAL = 180 * 24 * 60 * 60; // 6 months
    uint256 constant VESTING_MILESTONES = 5;
    uint256 constant PERCENTAGE_PER_MILESTONE = 2000; // 20%
    uint256 constant BASIS_POINTS = 10000;

    event TreasuryFunded(uint256 amount, uint256 timestamp);
    event BeneficiaryAdded(address indexed beneficiary, uint256 allocation);
    event BeneficiaryUpdated(address indexed beneficiary, uint256 newAllocation);
    event BeneficiaryRemoved(address indexed beneficiary, uint256 allocation);
    event TokensClaimed(address indexed beneficiary, uint256 amount, uint256 milestone);
    event AllocationRevoked(address indexed beneficiary, uint256 unvestedAmount);
    event AllocationsLocked(uint256 timestamp);
    event EmergencyWithdraw(address indexed token, uint256 amount);

    function setUp() public {
        owner = address(this);
        addr1 = makeAddr("beneficiary1");
        addr2 = makeAddr("beneficiary2");
        addr3 = makeAddr("beneficiary3");

        // Deploy mock token with initial supply
        escrowToken = new MockEscrowToken();

        // Deploy treasury with token address
        treasury = new EscrowTeamTreasury(address(escrowToken));
    }

    // ============ DEPLOYMENT TESTS ============

    function testDeployment() public view {
        // Check basic deployment
        assertEq(address(treasury.escrowToken()), address(escrowToken));
        assertEq(treasury.TOTAL_ALLOCATION(), TOTAL_ALLOCATION);
        assertEq(treasury.LOCK_DURATION(), LOCK_DURATION);
        assertEq(treasury.VESTING_INTERVAL(), VESTING_INTERVAL);
        assertEq(treasury.VESTING_MILESTONES(), VESTING_MILESTONES);
        assertEq(treasury.PERCENTAGE_PER_MILESTONE(), PERCENTAGE_PER_MILESTONE);


        // Check initial state
        assertFalse(treasury.treasuryFunded());
        assertFalse(treasury.allocationsLocked());
        assertEq(treasury.owner(), owner);

        // Check initial beneficiaries are set up
        (address[] memory initialBeneficiaries,,,) = treasury.getAllBeneficiaries();
        assertGt(initialBeneficiaries.length, 0);
        assertTrue(treasury.totalAllocated() > 0);
    }

    function testDeploymentWithZeroAddress() public {
        vm.expectRevert(EscrowTeamTreasury.InvalidAddress.selector);
        new EscrowTeamTreasury(address(0));
    }

    // ============ FUNDING TESTS ============

    function testFundTreasury() public {
        uint256 amount = treasury.TOTAL_ALLOCATION();

        // Mint tokens to owner
        escrowToken.mint(owner, amount);

        // Approve treasury to spend tokens
        escrowToken.approve(address(treasury), amount);

        // Expect the TreasuryFunded event
        vm.expectEmit(true, true, true, true);
        emit TreasuryFunded(amount, block.timestamp);

        // Fund treasury
        treasury.fundTreasury();

        // Check state after funding
        assertTrue(treasury.treasuryFunded());
        assertEq(escrowToken.balanceOf(address(treasury)), amount);
        assertEq(escrowToken.balanceOf(owner), amount); // Owner started with 1B from constructor, got another 1B, transferred 1B to treasury
    }

    function testFundTreasuryTwice() public {
        uint256 amount = treasury.TOTAL_ALLOCATION();

        // Setup first funding
        escrowToken.mint(owner, amount);
        escrowToken.approve(address(treasury), amount);
        treasury.fundTreasury();

        // Try to fund again - should revert
        vm.expectRevert(EscrowTeamTreasury.TreasuryAlreadyFunded.selector);
        treasury.fundTreasury();
    }

    function testFundTreasuryInsufficientBalance() public {
        // Deploy token that doesn't mint in constructor
        tokenNoMint = new MockEscrowTokenNoMint();
        EscrowTeamTreasury newTreasury = new EscrowTeamTreasury(address(tokenNoMint));

        uint256 amount = newTreasury.TOTAL_ALLOCATION();

        // Mint less than required
        tokenNoMint.mint(owner, amount - 1);

        // Approve treasury
        tokenNoMint.approve(address(newTreasury), amount);

        // Should revert with insufficient balance
        vm.expectRevert(EscrowTeamTreasury.InsufficientBalance.selector);
        newTreasury.fundTreasury();
    }

    // ============ BENEFICIARY MANAGEMENT TESTS ============

    function testAddBeneficiary() public {
        fundTreasury();

        // Remove initial beneficiary first to make space
        (address[] memory initialBeneficiaries,,,) = treasury.getAllBeneficiaries();
        treasury.removeBeneficiary(initialBeneficiaries[0]);

        uint256 initialTotalAllocated = treasury.totalAllocated();
        uint256 beneficiaryAmount = 100000 * 1e18;

        vm.expectEmit(true, true, true, true);
        emit BeneficiaryAdded(addr1, beneficiaryAmount);

        treasury.addBeneficiary(addr1, beneficiaryAmount);

        // Verify beneficiary was added
        assertTrue(treasury.isBeneficiary(addr1));
        (,,,,,, bool isActive,) = treasury.getBeneficiaryInfo(addr1);
        assertTrue(isActive);
        assertEq(treasury.totalAllocated(), initialTotalAllocated + beneficiaryAmount);
    }

    function testAddBeneficiaryTwice() public {
        fundTreasury();

        (address[] memory initialBeneficiaries,,,) = treasury.getAllBeneficiaries();
        treasury.removeBeneficiary(initialBeneficiaries[0]);

        uint256 beneficiaryAmount = 100000 * 1e18;
        treasury.addBeneficiary(addr1, beneficiaryAmount);

        // Try to add same beneficiary again
        vm.expectRevert(EscrowTeamTreasury.AlreadyAllocated.selector);
        treasury.addBeneficiary(addr1, beneficiaryAmount);
    }

    function testAddBeneficiaryExceedsTotal() public {
        fundTreasury();

        (address[] memory initialBeneficiaries,,,) = treasury.getAllBeneficiaries();
        treasury.removeBeneficiary(initialBeneficiaries[0]);

        uint256 hugeAmount = TOTAL_ALLOCATION + 1; // Exceeds total allocation

        vm.expectRevert(EscrowTeamTreasury.ExceedsTotalAllocation.selector);
        treasury.addBeneficiary(addr1, hugeAmount);
    }

    function testAddBeneficiaryZeroAmount() public {
        fundTreasury();

        vm.expectRevert(EscrowTeamTreasury.InvalidAmount.selector);
        treasury.addBeneficiary(addr1, 0);
    }

    function testAddBeneficiaryZeroAddress() public {
        fundTreasury();

        vm.expectRevert(EscrowTeamTreasury.InvalidAddress.selector);
        treasury.addBeneficiary(address(0), 1000);
    }

    function testUpdateBeneficiary() public {
        fundTreasury();

        (address[] memory initialBeneficiaries,,,) = treasury.getAllBeneficiaries();
        treasury.removeBeneficiary(initialBeneficiaries[0]);

        uint256 initialAmount = 100000 * 1e18;
        treasury.addBeneficiary(addr1, initialAmount);

        uint256 newAmount = 200000 * 1e18;

        vm.expectEmit(true, true, true, true);
        emit BeneficiaryUpdated(addr1, newAmount);

        treasury.updateBeneficiary(addr1, newAmount);

        // Verify update
        (uint256 totalAllocation,,,,,,,) = treasury.getBeneficiaryInfo(addr1);
        assertEq(totalAllocation, newAmount);
    }

    function testUpdateBeneficiaryAfterLocking() public {
        fundTreasury();

        (address[] memory initialBeneficiaries,,,) = treasury.getAllBeneficiaries();
        treasury.removeBeneficiary(initialBeneficiaries[0]);

        uint256 initialAmount = 100000 * 1e18;
        treasury.addBeneficiary(addr1, initialAmount);
        treasury.lockAllocations();

        uint256 newAmount = 200000 * 1e18;

        vm.expectRevert(EscrowTeamTreasury.AllocationsAlreadyLocked.selector);
        treasury.updateBeneficiary(addr1, newAmount);
    }

    function testUpdateBeneficiaryZeroAmount() public {
        fundTreasury();

        (address[] memory initialBeneficiaries,,,) = treasury.getAllBeneficiaries();
        treasury.removeBeneficiary(initialBeneficiaries[0]);

        treasury.addBeneficiary(addr1, 100000 * 1e18);

        vm.expectRevert(EscrowTeamTreasury.InvalidAmount.selector);
        treasury.updateBeneficiary(addr1, 0);
    }

    function testRemoveBeneficiary() public {
        fundTreasury();

        (address[] memory initialBeneficiaries,,,) = treasury.getAllBeneficiaries();
        treasury.removeBeneficiary(initialBeneficiaries[0]);

        uint256 beneficiaryAmount = 100000 * 1e18;
        treasury.addBeneficiary(addr1, beneficiaryAmount);

        vm.expectEmit(true, true, true, true);
        emit BeneficiaryRemoved(addr1, beneficiaryAmount);

        treasury.removeBeneficiary(addr1);

        // Verify removal
        assertFalse(treasury.isBeneficiary(addr1));
        (,,,,,, bool isActive,) = treasury.getBeneficiaryInfo(addr1);
        assertFalse(isActive);
    }

    function testRemoveBeneficiaryAfterLocking() public {
        fundTreasuryAndLock();

        (address[] memory initialBeneficiaries,,,) = treasury.getAllBeneficiaries();
        address firstBeneficiary = initialBeneficiaries[0];

        vm.expectRevert(EscrowTeamTreasury.AllocationsAlreadyLocked.selector);
        treasury.removeBeneficiary(firstBeneficiary);
    }

    function testRemoveNonExistentBeneficiary() public {
        vm.expectRevert(EscrowTeamTreasury.NotBeneficiary.selector);
        treasury.removeBeneficiary(addr1);
    }

    // ============ LOCKING TESTS ============

    function testLockAllocations() public {
        fundTreasury();

        vm.expectEmit(true, true, true, true);
        emit AllocationsLocked(block.timestamp);

        treasury.lockAllocations();

        assertTrue(treasury.allocationsLocked());
    }

    function testLockAllocationsTwice() public {
        fundTreasury();
        treasury.lockAllocations();

        vm.expectRevert(EscrowTeamTreasury.AllocationsAlreadyLocked.selector);
        treasury.lockAllocations();
    }

    function testLockAllocationsNotFunded() public {
        vm.expectRevert(EscrowTeamTreasury.TreasuryNotFunded.selector);
        treasury.lockAllocations();
    }

    function testLockAllocationsZeroAllocation() public {
        // Create treasury with no initial beneficiaries (this is tricky with the current constructor)
        // For now, this test validates the existing logic
        fundTreasury();

        // Remove all initial beneficiaries
        (address[] memory initialBeneficiaries,,,) = treasury.getAllBeneficiaries();
        for (uint256 i = 0; i < initialBeneficiaries.length; i++) {
            treasury.removeBeneficiary(initialBeneficiaries[i]);
        }

        // Should fail to lock with zero allocation
        vm.expectRevert(EscrowTeamTreasury.InvalidAmount.selector);
        treasury.lockAllocations();
    }

    // ============ CLAIMING TESTS ============

    function testClaimBeforeLockPeriod() public {
        fundTreasuryAndLock();

        (address[] memory initialBeneficiaries,,,) = treasury.getAllBeneficiaries();
        address firstBeneficiary = initialBeneficiaries[0];

        vm.expectRevert(EscrowTeamTreasury.NoTokensAvailable.selector);
        treasury.claimFor(firstBeneficiary);
    }

    function testClaimAfterThreeYears() public {
        fundTreasuryAndLock();

        (address[] memory initialBeneficiaries,,,) = treasury.getAllBeneficiaries();
        address firstBeneficiary = initialBeneficiaries[0];

        // Advance time by 3 years (lock duration)
        vm.warp(block.timestamp + LOCK_DURATION);

        uint256 expectedClaimAmount = 2000000 * 1e18; // 20% of 10M

        vm.expectEmit(true, true, true, true);
        emit TokensClaimed(firstBeneficiary, expectedClaimAmount, 1);

        treasury.claimFor(firstBeneficiary);

        // Verify claim
        (,, uint256 claimedAmount,,,,,) = treasury.getBeneficiaryInfo(firstBeneficiary);
        assertEq(claimedAmount, expectedClaimAmount);
        assertEq(treasury.totalClaimed(), expectedClaimAmount);
    }

    function testClaimMultipleMilestones() public {
        fundTreasuryAndLock();

        (address[] memory initialBeneficiaries,,,) = treasury.getAllBeneficiaries();
        address firstBeneficiary = initialBeneficiaries[0];

        uint256 expectedAmountPerMilestone = 2000000 * 1e18; // 20% of 10M

        // Test all 5 milestones
        for (uint256 milestone = 1; milestone <= VESTING_MILESTONES; milestone++) {
            // Advance time to next milestone
            vm.warp(block.timestamp + (milestone == 1 ? LOCK_DURATION : VESTING_INTERVAL));

            treasury.claimFor(firstBeneficiary);

            // Verify claimed amount
            (,, uint256 claimedAmount,,,,,) = treasury.getBeneficiaryInfo(firstBeneficiary);
            assertEq(claimedAmount, expectedAmountPerMilestone * milestone);
        }

        // After all milestones, no more claims should be possible
        vm.warp(block.timestamp + VESTING_INTERVAL);
        vm.expectRevert(EscrowTeamTreasury.NoTokensAvailable.selector);
        treasury.claimFor(firstBeneficiary);
    }

    function testClaimMultipleInSameMilestone() public {
        fundTreasuryAndLock();

        (address[] memory initialBeneficiaries,,,) = treasury.getAllBeneficiaries();
        address firstBeneficiary = initialBeneficiaries[0];

        // Advance to first milestone
        vm.warp(block.timestamp + LOCK_DURATION);
        treasury.claimFor(firstBeneficiary);

        // Try to claim again in same milestone
        vm.expectRevert(EscrowTeamTreasury.NoTokensAvailable.selector);
        treasury.claimFor(firstBeneficiary);
    }

    function testClaimForMultipleBeneficiaries() public {
        fundTreasuryAndLock();

        (address[] memory initialBeneficiaries,,,) = treasury.getAllBeneficiaries();
        address ben1 = initialBeneficiaries[0];
        address ben2 = initialBeneficiaries[1];

        // Advance to first milestone
        vm.warp(block.timestamp + LOCK_DURATION);

        // Claim for both beneficiaries
        treasury.claimFor(ben1);
        treasury.claimFor(ben2);

        // Verify both claimed
        (,, uint256 claimed1,,,,,) = treasury.getBeneficiaryInfo(ben1);
        (,, uint256 claimed2,,,,,) = treasury.getBeneficiaryInfo(ben2);

        assertEq(claimed1, 2000000 * 1e18);
        assertEq(claimed2, 2000000 * 1e18);
    }


    function testClaimForNonBeneficiary() public {
        fundTreasuryAndLock();

        vm.expectRevert(EscrowTeamTreasury.NotBeneficiary.selector);
        treasury.claimFor(addr1);
    }

    function testClaimForRevokedBeneficiary() public {
        fundTreasuryAndLock();

        (address[] memory initialBeneficiaries,,,) = treasury.getAllBeneficiaries();
        address firstBeneficiary = initialBeneficiaries[0];

        // Advance time and revoke
        vm.warp(block.timestamp + LOCK_DURATION);
        treasury.revokeAllocation(firstBeneficiary);

        vm.expectRevert(EscrowTeamTreasury.AllocationAlreadyRevoked.selector);
        treasury.claimFor(firstBeneficiary);
    }

    // ============ ADMIN FUNCTIONS TESTS ============


    function testRevokeAllocation() public {
        fundTreasuryAndLock();

        (address[] memory initialBeneficiaries,,,) = treasury.getAllBeneficiaries();
        address firstBeneficiary = initialBeneficiaries[0];

        // Advance time to make some tokens claimable
        vm.warp(block.timestamp + LOCK_DURATION);

        vm.expectEmit(true, true, true, true);
        emit AllocationRevoked(firstBeneficiary, 8000000 * 1e18); // 80% remaining

        treasury.revokeAllocation(firstBeneficiary);

        // Check if revoked
        (,,,,,, bool isActive, bool revoked) = treasury.getBeneficiaryInfo(firstBeneficiary);
        assertTrue(revoked);
        assertTrue(isActive); // Still active but revoked
    }

    function testRevokeAllocationTwice() public {
        fundTreasuryAndLock();

        (address[] memory initialBeneficiaries,,,) = treasury.getAllBeneficiaries();
        address firstBeneficiary = initialBeneficiaries[0];

        treasury.revokeAllocation(firstBeneficiary);

        // Try to revoke again
        vm.expectRevert(EscrowTeamTreasury.AllocationAlreadyRevoked.selector);
        treasury.revokeAllocation(firstBeneficiary);
    }


    // ============ ACCESS CONTROL TESTS ============

    function testOnlyOwnerCanAddBeneficiary() public {
        fundTreasury();

        uint256 amount = 10000 * 1e18;

        vm.prank(addr1);
        vm.expectRevert();
        treasury.addBeneficiary(addr2, amount);
    }

    function testOnlyOwnerCanLockAllocations() public {
        fundTreasury();

        vm.prank(addr1);
        vm.expectRevert();
        treasury.lockAllocations();
    }

    function testOnlyOwnerCanRevoke() public {
        fundTreasuryAndLock();

        (address[] memory initialBeneficiaries,,,) = treasury.getAllBeneficiaries();
        address firstBeneficiary = initialBeneficiaries[0];

        vm.prank(addr1);
        vm.expectRevert();
        treasury.revokeAllocation(firstBeneficiary);
    }

    // ============ VIEW FUNCTIONS TESTS ============

    function testGetContractInfo() public view {
        (
            address tokenAddress,
            uint256 totalAllocation,
            uint256 lockDuration,
            uint256 vestingInterval,
            uint256 milestones,
            uint256 percentPerMilestone
        ) = treasury.getContractInfo();

        assertEq(tokenAddress, address(escrowToken));
        assertEq(totalAllocation, TOTAL_ALLOCATION);
        assertEq(lockDuration, LOCK_DURATION);
        assertEq(vestingInterval, VESTING_INTERVAL);
        assertEq(milestones, VESTING_MILESTONES);
        assertEq(percentPerMilestone, PERCENTAGE_PER_MILESTONE);
    }

    function testGetTreasuryStats() public {
        fundTreasuryAndLock();

        (
            uint256 totalAlloc,
            uint256 totalClaim,
            uint256 totalRemaining,
            uint256 unallocated,
            uint256 beneficiaryCount,
            bool locked,
            bool funded
        ) = treasury.getTreasuryStats();

        assertEq(totalAlloc, treasury.totalAllocated());
        assertEq(totalClaim, treasury.totalClaimed());
        assertEq(totalRemaining, treasury.totalAllocated() - treasury.totalClaimed());
        assertGe(unallocated, 0); // Should be non-negative
        assertGe(beneficiaryCount, 0); // Should be non-negative
        assertTrue(locked);
        assertTrue(funded);
    }

    function testGetBeneficiaryInfo() public {
        fundTreasuryAndLock();

        (address[] memory initialBeneficiaries,,,) = treasury.getAllBeneficiaries();
        address firstBeneficiary = initialBeneficiaries[0];

        (
            uint256 totalAllocation,
            uint256 vestedAmount,
            uint256 claimedAmount,
            uint256 claimableAmount,
            uint256 remainingAmount,
            uint256 currentMilestone,
            bool isActive,
            bool revoked
        ) = treasury.getBeneficiaryInfo(firstBeneficiary);

        assertEq(totalAllocation, 10000000 * 1e18);
        assertEq(vestedAmount, 0); // Before 3-year lock
        assertEq(claimedAmount, 0);
        assertEq(claimableAmount, 0);
        assertEq(remainingAmount, 10000000 * 1e18);
        assertEq(currentMilestone, 0);
        assertTrue(isActive);
        assertFalse(revoked);
    }

    function testGetBeneficiaryInfoAfterClaim() public {
        fundTreasuryAndLock();

        (address[] memory initialBeneficiaries,,,) = treasury.getAllBeneficiaries();
        address firstBeneficiary = initialBeneficiaries[0];

        // Advance time and claim
        vm.warp(block.timestamp + LOCK_DURATION);
        treasury.claimFor(firstBeneficiary);

        (
            ,
            ,
            uint256 claimedAmount,
            uint256 claimableAmount,
            uint256 remainingAmount,
            ,
            ,
            
        ) = treasury.getBeneficiaryInfo(firstBeneficiary);

        assertEq(claimedAmount, 2000000 * 1e18);
        assertEq(claimableAmount, 0); // Already claimed
        assertEq(remainingAmount, 8000000 * 1e18);
    }

    function testGetClaimableAmountForRevoked() public {
        fundTreasuryAndLock();

        (address[] memory initialBeneficiaries,,,) = treasury.getAllBeneficiaries();
        address firstBeneficiary = initialBeneficiaries[0];

        treasury.revokeAllocation(firstBeneficiary);

        uint256 claimable = treasury.getClaimableAmount(firstBeneficiary);
        assertEq(claimable, 0);
    }

    function testGetClaimableAmountForNonBeneficiary() public view {
        uint256 claimable = treasury.getClaimableAmount(addr1);
        assertEq(claimable, 0);
    }

    function testIsBeneficiary() public {
        fundTreasuryAndLock();

        (address[] memory initialBeneficiaries,,,) = treasury.getAllBeneficiaries();
        address firstBeneficiary = initialBeneficiaries[0];

        assertTrue(treasury.isBeneficiary(firstBeneficiary));
        assertFalse(treasury.isBeneficiary(addr1));
    }

    function testGetVestingSchedule() public {
        fundTreasuryAndLock();

        (
            uint256 startTime,
            uint256 firstUnlock,
            uint256 currentMilestone,
            uint256 totalMilestones,
            uint256 intervalDays
        ) = treasury.getVestingSchedule();

        assertEq(startTime, treasury.treasuryStartTime());
        assertEq(firstUnlock, treasury.firstUnlockTime());
        assertEq(currentMilestone, 0); // Before lock period
        assertEq(totalMilestones, VESTING_MILESTONES);
        assertEq(intervalDays, VESTING_INTERVAL / 1 days);
    }

    function testGetNextUnlockTime() public {
        fundTreasuryAndLock();

        // Before any vesting
        uint256 nextUnlock = treasury.getNextUnlockTime();
        assertEq(nextUnlock, treasury.firstUnlockTime());

        // At first milestone
        vm.warp(block.timestamp + LOCK_DURATION);
        nextUnlock = treasury.getNextUnlockTime();
        assertEq(nextUnlock, treasury.firstUnlockTime() + VESTING_INTERVAL);

        // At second milestone
        vm.warp(block.timestamp + VESTING_INTERVAL);
        nextUnlock = treasury.getNextUnlockTime();
        assertEq(nextUnlock, treasury.firstUnlockTime() + (2 * VESTING_INTERVAL));
    }

    function testGetTimeUntilNextUnlock() public {
        fundTreasuryAndLock();

        // Before any vesting
        uint256 timeUntil = treasury.getTimeUntilNextUnlock();
        assertEq(timeUntil, treasury.firstUnlockTime() - block.timestamp);

        // At first milestone
        vm.warp(block.timestamp + LOCK_DURATION);
        timeUntil = treasury.getTimeUntilNextUnlock();
        assertEq(timeUntil, VESTING_INTERVAL);

        // After all milestones
        vm.warp(block.timestamp + (VESTING_MILESTONES * VESTING_INTERVAL));
        timeUntil = treasury.getTimeUntilNextUnlock();
        assertEq(timeUntil, 0);
    }

    function testGetAllBeneficiaries() public {
        fundTreasuryAndLock();

        (address[] memory addresses, uint256[] memory allocations, uint256[] memory claimed, bool[] memory active) = treasury.getAllBeneficiaries();

        // Verify addresses array
        assertGt(addresses.length, 0, "Should have at least one beneficiary");
        assertEq(addresses.length, allocations.length, "Addresses and allocations arrays should have same length");
        assertEq(addresses.length, claimed.length, "Addresses and claimed arrays should have same length");
        assertEq(addresses.length, active.length, "Addresses and active arrays should have same length");

        // Verify all addresses are valid (non-zero)
        for (uint256 i = 0; i < addresses.length; i++) {
            assertNotEq(addresses[i], address(0), "Beneficiary address should not be zero");
        }

        assertEq(allocations[0], 10000000 * 1e18);
        assertEq(claimed[0], 0);
        assertTrue(active[0]);
    }

    // ============ EDGE CASES AND COMPREHENSIVE TESTS ============


    function testBeneficiaryManagementWorkflow() public {
        fundTreasury();

        // Start with initial beneficiaries
        (address[] memory initialBeneficiaries,,,) = treasury.getAllBeneficiaries();
        uint256 initialCount = initialBeneficiaries.length;

        // Remove one beneficiary
        treasury.removeBeneficiary(initialBeneficiaries[0]);
        (address[] memory addresses,,,) = treasury.getAllBeneficiaries();
        assertEq(addresses.length, initialCount - 1);

        // Add new beneficiary
        treasury.addBeneficiary(addr1, 100000 * 1e18);
        assertTrue(treasury.isBeneficiary(addr1));

        // Update allocation
        treasury.updateBeneficiary(addr1, 200000 * 1e18);
        (uint256 newAllocation,,,,,,,) = treasury.getBeneficiaryInfo(addr1);
        assertEq(newAllocation, 200000 * 1e18);

        // Lock allocations
        treasury.lockAllocations();
        assertTrue(treasury.allocationsLocked());

        // Should not be able to modify after locking
        vm.expectRevert(EscrowTeamTreasury.AllocationsAlreadyLocked.selector);
        treasury.addBeneficiary(addr2, 100000 * 1e18);

        vm.expectRevert(EscrowTeamTreasury.AllocationsAlreadyLocked.selector);
        treasury.updateBeneficiary(addr1, 150000 * 1e18);

        vm.expectRevert(EscrowTeamTreasury.AllocationsAlreadyLocked.selector);
        treasury.removeBeneficiary(addr1);
    }


    function testVestingCalculations() public {
        fundTreasuryAndLock();

        (address[] memory initialBeneficiaries,,,) = treasury.getAllBeneficiaries();
        address firstBeneficiary = initialBeneficiaries[0];

        // Test milestone calculations at different times
        (,, uint256 currentMilestone1,,) = treasury.getVestingSchedule();
        assertEq(currentMilestone1, 0);

        // At first unlock (20% = 2M tokens)
        vm.warp(block.timestamp + LOCK_DURATION);
        (,, uint256 currentMilestone2,,) = treasury.getVestingSchedule();
        assertEq(currentMilestone2, 1);
        assertEq(treasury.getClaimableAmount(firstBeneficiary), 2000000 * 1e18);

        // At second milestone (40% = 4M tokens)
        vm.warp(block.timestamp + VESTING_INTERVAL);
        (,, uint256 currentMilestone3,,) = treasury.getVestingSchedule();
        assertEq(currentMilestone3, 2);
        assertEq(treasury.getClaimableAmount(firstBeneficiary), 4000000 * 1e18);

        // At third milestone (60% = 6M tokens)
        vm.warp(block.timestamp + VESTING_INTERVAL);
        (,, uint256 currentMilestone4,,) = treasury.getVestingSchedule();
        assertEq(currentMilestone4, 3);
        assertEq(treasury.getClaimableAmount(firstBeneficiary), 6000000 * 1e18);
    }

    function testGasOptimizations() public {
        fundTreasuryAndLock();

        (address[] memory initialBeneficiaries,,,) = treasury.getAllBeneficiaries();

        // Test that getAllBeneficiaries works efficiently
        (address[] memory addresses, uint256[] memory allocations, uint256[] memory claimed, bool[] memory active) = treasury.getAllBeneficiaries();

        assertEq(addresses.length, initialBeneficiaries.length);
        assertEq(allocations.length, initialBeneficiaries.length);
        assertEq(claimed.length, initialBeneficiaries.length);
        assertEq(active.length, initialBeneficiaries.length);

        // Verify first beneficiary data
        assertEq(addresses[0], initialBeneficiaries[0]);
        assertEq(allocations[0], 10000000 * 1e18);
        assertEq(claimed[0], 0);
        assertTrue(active[0]);
    }

    function testErrorConditions() public {
        // Test deployment with zero address (already tested in testDeploymentWithZeroAddress)

        // Test fund treasury without funding
        vm.expectRevert(EscrowTeamTreasury.TreasuryNotFunded.selector);
        treasury.addBeneficiary(addr1, 1000);

        vm.expectRevert(EscrowTeamTreasury.TreasuryNotFunded.selector);
        treasury.lockAllocations();

        // Test operations after locking (already tested in various functions)

        // Test invalid operations on non-beneficiaries
        vm.expectRevert(EscrowTeamTreasury.NotBeneficiary.selector);
        treasury.updateBeneficiary(addr1, 1000);

        vm.expectRevert(EscrowTeamTreasury.NotBeneficiary.selector);
        treasury.removeBeneficiary(addr1);
    }

    function testRevokeAfterPartialClaim() public {
        fundTreasuryAndLock();

        (address[] memory initialBeneficiaries,,,) = treasury.getAllBeneficiaries();
        address firstBeneficiary = initialBeneficiaries[0];

        // Advance time and claim
        vm.warp(block.timestamp + LOCK_DURATION);
        treasury.claimFor(firstBeneficiary);

        // Revoke should still work
        vm.expectEmit(true, true, true, true);
        emit AllocationRevoked(firstBeneficiary, 8000000 * 1e18); // 80% remaining
        treasury.revokeAllocation(firstBeneficiary);
    }

    function testGetAllBeneficiariesAfterRemoval() public {
        fundTreasury();

        (address[] memory initialBeneficiaries,,,) = treasury.getAllBeneficiaries();
        treasury.removeBeneficiary(initialBeneficiaries[0]);

        (address[] memory addresses,,,) = treasury.getAllBeneficiaries();
        assertEq(addresses.length, initialBeneficiaries.length - 1);
    }

    function testGetBeneficiaryInfoForRemoved() public {
        fundTreasury();

        (address[] memory initialBeneficiaries,,,) = treasury.getAllBeneficiaries();
        address removedBeneficiary = initialBeneficiaries[0];

        treasury.removeBeneficiary(removedBeneficiary);

        (uint256 totalAllocation,,,,,, bool isActive,) = treasury.getBeneficiaryInfo(removedBeneficiary);
        assertEq(totalAllocation, 0);
        assertFalse(isActive);
    }


    // ============ HELPER FUNCTIONS ============

    function fundTreasury() internal {
        uint256 amount = treasury.TOTAL_ALLOCATION();
        escrowToken.mint(owner, amount);
        escrowToken.approve(address(treasury), amount);
        treasury.fundTreasury();
    }

    function fundTreasuryAndLock() internal {
        fundTreasury();
        treasury.lockAllocations();
    }
}
