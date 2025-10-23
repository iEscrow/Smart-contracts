// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@forge-std/Test.sol";
import "@forge-std/console.sol";
import "../EscrowMultiTreasury.sol";
import "../contracts/mocks/MockERC20.sol";

contract EscrowMultiTreasuryTest is Test {
    EscrowMultiTreasury public treasury;
    MockERC20 public escrowToken;

    // Test accounts
    address public owner;
    address public teamBeneficiary1;
    address public teamBeneficiary2;
    address public lpRecipient;
    address public marketingRecipient;
    address public user1;
    address public user2;

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

    function setUp() public {
        // Initialize test accounts
        owner = address(this);
        teamBeneficiary1 = makeAddr("teamBeneficiary1");
        teamBeneficiary2 = makeAddr("teamBeneficiary2");
        lpRecipient = 0x5f5868Bb7E708aAb9C25c80AEBFA0131735233af;
        marketingRecipient = 0xa315b46cA80982278eD28A3496718B1524Df467b;
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy mock token
        escrowToken = new MockERC20("EscrowToken", "ESCROW", 18, TOTAL_SUPPLY);

        // Deploy treasury contract
        treasury = new EscrowMultiTreasury(address(escrowToken));

        // Transfer tokens to owner for funding
        escrowToken.transfer(owner, TOTAL_ALLOCATION);
    }

    // ============ DEPLOYMENT TESTS ============

    function testDeployment() public view {
        // Check basic deployment
        assertEq(address(treasury.escrowToken()), address(escrowToken));
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
        escrowToken.approve(address(treasury), TOTAL_ALLOCATION);
        treasury.fundTreasury();

        // Check state after funding
        assertTrue(treasury.treasuryFunded());
        assertEq(escrowToken.balanceOf(address(treasury)), TOTAL_ALLOCATION);
        assertEq(escrowToken.balanceOf(owner), initialBalance - TOTAL_ALLOCATION);
    }

    function testFundTreasuryTwice() public {
        escrowToken.approve(address(treasury), TOTAL_ALLOCATION);
        treasury.fundTreasury();

        // Try to fund again - should revert
        vm.expectRevert(EscrowMultiTreasury.TreasuryAlreadyFunded.selector);
        treasury.fundTreasury();
    }

    function testFundTreasuryInsufficientBalance() public {
        // Deploy new treasury with insufficient balance
        address newOwner = makeAddr("newOwner");
        escrowToken.transfer(newOwner, 1); // Give minimal tokens
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

    function testMarketingClaimSameMilestone() public {
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
        treasury.lockAllocations();

        (address[] memory initialBeneficiaries,,,) = treasury.getAllTeamBeneficiaries();
        address firstBeneficiary = initialBeneficiaries[0];

        // Before 3-year lock period
        vm.expectRevert(EscrowMultiTreasury.NoTokensAvailable.selector);
        treasury.claimFor(firstBeneficiary);
    }

    function testTeamClaimAfterThreeYears() public {
        fundTreasury();
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
        escrowToken.approve(address(treasury), TOTAL_ALLOCATION);
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

    function testTreasuryStats() public {
        fundTreasury();

        EscrowMultiTreasury.TreasuryStats memory stats = treasury.getTreasuryStats();

        assertEq(stats.teamTotalAlloc, TEAM_ALLOCATION);
        assertEq(stats.teamTotalClaim, 0);
        assertEq(stats.teamTotalRemaining, TEAM_ALLOCATION);
        assertEq(stats.lpTotalAlloc, LP_ALLOCATION);
        assertEq(stats.lpTotalClaim, 0);
        assertEq(stats.lpTotalRemaining, LP_ALLOCATION);
        assertEq(stats.marketingTotalAlloc, MARKETING_ALLOCATION);
        assertEq(stats.marketingTotalClaim, 0);
        assertEq(stats.marketingTotalRemaining, MARKETING_ALLOCATION);
        assertFalse(stats.globalLocked);
        assertTrue(stats.globalFunded);
    }

    // ============ HELPER FUNCTIONS ============

    function fundTreasury() internal {
        escrowToken.approve(address(treasury), TOTAL_ALLOCATION);
        treasury.fundTreasury();
    }
}
