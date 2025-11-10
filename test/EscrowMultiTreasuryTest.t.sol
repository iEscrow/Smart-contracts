// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../EscrowMultiTreasury.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockEscrowToken is ERC20 {
    constructor() ERC20("ESCROW", "ESC") {
        _mint(msg.sender, 100_000_000_000 * 1e18);
    }
}

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

    uint256 constant TOTAL_ALLOC = 9_400_000_000 * 1e18;
    uint256 constant TEAM_ALLOC = 1_000_000_000 * 1e18;
    uint256 constant LP_INITIAL = 2_500_000_000 * 1e18;
    uint256 constant LP_VESTED = 2_500_000_000 * 1e18;
    uint256 constant MKT_INITIAL = 1_400_000_000 * 1e18;
    uint256 constant MKT_PER_MILESTONE = 500_000_000 * 1e18;
    uint256 constant TEAM_CLIFF = 3 * 365 days;
    uint256 constant TEAM_INTERVAL = 180 days;
    uint256 constant LP_INTERVAL = 180 days;
    uint256 constant MKT_INTERVAL = 180 days;

    event Funded(uint256 amount);
    event TeamSet(address indexed beneficiary, uint256 amount);
    event TeamRemoved(address indexed beneficiary, uint256 amount);
    event Locked();
    event Claimed(address indexed recipient, uint256 amount, string category);

    function setUp() public {
        owner = address(this);
        lpRecipient = makeAddr("lpRecipient");
        mktRecipient = makeAddr("mktRecipient");
        teamMember1 = makeAddr("teamMember1");
        teamMember2 = makeAddr("teamMember2");
        teamMember3 = makeAddr("teamMember3");
        attacker = makeAddr("attacker");

        token = new MockEscrowToken();
        treasury = new EscrowMultiTreasury(address(token), lpRecipient, mktRecipient);
    }

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

    function test_Fund() public {
        token.approve(address(treasury), TOTAL_ALLOC);
        vm.expectEmit(true, true, true, true);
        emit Funded(TOTAL_ALLOC);
        treasury.fund();
        assertEq(token.balanceOf(address(treasury)), TOTAL_ALLOC);
    }

    function test_RevertFund_AlreadyFunded() public {
        token.approve(address(treasury), TOTAL_ALLOC);
        treasury.fund();
        token.approve(address(treasury), TOTAL_ALLOC);
        vm.expectRevert(EscrowMultiTreasury.AlreadyFunded.selector);
        treasury.fund();
    }

    function test_SetTeam() public {
        _fundTreasury();
        vm.expectEmit(true, true, true, true);
        emit TeamSet(teamMember1, 100_000_000 * 1e18);
        treasury.setTeam(teamMember1, 100_000_000 * 1e18);
        assertEq(treasury.teamAlloc(teamMember1), 100_000_000 * 1e18);
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
        assertEq(treasury.teamTotal(), 600_000_000 * 1e18);
    }

    function test_RevertSetTeam_ExceedsLimit() public {
        _fundTreasury();
        vm.expectRevert(EscrowMultiTreasury.ExceedsLimit.selector);
        treasury.setTeam(teamMember1, TEAM_ALLOC + 1);
    }

    function test_RemoveTeam() public {
        _fundTreasury();
        treasury.setTeam(teamMember1, 100_000_000 * 1e18);
        vm.expectEmit(true, true, true, true);
        emit TeamRemoved(teamMember1, 100_000_000 * 1e18);
        treasury.removeTeam(teamMember1);
        assertEq(treasury.teamAlloc(teamMember1), 0);
    }

    function test_Lock() public {
        _fundTreasury();
        treasury.setTeam(teamMember1, 100_000_000 * 1e18);
        vm.expectEmit(true, true, true, true);
        emit Locked();
        treasury.lock();
        (, , , bool locked) = treasury.stats();
        assertTrue(locked);
    }

    function test_ClaimTeam_AfterCliff() public {
        _fundAndSetupTeam();
        vm.warp(block.timestamp + TEAM_CLIFF + 1);
        uint256 expectedAmount = 20_000_000 * 1e18;
        vm.prank(teamMember1);
        treasury.claimTeam();
        assertEq(token.balanceOf(teamMember1), expectedAmount);
    }

    function test_ClaimTeam_FullVesting() public {
        _fundAndSetupTeam();
        vm.warp(block.timestamp + TEAM_CLIFF + (5 * TEAM_INTERVAL) + 1);
        vm.prank(teamMember1);
        treasury.claimTeam();
        assertEq(token.balanceOf(teamMember1), 100_000_000 * 1e18);
    }

    function test_RevertClaimTeam_BeforeCliff() public {
        _fundAndSetupTeam();
        vm.prank(teamMember1);
        vm.expectRevert(EscrowMultiTreasury.NoTokensAvailable.selector);
        treasury.claimTeam();
    }

    function test_ClaimLPInitial() public {
        _fundTreasury();
        vm.prank(lpRecipient);
        vm.expectEmit(true, true, true, true);
        emit Claimed(lpRecipient, LP_INITIAL, "LP-Initial");
        treasury.claimLPInitial();
        assertEq(token.balanceOf(lpRecipient), LP_INITIAL);
    }

    function test_ClaimLPVested() public {
        _fundTreasury();
        vm.warp(block.timestamp + LP_INTERVAL + 1);
        vm.prank(lpRecipient);
        vm.expectEmit(true, true, true, true);
        emit Claimed(lpRecipient, LP_VESTED, "LP-Vested");
        treasury.claimLPVested();
        assertEq(token.balanceOf(lpRecipient), LP_VESTED);
    }

    function test_RevertClaimLPVested_BeforeInterval() public {
        _fundTreasury();
        vm.prank(lpRecipient);
        vm.expectRevert(EscrowMultiTreasury.NoTokensAvailable.selector);
        treasury.claimLPVested();
    }

    function test_RevertClaimLP_NotRecipient() public {
        _fundTreasury();
        vm.prank(attacker);
        vm.expectRevert(EscrowMultiTreasury.Unauthorized.selector);
        treasury.claimLPInitial();
    }

    function test_RevertClaimLP_AlreadyClaimed() public {
        _fundTreasury();
        vm.prank(lpRecipient);
        treasury.claimLPInitial();
        vm.prank(lpRecipient);
        vm.expectRevert(EscrowMultiTreasury.NoTokensAvailable.selector);
        treasury.claimLPInitial();
    }

    function test_ClaimMktInitial() public {
        _fundTreasury();
        vm.prank(mktRecipient);
        vm.expectEmit(true, true, true, true);
        emit Claimed(mktRecipient, MKT_INITIAL, "Marketing-Initial");
        treasury.claimMktInitial();
        assertEq(token.balanceOf(mktRecipient), MKT_INITIAL);
    }

    function test_ClaimMktVested_FirstMilestone() public {
        _fundTreasury();
        vm.warp(block.timestamp + MKT_INTERVAL + 1);
        vm.prank(mktRecipient);
        treasury.claimMktVested();
        assertEq(token.balanceOf(mktRecipient), MKT_PER_MILESTONE);
    }

    function test_ClaimMktVested_AllMilestones() public {
        _fundTreasury();
        vm.warp(block.timestamp + (4 * MKT_INTERVAL) + 1);
        vm.prank(mktRecipient);
        treasury.claimMktVested();
        assertEq(token.balanceOf(mktRecipient), 4 * MKT_PER_MILESTONE);
    }

    function test_RevertClaimMkt_NotRecipient() public {
        _fundTreasury();
        vm.prank(attacker);
        vm.expectRevert(EscrowMultiTreasury.Unauthorized.selector);
        treasury.claimMktInitial();
    }

    function test_TeamInfo() public {
        _fundAndSetupTeam();
        vm.warp(block.timestamp + TEAM_CLIFF + TEAM_INTERVAL + 1);
        (uint256 allocated, uint256 vested, uint256 claimed, uint256 claimable, uint8 milestone) = treasury.teamInfo(teamMember1);
        assertEq(allocated, 100_000_000 * 1e18);
        assertEq(vested, 40_000_000 * 1e18);
        assertEq(claimed, 0);
        assertEq(claimable, 40_000_000 * 1e18);
        assertEq(milestone, 2);
    }

    function test_LPInfo() public {
        _fundTreasury();
        (uint256 initialAmount, uint256 vestedAmount, bool initialClaimed, bool vestedClaimed, bool vestedUnlocked) = treasury.lpInfo();
        assertEq(initialAmount, LP_INITIAL);
        assertEq(vestedAmount, LP_VESTED);
        assertFalse(initialClaimed);
        assertFalse(vestedClaimed);
        assertFalse(vestedUnlocked);
    }

    function test_MktInfo() public {
        _fundTreasury();
        vm.warp(block.timestamp + MKT_INTERVAL + 1);
        (uint256 initialAmount, uint256 perMilestone, uint256 totalClaimed, uint256 claimableNow, uint8 currentMilestone, uint8 lastClaimedMilestone, bool initialClaimed) = treasury.mktInfo();
        assertEq(initialAmount, MKT_INITIAL);
        assertEq(perMilestone, MKT_PER_MILESTONE);
        assertEq(totalClaimed, 0);
        assertEq(claimableNow, MKT_PER_MILESTONE);
        assertEq(currentMilestone, 1);
        assertEq(lastClaimedMilestone, 0);
        assertFalse(initialClaimed);
    }

    function test_Stats() public {
        _fundTreasury();
        treasury.setTeam(teamMember1, 100_000_000 * 1e18);
        treasury.lock();
        (uint256 balance, uint256 teamCount, bool funded, bool locked) = treasury.stats();
        assertEq(balance, TOTAL_ALLOC);
        assertEq(teamCount, 1);
        assertTrue(funded);
        assertTrue(locked);
    }

    function test_AllTeam() public {
        _fundTreasury();
        treasury.setTeam(teamMember1, 100_000_000 * 1e18);
        treasury.setTeam(teamMember2, 200_000_000 * 1e18);
        (address[] memory addrs, uint256[] memory allocs, uint256[] memory claimed) = treasury.allTeam();
        assertEq(addrs.length, 2);
        assertEq(allocs[0], 100_000_000 * 1e18);
        assertEq(allocs[1], 200_000_000 * 1e18);
        // Verify that newly set team members have 0 claimed tokens initially
        assertEq(claimed[0], 0);
        assertEq(claimed[1], 0);
    }

    function test_NextUnlock() public {
        _fundAndSetupTeam();
        (uint256 teamNext, uint256 lpNext, uint256 mktNext) = treasury.nextUnlock();
        assertEq(teamNext, treasury.deployTime() + TEAM_CLIFF);
        assertEq(lpNext, treasury.deployTime() + LP_INTERVAL);
        assertEq(mktNext, treasury.deployTime() + MKT_INTERVAL);
    }

    function test_Pause() public {
        treasury.pause();
        _fundTreasury();
        vm.prank(lpRecipient);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        treasury.claimLPInitial();
    }

    function test_Unpause() public {
        treasury.pause();
        treasury.unpause();
        _fundTreasury();
        vm.prank(lpRecipient);
        treasury.claimLPInitial();
        assertEq(token.balanceOf(lpRecipient), LP_INITIAL);
    }

   function test_FullLifecycle_AllAllocations() public {
    uint256 deployTime = block.timestamp;  // ✅ Store deploy time
    
    _fundTreasury();
    treasury.setTeam(teamMember1, 500_000_000 * 1e18);
    treasury.setTeam(teamMember2, 500_000_000 * 1e18);
    treasury.lock();

    // LP Initial (immediate)
    vm.prank(lpRecipient);
    treasury.claimLPInitial();

    // LP Vested (after 6 months from deploy)
    vm.warp(deployTime + LP_INTERVAL + 1);  // ✅ Absolute time
    vm.prank(lpRecipient);
    treasury.claimLPVested();

    // Marketing Initial (immediate)
    vm.prank(mktRecipient);
    treasury.claimMktInitial();

    // Marketing Vested (after 24 months from deploy)
    vm.warp(deployTime + (4 * MKT_INTERVAL) + 1);  // ✅ Absolute time
    vm.prank(mktRecipient);
    treasury.claimMktVested();

    // Team First Claim (after 3 years from deploy)
    vm.warp(deployTime + TEAM_CLIFF + 1);  // ✅ Absolute time
    vm.prank(teamMember1);
    treasury.claimTeam();

    // Team Full Vesting (after 3 years + 30 months from deploy)
    vm.warp(deployTime + TEAM_CLIFF + (5 * TEAM_INTERVAL) + 1);  // ✅ Absolute time
    vm.prank(teamMember1);
    treasury.claimTeam();
    vm.prank(teamMember2);
    treasury.claimTeam();

    uint256 totalDistributed = token.balanceOf(lpRecipient) + 
                               token.balanceOf(mktRecipient) + 
                               token.balanceOf(teamMember1) + 
                               token.balanceOf(teamMember2);
    assertEq(totalDistributed, TOTAL_ALLOC);
}

    function test_OnlyOwnerFunctions() public {
        vm.startPrank(attacker);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", attacker));
        treasury.fund();
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", attacker));
        treasury.setTeam(teamMember1, 100_000_000 * 1e18);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", attacker));
        treasury.lock();
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", attacker));
        treasury.pause();
        vm.stopPrank();
    }

    function testFuzz_SetTeam(uint256 amount) public {
        vm.assume(amount > 0 && amount <= TEAM_ALLOC);
        _fundTreasury();
        treasury.setTeam(teamMember1, amount);
        assertEq(treasury.teamAlloc(teamMember1), amount);
    }

    function testFuzz_ClaimTeam_AtDifferentTimes(uint256 timeAfterCliff) public {
        timeAfterCliff = bound(timeAfterCliff, 0, 10 * 365 days);
        _fundAndSetupTeam();
        vm.warp(block.timestamp + TEAM_CLIFF + timeAfterCliff);
        uint256 claimable = treasury.teamClaimable(teamMember1);
        if (claimable > 0) {
            vm.prank(teamMember1);
            treasury.claimTeam();
            assertEq(token.balanceOf(teamMember1), claimable);
        }
        assertLe(claimable, 100_000_000 * 1e18);
    }

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
}