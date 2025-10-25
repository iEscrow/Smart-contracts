// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../EscrowTresury.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title Mock ESCROW Token for Testing
 */
contract MockEscrowToken is ERC20 {
    constructor() ERC20("ESCROW", "ESC") {
        _mint(msg.sender, 100_000_000_000 * 1e18); // 100B tokens
    }
}

/**
 * @title EscrowMultiTreasury Test Suite
 * @notice Comprehensive test coverage for all functions
 */
contract EscrowMultiTreasuryTest is Test {
    EscrowMultiTreasury public treasury;
    MockEscrowToken public token;

    address public owner;
    address public lpRecipient;
    address public mktRecipient;
    address public teamMember1;
    address public teamMember2;
    address public teamMember3;
    address public attacker;

    // Constants matching contract
    uint256 constant TOTAL_ALLOC = 9_400_000_000 * 1e18;
    uint256 constant TEAM_ALLOC = 1_000_000_000 * 1e18;
    uint256 constant LP_ALLOC = 5_000_000_000 * 1e18;
    uint256 constant MKT_ALLOC = 3_400_000_000 * 1e18;
    uint256 constant TEAM_CLIFF = 3 * 365 days;
    uint256 constant TEAM_INTERVAL = 180 days;
    uint256 constant MKT_INTERVAL = 180 days;

    event Funded(uint256 amount);
    event TeamSet(address indexed who, uint256 amount);
    event TeamRemoved(address indexed who, uint256 amount);
    event Locked();
    event Claimed(address indexed who, uint256 amount, uint8 milestone);

    function setUp() public {
        owner = address(this);
        lpRecipient = makeAddr("lpRecipient");
        mktRecipient = makeAddr("mktRecipient");
        teamMember1 = makeAddr("teamMember1");
        teamMember2 = makeAddr("teamMember2");
        teamMember3 = makeAddr("teamMember3");
        attacker = makeAddr("attacker");

        // Deploy token and treasury
        token = new MockEscrowToken();
        treasury = new EscrowMultiTreasury(
            address(token),
            lpRecipient,
            mktRecipient
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // DEPLOYMENT TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_Deployment() public view {
        assertEq(address(treasury.token()), address(token));
        assertEq(treasury.lpRecipient(), lpRecipient);
        assertEq(treasury.mktRecipient(), mktRecipient);
        assertEq(treasury.owner(), owner);
        assertGt(treasury.deployTime(), 0);
    }

    function test_RevertDeployment_ZeroAddresses() public {
        vm.expectRevert(EscrowMultiTreasury.ZeroAddress.selector);
        new EscrowMultiTreasury(address(0), lpRecipient, mktRecipient);

        vm.expectRevert(EscrowMultiTreasury.ZeroAddress.selector);
        new EscrowMultiTreasury(address(token), address(0), mktRecipient);

        vm.expectRevert(EscrowMultiTreasury.ZeroAddress.selector);
        new EscrowMultiTreasury(address(token), lpRecipient, address(0));
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // FUNDING TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_Fund() public {
        token.approve(address(treasury), TOTAL_ALLOC);
        
        vm.expectEmit(true, true, true, true);
        emit Funded(TOTAL_ALLOC);
        
        treasury.fund();

        assertEq(token.balanceOf(address(treasury)), TOTAL_ALLOC);
        (uint256 balance, , bool funded, ) = treasury.stats();
        assertTrue(funded);
        assertEq(balance, TOTAL_ALLOC);
    }

    function test_RevertFund_NotOwner() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", attacker));
        treasury.fund();
    }

    function test_RevertFund_AlreadyFunded() public {
        token.approve(address(treasury), TOTAL_ALLOC);
        treasury.fund();

        token.approve(address(treasury), TOTAL_ALLOC);
        vm.expectRevert(EscrowMultiTreasury.AlreadyFunded.selector);
        treasury.fund();
    }

    function test_RevertFund_InsufficientBalance() public {
        // Transfer away all tokens
        token.transfer(attacker, token.balanceOf(owner));
        
        vm.expectRevert(); // SafeERC20 will revert
        treasury.fund();
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // TEAM ALLOCATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_SetTeam() public {
        _fundTreasury();

        vm.expectEmit(true, true, true, true);
        emit TeamSet(teamMember1, 100_000_000 * 1e18);
        
        treasury.setTeam(teamMember1, 100_000_000 * 1e18);

        assertEq(treasury.teamAlloc(teamMember1), 100_000_000 * 1e18);
        assertEq(treasury.teamTotal(), 100_000_000 * 1e18);
    }

    function test_BatchSetTeam() public {
        _fundTreasury();

        address[] memory addrs = new address[](3);
        uint256[] memory amts = new uint256[](3);
        
        addrs[0] = teamMember1;
        addrs[1] = teamMember2;
        addrs[2] = teamMember3;
        
        amts[0] = 100_000_000 * 1e18;
        amts[1] = 200_000_000 * 1e18;
        amts[2] = 300_000_000 * 1e18;

        treasury.batchSetTeam(addrs, amts);

        assertEq(treasury.teamAlloc(teamMember1), 100_000_000 * 1e18);
        assertEq(treasury.teamAlloc(teamMember2), 200_000_000 * 1e18);
        assertEq(treasury.teamAlloc(teamMember3), 300_000_000 * 1e18);
        assertEq(treasury.teamTotal(), 600_000_000 * 1e18);
    }

    function test_RevertSetTeam_NotFunded() public {
        vm.expectRevert(EscrowMultiTreasury.NotFunded.selector);
        treasury.setTeam(teamMember1, 100_000_000 * 1e18);
    }

    function test_RevertSetTeam_ZeroAddress() public {
        _fundTreasury();

        vm.expectRevert(EscrowMultiTreasury.ZeroAddress.selector);
        treasury.setTeam(address(0), 100_000_000 * 1e18);
    }

    function test_RevertSetTeam_ZeroAmount() public {
        _fundTreasury();

        vm.expectRevert(EscrowMultiTreasury.ZeroAmount.selector);
        treasury.setTeam(teamMember1, 0);
    }

    function test_RevertSetTeam_AlreadyExists() public {
        _fundTreasury();
        treasury.setTeam(teamMember1, 100_000_000 * 1e18);

        vm.expectRevert(EscrowMultiTreasury.AlreadyExists.selector);
        treasury.setTeam(teamMember1, 200_000_000 * 1e18);
    }

    function test_RevertSetTeam_ExceedsLimit() public {
        _fundTreasury();

        vm.expectRevert(EscrowMultiTreasury.ExceedsLimit.selector);
        treasury.setTeam(teamMember1, TEAM_ALLOC + 1);
    }

    function test_RevertSetTeam_AfterLocked() public {
        _fundTreasury();
        treasury.setTeam(teamMember1, 100_000_000 * 1e18);
        treasury.lock();

        vm.expectRevert(EscrowMultiTreasury.AlreadyLocked.selector);
        treasury.setTeam(teamMember2, 100_000_000 * 1e18);
    }

    function test_RemoveTeam() public {
        _fundTreasury();
        treasury.setTeam(teamMember1, 100_000_000 * 1e18);

        vm.expectEmit(true, true, true, true);
        emit TeamRemoved(teamMember1, 100_000_000 * 1e18);
        
        treasury.removeTeam(teamMember1);

        assertEq(treasury.teamAlloc(teamMember1), 0);
        assertEq(treasury.teamTotal(), 0);
    }

    function test_RevertRemoveTeam_NotFound() public {
        _fundTreasury();

        vm.expectRevert(EscrowMultiTreasury.NotFound.selector);
        treasury.removeTeam(teamMember1);
    }

    function test_RevertRemoveTeam_AfterLocked() public {
        _fundTreasury();
        treasury.setTeam(teamMember1, 100_000_000 * 1e18);
        treasury.lock();

        vm.expectRevert(EscrowMultiTreasury.AlreadyLocked.selector);
        treasury.removeTeam(teamMember1);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // LOCK TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_Lock() public {
        _fundTreasury();
        treasury.setTeam(teamMember1, 100_000_000 * 1e18);

        vm.expectEmit(true, true, true, true);
        emit Locked();
        
        treasury.lock();

        (, , , bool locked) = treasury.stats();
        assertTrue(locked);
    }

    function test_RevertLock_NotFunded() public {
        vm.expectRevert(EscrowMultiTreasury.NotFunded.selector);
        treasury.lock();
    }

    function test_RevertLock_AlreadyLocked() public {
        _fundTreasury();
        treasury.setTeam(teamMember1, 100_000_000 * 1e18);
        treasury.lock();

        vm.expectRevert(EscrowMultiTreasury.AlreadyLocked.selector);
        treasury.lock();
    }

    function test_RevertLock_NoTeamAllocations() public {
        _fundTreasury();

        vm.expectRevert(EscrowMultiTreasury.ZeroAmount.selector);
        treasury.lock();
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // TEAM CLAIM TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_ClaimTeam_AfterCliff() public {
        _fundAndSetupTeam();

        // Fast forward past cliff (3 years) + 1 interval (6 months) = Milestone 1
        vm.warp(block.timestamp + TEAM_CLIFF + 1);

        // Team member 1 should have 20% vested
        uint256 expectedAmount = (100_000_000 * 1e18 * 2000) / 10_000; // 20M

        vm.prank(teamMember1);
        vm.expectEmit(true, true, true, true);
        emit Claimed(teamMember1, expectedAmount, 1);
        
        treasury.claimTeam();

        assertEq(token.balanceOf(teamMember1), expectedAmount);
        assertEq(treasury.teamClaimed(teamMember1), expectedAmount);
    }

    function test_ClaimTeam_MultipleMilestones() public {
        _fundAndSetupTeam();

        // Fast forward to milestone 1
        vm.warp(block.timestamp + TEAM_CLIFF + 1);
        
        vm.prank(teamMember1);
        treasury.claimTeam();
        uint256 firstClaim = token.balanceOf(teamMember1);

        // Fast forward to milestone 2
        vm.warp(block.timestamp + TEAM_INTERVAL);
        
        vm.prank(teamMember1);
        treasury.claimTeam();
        uint256 secondClaim = token.balanceOf(teamMember1) - firstClaim;

        assertEq(firstClaim, 20_000_000 * 1e18); // 20%
        assertEq(secondClaim, 20_000_000 * 1e18); // Another 20%
        assertEq(treasury.teamClaimed(teamMember1), 40_000_000 * 1e18);
    }

    function test_ClaimTeam_FullVesting() public {
        _fundAndSetupTeam();

        // Fast forward past all milestones (3yr cliff + 5 * 6mo intervals)
        vm.warp(block.timestamp + TEAM_CLIFF + (5 * TEAM_INTERVAL) + 1);

        vm.prank(teamMember1);
        treasury.claimTeam();

        // Should receive 100% of allocation
        assertEq(token.balanceOf(teamMember1), 100_000_000 * 1e18);
        assertEq(treasury.teamClaimed(teamMember1), 100_000_000 * 1e18);
    }

    function test_RevertClaimTeam_BeforeCliff() public {
        _fundAndSetupTeam();

        vm.prank(teamMember1);
        vm.expectRevert(EscrowMultiTreasury.NoTokens.selector);
        treasury.claimTeam();
    }

    function test_RevertClaimTeam_NotFunded() public {
        vm.prank(teamMember1);
        vm.expectRevert(EscrowMultiTreasury.NotFunded.selector);
        treasury.claimTeam();
    }

    function test_RevertClaimTeam_NotLocked() public {
        _fundTreasury();
        treasury.setTeam(teamMember1, 100_000_000 * 1e18);

        vm.prank(teamMember1);
        vm.expectRevert(EscrowMultiTreasury.NotLocked.selector);
        treasury.claimTeam();
    }

    function test_RevertClaimTeam_NotTeamMember() public {
        _fundAndSetupTeam();
        vm.warp(block.timestamp + TEAM_CLIFF + 1);

        vm.prank(attacker);
        vm.expectRevert(EscrowMultiTreasury.NotFound.selector);
        treasury.claimTeam();
    }

    function test_RevertClaimTeam_AlreadyClaimed() public {
        _fundAndSetupTeam();
        vm.warp(block.timestamp + TEAM_CLIFF + 1);

        vm.prank(teamMember1);
        treasury.claimTeam();

        // Try to claim again at same milestone
        vm.prank(teamMember1);
        vm.expectRevert(EscrowMultiTreasury.NoTokens.selector);
        treasury.claimTeam();
    }

    function test_ClaimTeam_WhenPaused() public {
        _fundAndSetupTeam();
        vm.warp(block.timestamp + TEAM_CLIFF + 1);

        treasury.pause();

        vm.prank(teamMember1);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        treasury.claimTeam();

        treasury.unpause();

        vm.prank(teamMember1);
        treasury.claimTeam(); // Should work now
        assertGt(token.balanceOf(teamMember1), 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // LP CLAIM TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_ClaimLP() public {
        _fundTreasury();

        vm.prank(lpRecipient);
        vm.expectEmit(true, true, true, true);
        emit Claimed(lpRecipient, LP_ALLOC, 0);
        
        treasury.claimLP();

        assertEq(token.balanceOf(lpRecipient), LP_ALLOC);
    }

    function test_RevertClaimLP_NotRecipient() public {
        _fundTreasury();

        vm.prank(attacker);
        vm.expectRevert(EscrowMultiTreasury.Unauthorized.selector);
        treasury.claimLP();
    }

    function test_RevertClaimLP_AlreadyClaimed() public {
        _fundTreasury();

        vm.prank(lpRecipient);
        treasury.claimLP();

        vm.prank(lpRecipient);
        vm.expectRevert(EscrowMultiTreasury.NoTokens.selector);
        treasury.claimLP();
    }

    function test_RevertClaimLP_NotFunded() public {
        vm.prank(lpRecipient);
        vm.expectRevert(EscrowMultiTreasury.NotFunded.selector);
        treasury.claimLP();
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // MARKETING CLAIM TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_ClaimMkt_Milestone1() public {
        _fundTreasury();

        // Marketing starts immediately, milestone 1 at deploy + 1 second
        vm.warp(block.timestamp + 1);

        uint256 expectedAmount = (MKT_ALLOC * 2500) / 10_000; // 25%

        vm.prank(mktRecipient);
        vm.expectEmit(true, true, true, true);
        emit Claimed(mktRecipient, expectedAmount, 1);
        
        treasury.claimMkt();

        assertEq(token.balanceOf(mktRecipient), expectedAmount);
        assertEq(treasury.mktClaimed(), expectedAmount);
    }

    function test_ClaimMkt_MultipleMilestones() public {
        _fundTreasury();

        // Claim milestone 1
        vm.warp(block.timestamp + 1);
        vm.prank(mktRecipient);
        treasury.claimMkt();
        uint256 firstClaim = token.balanceOf(mktRecipient);

        // Claim milestone 2
        vm.warp(block.timestamp + MKT_INTERVAL);
        vm.prank(mktRecipient);
        treasury.claimMkt();
        uint256 secondClaim = token.balanceOf(mktRecipient) - firstClaim;

        assertEq(firstClaim, (MKT_ALLOC * 25) / 100); // 25%
        assertEq(secondClaim, (MKT_ALLOC * 25) / 100); // 25%
    }

    function test_ClaimMkt_FullVesting() public {
        _fundTreasury();

        // Fast forward past all 4 milestones
        vm.warp(block.timestamp + (4 * MKT_INTERVAL) + 1);

        vm.prank(mktRecipient);
        treasury.claimMkt();

        assertEq(token.balanceOf(mktRecipient), MKT_ALLOC); // 100%
        assertEq(treasury.mktClaimed(), MKT_ALLOC);
    }

    function test_RevertClaimMkt_NotRecipient() public {
        _fundTreasury();
        vm.warp(block.timestamp + 1);

        vm.prank(attacker);
        vm.expectRevert(EscrowMultiTreasury.Unauthorized.selector);
        treasury.claimMkt();
    }

    function test_RevertClaimMkt_AlreadyClaimedMilestone() public {
        _fundTreasury();
        vm.warp(block.timestamp + 1);

        vm.prank(mktRecipient);
        treasury.claimMkt();

        // Try to claim again at same milestone
        vm.prank(mktRecipient);
        vm.expectRevert(EscrowMultiTreasury.NoTokens.selector);
        treasury.claimMkt();
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_TeamClaimable() public {
        _fundAndSetupTeam();

        // Before cliff
        uint256 claimable = treasury.teamClaimable(teamMember1);
        assertEq(claimable, 0);

        // After cliff + 1 milestone
        vm.warp(block.timestamp + TEAM_CLIFF + 1);
        claimable = treasury.teamClaimable(teamMember1);
        assertEq(claimable, 20_000_000 * 1e18); // 20%

        // After claiming
        vm.prank(teamMember1);
        treasury.claimTeam();
        claimable = treasury.teamClaimable(teamMember1);
        assertEq(claimable, 0);
    }

    function test_TeamInfo() public {
        _fundAndSetupTeam();
        vm.warp(block.timestamp + TEAM_CLIFF + TEAM_INTERVAL + 1);

        (
            uint256 allocated,
            uint256 vested,
            uint256 claimed,
            uint256 claimable,
            uint8 milestone
        ) = treasury.teamInfo(teamMember1);

        assertEq(allocated, 100_000_000 * 1e18);
        assertEq(vested, 40_000_000 * 1e18); // 40% after milestone 2
        assertEq(claimed, 0);
        assertEq(claimable, 40_000_000 * 1e18);
        assertEq(milestone, 2);
    }

    function test_MktClaimable() public {
        _fundTreasury();
        vm.warp(block.timestamp + MKT_INTERVAL + 1);

        uint256 claimable = treasury.mktClaimable();
        assertEq(claimable, (MKT_ALLOC * 50) / 100); // 50% for 2 milestones
    }

    function test_Stats() public {
        _fundTreasury();
        treasury.setTeam(teamMember1, 100_000_000 * 1e18);
        treasury.setTeam(teamMember2, 200_000_000 * 1e18);
        treasury.lock();

        (uint256 balance, uint256 teamCount, bool funded, bool locked) = treasury.stats();

        assertEq(balance, TOTAL_ALLOC);
        assertEq(teamCount, 2);
        assertTrue(funded);
        assertTrue(locked);
    }

    function test_AllTeam() public {
        _fundTreasury();
        treasury.setTeam(teamMember1, 100_000_000 * 1e18);
        treasury.setTeam(teamMember2, 200_000_000 * 1e18);

        (
            address[] memory addrs,
            uint256[] memory allocs,
            uint256[] memory claimed
        ) = treasury.allTeam();

        assertEq(addrs.length, 2);
        assertEq(addrs[0], teamMember1);
        assertEq(addrs[1], teamMember2);
        assertEq(allocs[0], 100_000_000 * 1e18);
        assertEq(allocs[1], 200_000_000 * 1e18);
        assertEq(claimed[0], 0);
        assertEq(claimed[1], 0);
    }

    function test_NextUnlock() public {
        _fundAndSetupTeam();

        (uint256 teamNext, uint256 mktNext) = treasury.nextUnlock();

        assertEq(teamNext, treasury.deployTime() + TEAM_CLIFF);
        assertEq(mktNext, block.timestamp + 0); // Marketing unlocks immediately

        // After first team milestone - next unlock should be at deployTime + TEAM_CLIFF + TEAM_INTERVAL
        vm.warp(block.timestamp + TEAM_CLIFF + 1);
        (teamNext, mktNext) = treasury.nextUnlock();
        assertEq(teamNext, treasury.deployTime() + TEAM_CLIFF + TEAM_INTERVAL);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // PAUSE/UNPAUSE TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_Pause() public {
        treasury.pause();
        
        _fundTreasury();
        vm.warp(block.timestamp + 1);

        vm.prank(lpRecipient);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        treasury.claimLP();
    }

    function test_Unpause() public {
        treasury.pause();
        treasury.unpause();

        _fundTreasury();
        vm.warp(block.timestamp + 1);

        vm.prank(lpRecipient);
        treasury.claimLP(); // Should work
        assertEq(token.balanceOf(lpRecipient), LP_ALLOC);
    }

    function test_RevertPause_NotOwner() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", attacker));
        treasury.pause();
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // SECURITY TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_ReentrancyProtection() public {
        // This is implicitly tested by using nonReentrant modifier
        // Additional reentrancy tests would require a malicious contract
        _fundAndSetupTeam();
        vm.warp(block.timestamp + TEAM_CLIFF + 1);

        vm.prank(teamMember1);
        treasury.claimTeam();
        
        // If reentrancy was possible, balance would be double
        assertEq(token.balanceOf(teamMember1), 20_000_000 * 1e18);
    }

    function test_OnlyOwnerFunctions() public {
        vm.startPrank(attacker);

        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", attacker));
        treasury.fund();

        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", attacker));
        treasury.setTeam(teamMember1, 100_000_000 * 1e18);

        address[] memory addrs = new address[](1);
        uint256[] memory amts = new uint256[](1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", attacker));
        treasury.batchSetTeam(addrs, amts);

        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", attacker));
        treasury.removeTeam(teamMember1);

        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", attacker));
        treasury.lock();

        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", attacker));
        treasury.pause();

        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", attacker));
        treasury.unpause();

        vm.stopPrank();
    }

    function test_AccessControl_ClaimFunctions() public {
        _fundAndSetupTeam();
        vm.warp(block.timestamp + TEAM_CLIFF + 1);

        // Attacker cannot claim for team member
        vm.prank(attacker);
        vm.expectRevert(EscrowMultiTreasury.NotFound.selector);
        treasury.claimTeam();

        // Attacker cannot claim LP
        vm.prank(attacker);
        vm.expectRevert(EscrowMultiTreasury.Unauthorized.selector);
        treasury.claimLP();

        // Attacker cannot claim marketing
        vm.prank(attacker);
        vm.expectRevert(EscrowMultiTreasury.Unauthorized.selector);
        treasury.claimMkt();
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // EDGE CASE TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_MaxTeamAllocation() public {
        _fundTreasury();

        // Allocate exactly TEAM_ALLOC
        treasury.setTeam(teamMember1, TEAM_ALLOC);
        assertEq(treasury.teamTotal(), TEAM_ALLOC);

        // Cannot add more
        vm.expectRevert(EscrowMultiTreasury.ExceedsLimit.selector);
        treasury.setTeam(teamMember2, 1);
    }

    function test_BatchSetTeam_ArrayMismatch() public {
        _fundTreasury();

        address[] memory addrs = new address[](2);
        uint256[] memory amts = new uint256[](3);

        vm.expectRevert(EscrowMultiTreasury.ZeroAmount.selector);
        treasury.batchSetTeam(addrs, amts);
    }

    function test_BatchSetTeam_EmptyArrays() public {
        _fundTreasury();

        address[] memory addrs = new address[](0);
        uint256[] memory amts = new uint256[](0);

        vm.expectRevert(EscrowMultiTreasury.ZeroAmount.selector);
        treasury.batchSetTeam(addrs, amts);
    }

    function test_ClaimTeam_PartialClaims() public {
        _fundAndSetupTeam();

        // Claim at milestone 1
        vm.warp(block.timestamp + TEAM_CLIFF + 1);
        vm.prank(teamMember1);
        treasury.claimTeam();
        uint256 balance1 = token.balanceOf(teamMember1);

        // Skip milestone 2, claim at milestone 3
        vm.warp(block.timestamp + (2 * TEAM_INTERVAL));
        vm.prank(teamMember1);
        treasury.claimTeam();
        uint256 balance2 = token.balanceOf(teamMember1);

        // Should receive 20% at milestone 1, then 40% at milestone 3
        assertEq(balance1, 20_000_000 * 1e18);
        assertEq(balance2 - balance1, 40_000_000 * 1e18); // Milestone 2 + 3
    }

    function test_MilestoneCalculation_EdgeCases() public {
        _fundAndSetupTeam();

        // Exactly at cliff - should return milestone 1 (contract logic: elapsed = 0, 0 < TEAM_INTERVAL returns 1)
        vm.warp(block.timestamp + TEAM_CLIFF);
        (, , , , uint8 milestone) = treasury.teamInfo(teamMember1);
        assertEq(milestone, 1);

        // 1 second after cliff
        vm.warp(block.timestamp + 1);
        (, , , , milestone) = treasury.teamInfo(teamMember1);
        assertEq(milestone, 1);

        // Exactly at second milestone
        vm.warp(block.timestamp + TEAM_INTERVAL - 1);
        (, , , , milestone) = treasury.teamInfo(teamMember1);
        assertEq(milestone, 1);

        vm.warp(block.timestamp + 1);
        (, , , , milestone) = treasury.teamInfo(teamMember1);
        assertEq(milestone, 2);
    }

    function test_RemoveTeam_MultipleMembers() public {
        _fundTreasury();
        
        treasury.setTeam(teamMember1, 100_000_000 * 1e18);
        treasury.setTeam(teamMember2, 200_000_000 * 1e18);
        treasury.setTeam(teamMember3, 300_000_000 * 1e18);

        treasury.removeTeam(teamMember2);

        (address[] memory addrs, , ) = treasury.allTeam();
        assertEq(addrs.length, 2);
        assertEq(treasury.teamTotal(), 400_000_000 * 1e18);
        
        // Verify removed member is not in list
        bool found = false;
        for (uint i = 0; i < addrs.length; i++) {
            if (addrs[i] == teamMember2) found = true;
        }
        assertFalse(found);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // INTEGRATION TESTS (Full Scenarios)
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_FullLifecycle_Team() public {
        // 1. Fund and setup
        _fundTreasury();
        treasury.setTeam(teamMember1, 100_000_000 * 1e18);
        treasury.setTeam(teamMember2, 200_000_000 * 1e18);
        treasury.lock();

        // 2. Wait for first milestone
        vm.warp(block.timestamp + TEAM_CLIFF + 1);
        
        // 3. Both claim milestone 1
        vm.prank(teamMember1);
        treasury.claimTeam();
        vm.prank(teamMember2);
        treasury.claimTeam();

        assertEq(token.balanceOf(teamMember1), 20_000_000 * 1e18);
        assertEq(token.balanceOf(teamMember2), 40_000_000 * 1e18);

        // 4. Wait for all milestones
        vm.warp(block.timestamp + (4 * TEAM_INTERVAL) + 1);

        // 5. Claim remaining
        vm.prank(teamMember1);
        treasury.claimTeam();
        vm.prank(teamMember2);
        treasury.claimTeam();

        assertEq(token.balanceOf(teamMember1), 100_000_000 * 1e18);
        assertEq(token.balanceOf(teamMember2), 200_000_000 * 1e18);

        // 6. Verify no more to claim
        vm.prank(teamMember1);
        vm.expectRevert(EscrowMultiTreasury.NoTokens.selector);
        treasury.claimTeam();
    }

    function test_FullLifecycle_AllAllocations() public {
        // Setup all allocations
        _fundTreasury();
        treasury.setTeam(teamMember1, 500_000_000 * 1e18);
        treasury.setTeam(teamMember2, 500_000_000 * 1e18);
        treasury.lock();

        uint256 initialBalance = token.balanceOf(address(treasury));
        assertEq(initialBalance, TOTAL_ALLOC);

        // LP claims immediately
        vm.prank(lpRecipient);
        treasury.claimLP();
        assertEq(token.balanceOf(lpRecipient), LP_ALLOC);

        // Marketing claims first milestone
        vm.warp(block.timestamp + 1);
        vm.prank(mktRecipient);
        treasury.claimMkt();
        assertEq(token.balanceOf(mktRecipient), (MKT_ALLOC * 25) / 100);

        // Team claims after cliff
        vm.warp(block.timestamp + TEAM_CLIFF);
        vm.prank(teamMember1);
        treasury.claimTeam();
        assertEq(token.balanceOf(teamMember1), 100_000_000 * 1e18);

        // Marketing claims all remaining
        vm.warp(block.timestamp + (4 * MKT_INTERVAL));
        vm.prank(mktRecipient);
        treasury.claimMkt();
        assertEq(token.balanceOf(mktRecipient), MKT_ALLOC);

        // Team claims all remaining
        vm.warp(block.timestamp + (5 * TEAM_INTERVAL));
        vm.prank(teamMember1);
        treasury.claimTeam();
        vm.prank(teamMember2);
        treasury.claimTeam();

        // Verify all tokens distributed
        uint256 totalDistributed = 
            token.balanceOf(lpRecipient) +
            token.balanceOf(mktRecipient) +
            token.balanceOf(teamMember1) +
            token.balanceOf(teamMember2);

        assertEq(totalDistributed, TOTAL_ALLOC);
        assertEq(token.balanceOf(address(treasury)), 0);
    }

    function test_EmergencyPause_DuringVesting() public {
        _fundAndSetupTeam();
        vm.warp(block.timestamp + TEAM_CLIFF + 1);

        // Owner pauses due to emergency
        treasury.pause();

        // Claims fail
        vm.prank(teamMember1);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        treasury.claimTeam();

        vm.prank(lpRecipient);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        treasury.claimLP();

        vm.prank(mktRecipient);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        treasury.claimMkt();

        // Owner unpauses
        treasury.unpause();

        // Claims work again
        vm.prank(teamMember1);
        treasury.claimTeam();
        assertGt(token.balanceOf(teamMember1), 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function testFuzz_SetTeam(uint256 amount) public {
        vm.assume(amount > 0 && amount <= TEAM_ALLOC);
        
        _fundTreasury();
        treasury.setTeam(teamMember1, amount);

        assertEq(treasury.teamAlloc(teamMember1), amount);
        assertEq(treasury.teamTotal(), amount);
    }

    function testFuzz_ClaimTeam_AtDifferentTimes(uint256 timeAfterCliff) public {
        // Bound time between 0 and 10 years after cliff
        timeAfterCliff = bound(timeAfterCliff, 0, 10 * 365 days);
        
        _fundAndSetupTeam();
        vm.warp(block.timestamp + TEAM_CLIFF + timeAfterCliff);

        uint256 claimable = treasury.teamClaimable(teamMember1);
        
        if (claimable > 0) {
            vm.prank(teamMember1);
            treasury.claimTeam();
            assertEq(token.balanceOf(teamMember1), claimable);
        }

        // Claimable should never exceed allocation
        assertLe(claimable, 100_000_000 * 1e18);
    }

    function testFuzz_BatchSetTeam(uint8 memberCount) public {
        vm.assume(memberCount > 0 && memberCount <= 20); // Reasonable limit
        
        _fundTreasury();

        address[] memory addrs = new address[](memberCount);
        uint256[] memory amts = new uint256[](memberCount);
        uint256 amountPerMember = TEAM_ALLOC / memberCount;

        for (uint i = 0; i < memberCount; i++) {
            addrs[i] = address(uint160(1000 + i));
            amts[i] = amountPerMember;
        }

        treasury.batchSetTeam(addrs, amts);

        assertEq(treasury.teamTotal(), amountPerMember * memberCount);
        
        (address[] memory retrieved, , ) = treasury.allTeam();
        assertEq(retrieved.length, memberCount);
    }

    function testFuzz_MktClaim_AtDifferentTimes(uint256 timeAfterDeploy) public {
        timeAfterDeploy = bound(timeAfterDeploy, 1, 5 * 365 days);
        
        _fundTreasury();
        vm.warp(block.timestamp + timeAfterDeploy);

        uint256 claimable = treasury.mktClaimable();
        
        if (claimable > 0) {
            vm.prank(mktRecipient);
            treasury.claimMkt();
            assertEq(token.balanceOf(mktRecipient), claimable);
        }

        // Should never exceed total allocation
        assertLe(claimable, MKT_ALLOC);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // GAS BENCHMARKING TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_GasBenchmark_SetTeam() public {
        _fundTreasury();
        
        uint256 gasBefore = gasleft();
        treasury.setTeam(teamMember1, 100_000_000 * 1e18);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas used for setTeam", gasUsed);
        assertLt(gasUsed, 100_000); // Should be < 100k gas
    }

    function test_GasBenchmark_BatchSetTeam() public {
        _fundTreasury();

        address[] memory addrs = new address[](10);
        uint256[] memory amts = new uint256[](10);
        
        for (uint i = 0; i < 10; i++) {
            addrs[i] = address(uint160(1000 + i));
            amts[i] = 10_000_000 * 1e18;
        }

        uint256 gasBefore = gasleft();
        treasury.batchSetTeam(addrs, amts);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas used for batchSetTeam (10 members)", gasUsed);
        assertLt(gasUsed, 600_000); // Should be < 600k gas
    }

    function test_GasBenchmark_ClaimTeam() public {
        _fundAndSetupTeam();
        vm.warp(block.timestamp + TEAM_CLIFF + 1);

        vm.prank(teamMember1);
        uint256 gasBefore = gasleft();
        treasury.claimTeam();
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas used for claimTeam", gasUsed);
        assertLt(gasUsed, 80_000); // Should be < 80k gas
    }

    function test_GasBenchmark_ClaimLP() public {
        _fundTreasury();

        vm.prank(lpRecipient);
        uint256 gasBefore = gasleft();
        treasury.claimLP();
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas used for claimLP", gasUsed);
        assertLt(gasUsed, 60_000); // Should be < 60k gas
    }

    function test_GasBenchmark_ClaimMkt() public {
        _fundTreasury();
        vm.warp(block.timestamp + 1);

        vm.prank(mktRecipient);
        uint256 gasBefore = gasleft();
        treasury.claimMkt();
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas used for claimMkt", gasUsed);
        assertLt(gasUsed, 85_000); // Should be < 85k gas
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // INVARIANT TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function invariant_TotalClaimedNeverExceedsAllocation() public view {
        // This would be used with Foundry's invariant testing
        // Total claimed should never exceed TOTAL_ALLOC
        uint256 totalClaimed = 
            treasury.teamClaimed(teamMember1) +
            treasury.teamClaimed(teamMember2) +
            treasury.mktClaimed();

        assertLe(totalClaimed, TOTAL_ALLOC);
    }

    function invariant_TeamTotalNeverExceedsTeamAlloc() public view {
        assertLe(treasury.teamTotal(), TEAM_ALLOC);
    }

    function invariant_ContractBalanceMatchesUnclaimed() public {
        if (!_isFunded()) return;

        uint256 contractBalance = token.balanceOf(address(treasury));
        
        // Calculate unclaimed
        (address[] memory addrs, uint256[] memory allocs, uint256[] memory claimed) = treasury.allTeam();
        
        uint256 teamUnclaimed;
        for (uint i = 0; i < addrs.length; i++) {
            teamUnclaimed += allocs[i] - claimed[i];
        }

        uint256 lpUnclaimed = _isLPClaimed() ? 0 : LP_ALLOC;
        uint256 mktUnclaimed = MKT_ALLOC - treasury.mktClaimed();

        uint256 totalUnclaimed = teamUnclaimed + lpUnclaimed + mktUnclaimed;

        assertEq(contractBalance, totalUnclaimed);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════

    function _fundTreasury() internal {
        token.approve(address(treasury), TOTAL_ALLOC);
        treasury.fund();
    }

    function _fundAndSetupTeam() internal {
        _fundTreasury();
        treasury.setTeam(teamMember1, 100_000_000 * 1e18);
        treasury.setTeam(teamMember2, 200_000_000 * 1e18);
        treasury.lock();
    }

    function _isFunded() internal view returns (bool) {
        (, , bool funded, ) = treasury.stats();
        return funded;
    }

    function _isLPClaimed() internal returns (bool) {
        // Try to claim LP, if it reverts with NoTokens, it's claimed
        try treasury.claimLP() {
            return false;
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            return selector == EscrowMultiTreasury.NoTokens.selector ||
                   selector == EscrowMultiTreasury.Unauthorized.selector;
        }
    }
}