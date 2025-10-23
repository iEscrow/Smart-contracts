// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@forge-std/Test.sol";
import "@forge-std/console.sol";
import "../EscrowMultiTreasury.sol";
import "../contracts/mocks/MockERC20.sol";

contract EscrowMultiTreasuryTest is Test {
    EscrowMultiTreasury public treasury;
    MockERC20 public escrowToken;

    // Test accounts (initialized in setUp)
    address owner;
    address teamBeneficiary1;
    address teamBeneficiary2;
    address lpRecipient;
    address marketingRecipient;
    address user1;
    address user2;

    // Constants
    uint256 constant TOTAL_SUPPLY = 100_000_000_000 * 1e18; // 100B tokens
    uint256 constant TEAM_ALLOCATION = 1_000_000_000 * 1e18; // 1B tokens
    uint256 constant LP_ALLOCATION = 5_000_000_000 * 1e18; // 5B tokens
    uint256 constant MARKETING_ALLOCATION = 3_400_000_000 * 1e18; // 3.4B tokens
    uint256 constant TOTAL_ALLOCATION = 9_400_000_000 * 1e18; // 9.4B tokens

    // Vesting constants
    uint256 constant TEAM_LOCK_DURATION = 3 * 365 * 24 * 60 * 60; // 3 years
    uint256 constant TEAM_VESTING_INTERVAL = 180 * 24 * 60 * 60; // 6 months
    uint256 constant TEAM_VESTING_MILESTONES = 5;

    uint256 constant MARKETING_VESTING_INTERVAL = 180 * 24 * 60 * 60; // 6 months
    uint256 constant MARKETING_VESTING_MILESTONES = 4;
    uint256 constant MARKETING_PERCENTAGE_PER_MILESTONE = 2500; // 25%

    event TreasuryFunded(uint256 amount, uint256 timestamp);
    event LPAllocationSet(address indexed recipient, uint256 allocation);
    event LPClaimed(address indexed recipient, uint256 amount);
    event MarketingAllocationSet(address indexed recipient, uint256 allocation);
    event MarketingClaimed(address indexed recipient, uint256 amount, uint256 milestone);
    event TokensClaimed(address indexed beneficiary, uint256 amount, uint256 milestone);
    event BeneficiaryAdded(address indexed beneficiary, uint256 allocation);
    event BeneficiaryRemoved(address indexed beneficiary, uint256 allocation);
    event AllocationRevoked(address indexed beneficiary, uint256 unvestedAmount);

    function setUp() public {
        // Initialize test accounts first
        owner = makeAddr("owner");
        teamBeneficiary1 = makeAddr("teamBeneficiary1");
        teamBeneficiary2 = makeAddr("teamBeneficiary2");
        // Use the hardcoded addresses from the contract
        lpRecipient = 0x5f5868Bb7E708aAb9C25c80AEBFA0131735233af;
        marketingRecipient = 0xa315b46cA80982278eD28A3496718B1524Df467b;
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Start prank as owner for the entire setup
        vm.startPrank(owner);

        // Deploy mock token
        escrowToken = new MockERC20("EscrowToken", "ESCROW", 18, TOTAL_SUPPLY);

        // Deploy treasury contract from owner address so owner becomes the contract owner
        treasury = new EscrowMultiTreasury(address(escrowToken));

        // Stop prank
        vm.stopPrank();

        // Mint tokens directly to owner for funding (since MockERC20 mints to deployer by default)
        escrowToken.mint(owner, TOTAL_ALLOCATION);
    }

    // ============ HELPER FUNCTIONS ============

    function fundTreasury() internal {
        vm.prank(owner);
        escrowToken.approve(address(treasury), TOTAL_ALLOCATION);
        vm.prank(owner);
        treasury.fundTreasury();
    }

    // ============ DEPLOYMENT TESTS ============

    function testCheckOwner() public view {
        console.log("Treasury owner:", treasury.owner());
        console.log("Test owner:", owner);
        console.log("Are they equal?", treasury.owner() == owner);
    }

    function testDeployment() public view {
        assertEq(treasury.TOTAL_ALLOCATION(), TOTAL_ALLOCATION);
        assertEq(treasury.TEAM_ALLOCATION(), TEAM_ALLOCATION);
        assertEq(treasury.LP_ALLOCATION(), LP_ALLOCATION);
        assertEq(treasury.MARKETING_ALLOCATION(), MARKETING_ALLOCATION);

        // Check initial state
        assertFalse(treasury.treasuryFunded());
        assertTrue(treasury.lpAllocationActive());
        assertTrue(treasury.marketingAllocationActive());
        assertEq(treasury.lpRecipient(), lpRecipient);
        assertEq(treasury.marketingRecipient(), marketingRecipient);
        assertEq(treasury.lpAllocation(), LP_ALLOCATION);
        assertEq(treasury.marketingAllocation(), MARKETING_ALLOCATION);
    }

    function testInitialTeamBeneficiaries() public view {
        // Check that initial team beneficiaries are set up correctly
        (address[] memory addresses, uint256[] memory allocations, uint256[] memory claimed, bool[] memory active) = treasury.getAllTeamBeneficiaries();

        assertGt(addresses.length, 0, "Should have initial team beneficiaries");
        assertEq(addresses.length, allocations.length);
        assertEq(addresses.length, claimed.length);
        assertEq(addresses.length, active.length);

        // Check first beneficiary
        assertTrue(treasury.isTeamBeneficiary(addresses[0]));
        assertEq(allocations[0], 10_000_000 * 1e18); // 10M tokens
        assertEq(claimed[0], 0); // No claims yet
        assertTrue(active[0]); // Should be active
    }

    // ============ FUNDING TESTS ============

    function testFundTreasury() public {
        uint256 initialBalance = escrowToken.balanceOf(owner);

        // Fund treasury
        vm.prank(owner);
        escrowToken.approve(address(treasury), TOTAL_ALLOCATION);
        vm.prank(owner);
        treasury.fundTreasury();

        // Check state after funding
        assertTrue(treasury.treasuryFunded());
        assertEq(escrowToken.balanceOf(address(treasury)), TOTAL_ALLOCATION);
        assertEq(escrowToken.balanceOf(owner), initialBalance - TOTAL_ALLOCATION);
    }

    function testFundTreasuryTwice() public {
        vm.prank(owner);
        escrowToken.approve(address(treasury), TOTAL_ALLOCATION);
        vm.prank(owner);
        treasury.fundTreasury();

        // Try to fund again - should revert
        vm.prank(owner);
        vm.expectRevert(EscrowMultiTreasury.TreasuryAlreadyFunded.selector);
        treasury.fundTreasury();
    }

    function testFundTreasuryInsufficientBalance() public {
        // Deploy new treasury with insufficient balance
        address newOwner = makeAddr("newOwner");
        escrowToken.mint(newOwner, 1); // Give minimal tokens directly
        vm.prank(newOwner);
        EscrowMultiTreasury newTreasury = new EscrowMultiTreasury(address(escrowToken));

        // Should revert with insufficient balance
        vm.prank(newOwner);
        vm.expectRevert(EscrowMultiTreasury.InsufficientBalance.selector);
        newTreasury.fundTreasury();
    }

    // ============ LP ALLOCATION TESTS ============

    function testLPClaimImmediately() public {
        fundTreasury();

        uint256 initialBalance = escrowToken.balanceOf(lpRecipient);

        // Expect the LPClaimed event
        vm.expectEmit(true, true, true, true);
        emit LPClaimed(lpRecipient, LP_ALLOCATION);

        // Claim LP tokens
        treasury.claimLP();

        // Verify LP tokens were transferred
        assertEq(escrowToken.balanceOf(lpRecipient), initialBalance + LP_ALLOCATION);
        assertEq(treasury.lpClaimed(), LP_ALLOCATION);
    }

    function testLPClaimTwice() public {
        fundTreasury();
        treasury.claimLP();

        // Try to claim again - should revert
        vm.expectRevert(EscrowMultiTreasury.NoTokensAvailable.selector);
        treasury.claimLP();
    }

    function testLPClaimBeforeFunding() public {
        // Should revert if treasury not funded
        vm.expectRevert(EscrowMultiTreasury.TreasuryNotFunded.selector);
        treasury.claimLP();
    }


    // ============ MARKETING ALLOCATION TESTS ============

    function testMarketingClaimFirstMilestone() public {
        fundTreasury();

        // Marketing starts immediately, so claim first milestone right away
        uint256 expectedClaim = (MARKETING_ALLOCATION * MARKETING_PERCENTAGE_PER_MILESTONE) / 10000;
        uint256 initialBalance = escrowToken.balanceOf(marketingRecipient);

        // Expect the MarketingClaimed event
        vm.expectEmit(true, true, true, true);
        emit MarketingClaimed(marketingRecipient, expectedClaim, 1);

        // Claim marketing tokens
        treasury.claimMarketing();

        // Verify marketing tokens were transferred
        assertEq(escrowToken.balanceOf(marketingRecipient), initialBalance + expectedClaim);
        assertEq(treasury.marketingClaimed(), expectedClaim);
        assertEq(treasury.marketingLastClaimMilestone(), 1);
    }

    function testMarketingClaimMultipleMilestones() public {
        fundTreasury();

        uint256 expectedPerMilestone = (MARKETING_ALLOCATION * MARKETING_PERCENTAGE_PER_MILESTONE) / 10000;
        uint256 initialBalance = escrowToken.balanceOf(marketingRecipient);

        // Test all 4 milestones
        for (uint256 milestone = 1; milestone <= MARKETING_VESTING_MILESTONES; milestone++) {
            // Advance time to next milestone (advance less than full interval for first milestone)
            if (milestone == 1) {
                vm.warp(block.timestamp + MARKETING_VESTING_INTERVAL / 2);
            } else {
                vm.warp(block.timestamp + MARKETING_VESTING_INTERVAL);
            }

            uint256 expectedClaim = expectedPerMilestone * milestone;
            if (expectedClaim > MARKETING_ALLOCATION) {
                expectedClaim = MARKETING_ALLOCATION;
            }

            treasury.claimMarketing();

            // Verify claimed amount
            assertEq(treasury.marketingClaimed(), expectedClaim);
            assertEq(treasury.marketingLastClaimMilestone(), milestone);
        }

        // Verify all marketing tokens were claimed
        assertEq(treasury.marketingClaimed(), MARKETING_ALLOCATION);
        assertEq(escrowToken.balanceOf(marketingRecipient), initialBalance + MARKETING_ALLOCATION);

        // After all milestones, no more claims should be possible
        vm.warp(block.timestamp + MARKETING_VESTING_INTERVAL);
        vm.expectRevert(EscrowMultiTreasury.NoTokensAvailable.selector);
        treasury.claimMarketing();
    }

    function testMarketingClaimBeforeFunding() public {
        // Should revert if treasury not funded
        vm.expectRevert(EscrowMultiTreasury.TreasuryNotFunded.selector);
        treasury.claimMarketing();
    }

    function testMarketingClaimEarly() public {
        fundTreasury();

        // Marketing starts vesting immediately, so this should work, not revert
        // Let's test that it claims the first milestone immediately
        uint256 expectedClaim = (MARKETING_ALLOCATION * MARKETING_PERCENTAGE_PER_MILESTONE) / 10000;
        uint256 initialBalance = escrowToken.balanceOf(marketingRecipient);

        vm.expectEmit(true, true, true, true);
        emit MarketingClaimed(marketingRecipient, expectedClaim, 1);

        treasury.claimMarketing();

        assertEq(escrowToken.balanceOf(marketingRecipient), initialBalance + expectedClaim);
        assertEq(treasury.marketingClaimed(), expectedClaim);
        assertEq(treasury.marketingLastClaimMilestone(), 1);
    }

    function testMarketingClaimSameMilestoneAfterInterval() public {
        fundTreasury();

        // Advance to first milestone and claim
        vm.warp(block.timestamp + MARKETING_VESTING_INTERVAL);
        treasury.claimMarketing();

        // Try to claim again in same milestone
        vm.expectRevert(EscrowMultiTreasury.NoTokensAvailable.selector);
        treasury.claimMarketing();
    }

    // ============ TEAM ALLOCATION TESTS ============

    function testTeamClaimBeforeLockPeriod() public {
        fundTreasury();
        vm.prank(owner);
        treasury.lockAllocations();

        (address[] memory initialBeneficiaries,,,) = treasury.getAllTeamBeneficiaries();
        address firstBeneficiary = initialBeneficiaries[0];

        // Before 3-year lock period
        vm.expectRevert(EscrowMultiTreasury.NoTokensAvailable.selector);
        treasury.claimFor(firstBeneficiary);
    }

    function testTeamClaimAfterThreeYears() public {
        fundTreasury();
        vm.prank(owner);
        treasury.lockAllocations();

        (address[] memory initialBeneficiaries,,,) = treasury.getAllTeamBeneficiaries();
        address firstBeneficiary = initialBeneficiaries[0];

        // Advance time by 3 years (lock duration) + 1 second to ensure we're past unlock time
        vm.warp(block.timestamp + TEAM_LOCK_DURATION + 1);

        uint256 expectedClaimAmount = 2000000 * 1e18; // 20% of 10M

        // Expect the TokensClaimed event from the treasury contract
        vm.expectEmit(true, true, true, true);
        emit TokensClaimed(firstBeneficiary, expectedClaimAmount, 1);

        treasury.claimFor(firstBeneficiary);

        // Verify claim
        (,, uint256 claimedAmount,,,,,) = treasury.getTeamBeneficiaryInfo(firstBeneficiary);
        assertEq(claimedAmount, expectedClaimAmount);
    }

    function testTeamClaimMultipleMilestones() public {
        fundTreasury();
        vm.prank(owner);
        treasury.lockAllocations();

        (address[] memory initialBeneficiaries,,,) = treasury.getAllTeamBeneficiaries();
        address firstBeneficiary = initialBeneficiaries[0];

        uint256 expectedAmountPerMilestone = 2000000 * 1e18; // 20% of 10M

        // Test all 5 milestones
        for (uint256 milestone = 1; milestone <= TEAM_VESTING_MILESTONES; milestone++) {
            // Advance time to next milestone (for first milestone, include lock duration)
            if (milestone == 1) {
                vm.warp(block.timestamp + TEAM_LOCK_DURATION + 1);
            } else {
                vm.warp(block.timestamp + TEAM_VESTING_INTERVAL);
            }

            treasury.claimFor(firstBeneficiary);

            // Verify claimed amount
            (,, uint256 claimedAmount,,,,,) = treasury.getTeamBeneficiaryInfo(firstBeneficiary);
            assertEq(claimedAmount, expectedAmountPerMilestone * milestone);
        }

        // After all milestones, no more claims should be possible
        vm.warp(block.timestamp + TEAM_VESTING_INTERVAL);
        vm.expectRevert(EscrowMultiTreasury.NoTokensAvailable.selector);
        treasury.claimFor(firstBeneficiary);
    }

    // ============ COMPREHENSIVE TESTS ============

    function testCompleteAllocationWorkflow() public {
        // Fund treasury
        vm.prank(owner);
        escrowToken.approve(address(treasury), TOTAL_ALLOCATION);
        vm.prank(owner);
        treasury.fundTreasury();

        // Verify all allocations are set up
        assertTrue(treasury.treasuryFunded());
        assertTrue(treasury.lpAllocationActive());
        assertTrue(treasury.marketingAllocationActive());

        // Test LP claiming (immediate)
        uint256 lpInitialBalance = escrowToken.balanceOf(lpRecipient);
        treasury.claimLP();
        assertEq(escrowToken.balanceOf(lpRecipient), lpInitialBalance + LP_ALLOCATION);

        // Test Marketing claiming (over time) - advance less than full interval to stay at milestone 1
        vm.warp(block.timestamp + MARKETING_VESTING_INTERVAL / 2);
        uint256 marketingInitialBalance = escrowToken.balanceOf(marketingRecipient);
        treasury.claimMarketing();
        assertEq(escrowToken.balanceOf(marketingRecipient), marketingInitialBalance + (MARKETING_ALLOCATION * MARKETING_PERCENTAGE_PER_MILESTONE / 10000));

        // Test Team claiming (after lock)
        vm.prank(owner);
        treasury.lockAllocations();
        vm.warp(block.timestamp + TEAM_LOCK_DURATION + 1);

        (address[] memory initialBeneficiaries,,,) = treasury.getAllTeamBeneficiaries();
        address firstBeneficiary = initialBeneficiaries[0];

        uint256 teamInitialBalance = escrowToken.balanceOf(firstBeneficiary);
        treasury.claimFor(firstBeneficiary);
        assertEq(escrowToken.balanceOf(firstBeneficiary), teamInitialBalance + 2000000 * 1e18);

        // Verify total balance in contract
        uint256 expectedRemaining = TOTAL_ALLOCATION - LP_ALLOCATION - (MARKETING_ALLOCATION * MARKETING_PERCENTAGE_PER_MILESTONE / 10000) - 2000000 * 1e18;
        assertEq(escrowToken.balanceOf(address(treasury)), expectedRemaining);
    }

    // ============ ADMIN FUNCTION TESTS ============

    function testAddBeneficiaryBeforeLock() public {
        fundTreasury();

        address newBeneficiary = makeAddr("newBeneficiary");
        uint256 allocationAmount = 1_000_000 * 1e18; // 1M tokens

        // TEAM_ALLOCATION is already fully allocated with initial beneficiaries
        // Adding any more should exceed the limit
        vm.prank(owner);
        vm.expectRevert(EscrowMultiTreasury.ExceedsTotalAllocation.selector);
        treasury.addBeneficiary(newBeneficiary, allocationAmount);
    }

    function testAddBeneficiaryExceedsAllocation() public {
        fundTreasury();

        // Try to add more than TEAM_ALLOCATION (1B tokens)
        vm.prank(owner);
        vm.expectRevert(EscrowMultiTreasury.ExceedsTotalAllocation.selector);
        treasury.addBeneficiary(makeAddr("newBeneficiary"), TEAM_ALLOCATION + 1);
    }

    function testAddBeneficiaryZeroAmount() public {
        fundTreasury();

        vm.prank(owner);
        vm.expectRevert(EscrowMultiTreasury.InvalidAmount.selector);
        treasury.addBeneficiary(makeAddr("newBeneficiary"), 0);
    }

    function testAddBeneficiaryZeroAddress() public {
        fundTreasury();

        vm.prank(owner);
        vm.expectRevert(EscrowMultiTreasury.InvalidAddress.selector);
        treasury.addBeneficiary(address(0), 1_000_000 * 1e18);
    }

    function testAddBeneficiaryAfterLock() public {
        fundTreasury();
        vm.prank(owner);
        treasury.lockAllocations();

        // This should revert because allocations are locked
        vm.prank(owner);
        vm.expectRevert(EscrowMultiTreasury.AllocationsAlreadyLocked.selector);
        treasury.addBeneficiary(makeAddr("newBeneficiary"), 1_000_000 * 1e18);
    }

    function testRevokeAllocation() public {
        fundTreasury();
        vm.prank(owner);
        treasury.lockAllocations();

        (address[] memory initialBeneficiaries,,,) = treasury.getAllTeamBeneficiaries();
        address firstBeneficiary = initialBeneficiaries[0];

        // Advance time past lock period
        vm.warp(block.timestamp + TEAM_LOCK_DURATION + 1);

        vm.prank(owner);
        treasury.revokeAllocation(firstBeneficiary);

        // Verify allocation was revoked
        (,,,,,, bool isActive, bool revoked) = treasury.getTeamBeneficiaryInfo(firstBeneficiary);
        assertTrue(isActive); // Still active but revoked
        assertTrue(revoked);
    }

    function testRevokeAllocationNotBeneficiary() public {
        fundTreasury();
        vm.prank(owner);
        treasury.lockAllocations();

        vm.prank(owner);
        vm.expectRevert(EscrowMultiTreasury.NotBeneficiary.selector);
        treasury.revokeAllocation(makeAddr("newBeneficiary"));
    }

    function testLockAllocationsNotFunded() public {
        vm.prank(owner);
        vm.expectRevert(EscrowMultiTreasury.TreasuryNotFunded.selector);
        treasury.lockAllocations();
    }

    function testLockAllocationsTwice() public {
        fundTreasury();
        vm.prank(owner);
        treasury.lockAllocations();

        vm.prank(owner);
        vm.expectRevert(EscrowMultiTreasury.AllocationsAlreadyLocked.selector);
        treasury.lockAllocations();
    }

    function testClaimForNotLocked() public {
        fundTreasury();

        (address[] memory initialBeneficiaries,,,) = treasury.getAllTeamBeneficiaries();
        address firstBeneficiary = initialBeneficiaries[0];

        vm.expectRevert(EscrowMultiTreasury.AllocationsNotLocked.selector);
        treasury.claimFor(firstBeneficiary);
    }

    function testClaimForNotBeneficiary() public {
        fundTreasury();
        vm.prank(owner);
        treasury.lockAllocations();

        address nonBeneficiary = makeAddr("nonBeneficiary");
        vm.expectRevert(EscrowMultiTreasury.NotBeneficiary.selector);
        treasury.claimFor(nonBeneficiary);
    }

    function testClaimForNoTokensAvailable() public {
        fundTreasury();
        vm.prank(owner);
        treasury.lockAllocations();

        (address[] memory initialBeneficiaries,,,) = treasury.getAllTeamBeneficiaries();
        address firstBeneficiary = initialBeneficiaries[0];

        // Advance time past all milestones
        vm.warp(block.timestamp + TEAM_LOCK_DURATION + (TEAM_VESTING_MILESTONES * TEAM_VESTING_INTERVAL) + 1);

        // Claim all available tokens
        treasury.claimFor(firstBeneficiary);

        // Try to claim again - should revert
        vm.expectRevert(EscrowMultiTreasury.NoTokensAvailable.selector);
        treasury.claimFor(firstBeneficiary);
    }

    function testGetTeamClaimableAmountNotActive() public {
        address nonBeneficiary = makeAddr("nonBeneficiary");
        assertEq(treasury.getTeamClaimableAmount(nonBeneficiary), 0);
    }

    // ============ EDGE CASE TESTS ============

    function testMilestoneCalculationEdgeCases() public {
        fundTreasury();
        vm.prank(owner);
        treasury.lockAllocations();

        (address[] memory initialBeneficiaries,,,) = treasury.getAllTeamBeneficiaries();
        address firstBeneficiary = initialBeneficiaries[0];

        // Test milestone 0 (before lock period)
        assertEq(treasury.getTeamVestingSchedule().currentMilestone, 0);

        // Test exactly at unlock time
        vm.warp(block.timestamp + TEAM_LOCK_DURATION);
        assertEq(treasury.getTeamVestingSchedule().currentMilestone, 1);

        // Test after first interval
        vm.warp(block.timestamp + TEAM_VESTING_INTERVAL);
        assertEq(treasury.getTeamVestingSchedule().currentMilestone, 2);

        // Test after all milestones
        vm.warp(block.timestamp + (TEAM_VESTING_MILESTONES - 1) * TEAM_VESTING_INTERVAL);
        assertEq(treasury.getTeamVestingSchedule().currentMilestone, TEAM_VESTING_MILESTONES);
    }

    function testTreasuryStatsAfterClaims() public {
        fundTreasury();

        // Get initial stats
        EscrowMultiTreasury.TreasuryStats memory initialStats = treasury.getTreasuryStats();
        assertEq(initialStats.totalClaimed, 0);
        assertEq(initialStats.teamBeneficiaryCount, 28); // Should have hardcoded beneficiaries

        // Claim LP tokens
        treasury.claimLP();
        EscrowMultiTreasury.TreasuryStats memory afterLpStats = treasury.getTreasuryStats();
        assertEq(afterLpStats.totalClaimed, LP_ALLOCATION);

        // Claim marketing tokens
        vm.warp(block.timestamp + MARKETING_VESTING_INTERVAL / 2);
        treasury.claimMarketing();
        EscrowMultiTreasury.TreasuryStats memory afterMarketingStats = treasury.getTreasuryStats();
        assertEq(afterMarketingStats.totalClaimed, LP_ALLOCATION + (MARKETING_ALLOCATION * MARKETING_PERCENTAGE_PER_MILESTONE / 10000));

        // Lock and claim team tokens
        vm.prank(owner);
        treasury.lockAllocations();
        vm.warp(block.timestamp + TEAM_LOCK_DURATION + 1);
        (address[] memory initialBeneficiaries,,,) = treasury.getAllTeamBeneficiaries();
        treasury.claimFor(initialBeneficiaries[0]);
        EscrowMultiTreasury.TreasuryStats memory finalStats = treasury.getTreasuryStats();
        assertGt(finalStats.totalClaimed, LP_ALLOCATION + (MARKETING_ALLOCATION * MARKETING_PERCENTAGE_PER_MILESTONE / 10000));
    }

    function testGetContractInfo() public {
        EscrowMultiTreasury.ContractInfo memory info = treasury.getContractInfo();

        assertEq(info.tokenAddress, address(escrowToken));
        assertEq(info.totalAllocation, TOTAL_ALLOCATION);
        assertEq(info.teamAllocation, TEAM_ALLOCATION);
        assertEq(info.lpAllocation, LP_ALLOCATION);
        assertEq(info.marketingAllocation, MARKETING_ALLOCATION);
        assertEq(info.teamLockDuration, TEAM_LOCK_DURATION);
        assertEq(info.teamVestingInterval, TEAM_VESTING_INTERVAL);
        assertEq(info.teamMilestones, TEAM_VESTING_MILESTONES);
        assertEq(info.teamPercentPerMilestone, 2000); // TEAM_PERCENTAGE_PER_MILESTONE
        assertEq(info.marketingVestingInterval, MARKETING_VESTING_INTERVAL);
        assertEq(info.marketingMilestones, MARKETING_VESTING_MILESTONES);
        assertEq(info.marketingPercentPerMilestone, MARKETING_PERCENTAGE_PER_MILESTONE);
    }

    function testGetTeamBeneficiaryInfoNotActive() public {
        address nonBeneficiary = makeAddr("nonBeneficiary");

        (uint256 totalAllocation, uint256 vestedAmount, uint256 claimedAmount, uint256 claimableAmount, uint256 remainingAmount, uint256 currentMilestone, bool isActive, bool revoked) = treasury.getTeamBeneficiaryInfo(nonBeneficiary);

        assertEq(totalAllocation, 0);
        assertEq(vestedAmount, 0);
        assertEq(claimedAmount, 0);
        assertEq(claimableAmount, 0);
        assertEq(remainingAmount, 0);
        assertEq(currentMilestone, treasury.getTeamVestingSchedule().currentMilestone);
        assertFalse(isActive);
        assertFalse(revoked);
    }

    function testMultipleClaimsInSameMilestone() public {
        fundTreasury();
        vm.prank(owner);
        treasury.lockAllocations();

        (address[] memory initialBeneficiaries,,,) = treasury.getAllTeamBeneficiaries();
        address firstBeneficiary = initialBeneficiaries[0];

        // Advance to first milestone
        vm.warp(block.timestamp + TEAM_LOCK_DURATION + 1);

        // Claim first time
        treasury.claimFor(firstBeneficiary);

        // Try to claim again in same milestone - should revert
        vm.expectRevert(EscrowMultiTreasury.NoTokensAvailable.selector);
        treasury.claimFor(firstBeneficiary);
    }

    function testClaimAfterRevocation() public {
        fundTreasury();
        vm.prank(owner);
        treasury.lockAllocations();

        (address[] memory initialBeneficiaries,,,) = treasury.getAllTeamBeneficiaries();
        address firstBeneficiary = initialBeneficiaries[0];

        // Advance time and revoke
        vm.warp(block.timestamp + TEAM_LOCK_DURATION + 1);
        vm.prank(owner);
        treasury.revokeAllocation(firstBeneficiary);

        // Try to claim after revocation - should revert
        vm.expectRevert(EscrowMultiTreasury.AllocationAlreadyRevoked.selector);
        treasury.claimFor(firstBeneficiary);
    }

    function testNextUnlockTimeCalculations() public {
        fundTreasury();
        vm.prank(owner);
        treasury.lockAllocations();

        // Before lock period
        assertEq(treasury.getNextTeamUnlockTime(), treasury.teamFirstUnlockTime());

        // Advance to first milestone
        vm.warp(block.timestamp + TEAM_LOCK_DURATION + 1);
        assertEq(treasury.getNextTeamUnlockTime(), treasury.teamFirstUnlockTime() + TEAM_VESTING_INTERVAL);

        // Advance past all milestones
        vm.warp(block.timestamp + (TEAM_VESTING_MILESTONES - 1) * TEAM_VESTING_INTERVAL);
        assertEq(treasury.getNextTeamUnlockTime(), 0); // No more unlocks
    }

    function testRemoveBeneficiaryAfterLock() public {
        fundTreasury();
        vm.prank(owner);
        treasury.lockAllocations();

        (address[] memory initialBeneficiaries,,,) = treasury.getAllTeamBeneficiaries();
        address firstBeneficiary = initialBeneficiaries[0];

        vm.prank(owner);
        vm.expectRevert(EscrowMultiTreasury.AllocationsAlreadyLocked.selector);
        treasury.removeBeneficiary(firstBeneficiary);
    }

    function testCalculationPrecision() public {
        fundTreasury();
        vm.prank(owner);
        treasury.lockAllocations();

        (address[] memory initialBeneficiaries,,,) = treasury.getAllTeamBeneficiaries();
        address firstBeneficiary = initialBeneficiaries[0];

        // Test exact milestone timing
        vm.warp(block.timestamp + TEAM_LOCK_DURATION);
        uint256 claimable1 = treasury.getTeamClaimableAmount(firstBeneficiary);
        assertEq(claimable1, 2000000 * 1e18); // Exactly 20%

        // Test after one interval
        vm.warp(block.timestamp + TEAM_VESTING_INTERVAL);
        uint256 claimable2 = treasury.getTeamClaimableAmount(firstBeneficiary);
        assertEq(claimable2, 4000000 * 1e18); // Exactly 40%
    }

    function testRemoveBeneficiary() public {
        fundTreasury();

        (address[] memory initialBeneficiaries,,,) = treasury.getAllTeamBeneficiaries();
        address firstBeneficiary = initialBeneficiaries[0];
        uint256 initialAllocation = 10_000_000 * 1e18;
        uint256 initialTotalAllocated = treasury.teamTotalAllocated();
        uint256 initialBeneficiaryCount = initialBeneficiaries.length;

        // Remove beneficiary
        vm.expectEmit(true, true, true, true);
        emit BeneficiaryRemoved(firstBeneficiary, initialAllocation);

        vm.prank(owner);
        treasury.removeBeneficiary(firstBeneficiary);

        // Verify removal
        assertFalse(treasury.isTeamBeneficiary(firstBeneficiary));
        assertEq(treasury.teamTotalAllocated(), initialTotalAllocated - initialAllocation);

        // Verify from list
        (address[] memory newBeneficiaries,,,) = treasury.getAllTeamBeneficiaries();
        assertEq(newBeneficiaries.length, initialBeneficiaryCount - 1);
    }

    function testRemoveBeneficiaryNotActive() public {
        fundTreasury();

        vm.prank(owner);
        vm.expectRevert(EscrowMultiTreasury.NotBeneficiary.selector);
        treasury.removeBeneficiary(makeAddr("newBeneficiary"));
    }

    function testTimeUntilNextMarketingUnlock() public {
        fundTreasury();

        // Initially: should return time when milestone 1 fully unlocks
        uint256 expectedFirstUnlock = treasury.marketingStartTime() + MARKETING_VESTING_INTERVAL;
        assertEq(treasury.getTimeUntilNextMarketingUnlock(), expectedFirstUnlock);

        // Claim milestone 1 - should still return same unlock time
        treasury.claimMarketing();
        assertEq(treasury.getTimeUntilNextMarketingUnlock(), expectedFirstUnlock);

        // Advance time past first interval - now milestone 2 becomes available
        vm.warp(block.timestamp + MARKETING_VESTING_INTERVAL);

        // Now should return time when milestone 2 fully unlocks
        uint256 expectedSecondUnlock = treasury.marketingStartTime() + (2 * MARKETING_VESTING_INTERVAL);
        assertEq(treasury.getTimeUntilNextMarketingUnlock(), expectedSecondUnlock);

        // Claim milestone 2
        treasury.claimMarketing();

        // Advance past second interval - now milestone 3 becomes available
        vm.warp(block.timestamp + MARKETING_VESTING_INTERVAL);

        // Should return time when milestone 3 fully unlocks
        uint256 expectedThirdUnlock = treasury.marketingStartTime() + (3 * MARKETING_VESTING_INTERVAL);
        assertEq(treasury.getTimeUntilNextMarketingUnlock(), expectedThirdUnlock);

        // Claim milestone 3
        treasury.claimMarketing();

        // Advance past third interval - now milestone 4 becomes available
        vm.warp(block.timestamp + MARKETING_VESTING_INTERVAL);

        // Should return 0 since milestone 4 is now available
        assertEq(treasury.getTimeUntilNextMarketingUnlock(), 0); // Should be 0 since milestone 4 is available

        // Claim milestone 4
        treasury.claimMarketing();

        // Debug: check current milestone after claiming 4
        console.log("Current milestone after claiming 4:", treasury.getMarketingCurrentMilestone());
        console.log("Last claim milestone after claiming 4:", treasury.marketingLastClaimMilestone());

        // Should return 0 when all milestones claimed
        assertEq(treasury.getTimeUntilNextMarketingUnlock(), 0);

        // Try to claim after all milestones - should revert
        vm.warp(block.timestamp + MARKETING_VESTING_INTERVAL);
        vm.expectRevert(EscrowMultiTreasury.NoTokensAvailable.selector);
        treasury.claimMarketing();
    }
}
