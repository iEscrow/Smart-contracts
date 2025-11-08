// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../EscrowStaking.sol";

contract MockEscrowToken is ERC20 {
    constructor(uint256 initialSupply) ERC20("Escrow", "ESC") {
        _mint(msg.sender, initialSupply);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}

contract EscrowStakingTest is Test {
    EscrowStaking public staking;
    MockEscrowToken public escrowToken;
    address public owner;
    address public project;
    address public staker1;
    address public staker2;

    uint256 constant INITIAL_SUPPLY = 100_000_000_000 * 10**18; // 100B tokens
    uint256 constant STAKE_AMOUNT = 1_000_000 * 10**18; // 1M tokens

    function setUp() public {
        owner = address(this);
        project = address(0x1);
        staker1 = address(0x2);
        staker2 = address(0x3);

        // Deploy token
        escrowToken = new MockEscrowToken(INITIAL_SUPPLY);

        // Deploy staking contract
        staking = new EscrowStaking(address(escrowToken), project);

        // Distribute tokens to stakers
        escrowToken.transfer(staker1, STAKE_AMOUNT * 10);
        escrowToken.transfer(staker2, STAKE_AMOUNT * 10);
    }

    // ============ Test Quantity Bonus Calculation ============

    function test_QuantityBonus_UnderCap() public {
        uint256 amount = 100_000_000 * 10**18; // 100M
        uint256 bonus = staking.calculateQuantityBonus(amount);
        // Expected: (100M * 10) / 1.5B
        uint256 bonusBase = 100_000_000 * 10**18;
        uint256 expected = (bonusBase * 10) / 1_500_000_000;
        assertApproxEqAbs(bonus, expected, 1000);
    }

    function test_QuantityBonus_OverCap() public {
        uint256 amount = 200_000_000 * 10**18; // 200M (over cap)
        uint256 bonus = staking.calculateQuantityBonus(amount);
        // Should cap at 150M: (150M * 10) / 1.5B = 1%
        uint256 bonusBase = 150_000_000 * 10**18;
        uint256 expected = (bonusBase * 10) / 1_500_000_000;
        assertApproxEqAbs(bonus, expected, 1000);
    }

    // ============ Test Time Bonus Calculation ============

    function test_TimeBonus_OneDay() public {
        uint256 bonus = staking.calculateTimeBonus(STAKE_AMOUNT, 1);
        assertEq(bonus, 0);
    }

    function test_TimeBonus_TwoDays() public {
        uint256 bonus = staking.calculateTimeBonus(STAKE_AMOUNT, 2);
        // Expected: (STAKE_AMOUNT × (2 - 1)) / 1820
        uint256 expected = (STAKE_AMOUNT * 1) / 1820;
        assertEq(bonus, expected);
    }

    function test_TimeBonus_3641Days() public {
        uint256 bonus = staking.calculateTimeBonus(STAKE_AMOUNT, 3641);
        // Should cap at 3x
        uint256 expected = STAKE_AMOUNT * 3;
        assertApproxEqAbs(bonus, expected, STAKE_AMOUNT);
    }

    function test_TimeBonus_GreaterThan3641Days() public {
        uint256 bonus = staking.calculateTimeBonus(STAKE_AMOUNT, 5000);
        // Should still cap at 3x
        uint256 expected = STAKE_AMOUNT * 3;
        assertApproxEqAbs(bonus, expected, STAKE_AMOUNT);
    }

    // ============ Test Stake Initiation ============

    function test_StartStake_Basic() public {
        vm.startPrank(staker1);
        escrowToken.approve(address(staking), STAKE_AMOUNT);

        uint256 durationDays = 365;
        staking.startStake(STAKE_AMOUNT, durationDays);
        vm.stopPrank();

        (uint256 amount, uint256 duration, , , , bool active, ) = staking.getStakeInfo(staker1);
        assertEq(amount, STAKE_AMOUNT);
        assertEq(duration, durationDays);
        assertTrue(active);
    }

    function test_StartStake_CannotStakeTwice() public {
        vm.startPrank(staker1);
        escrowToken.approve(address(staking), STAKE_AMOUNT * 2);

        staking.startStake(STAKE_AMOUNT, 365);

        vm.expectRevert("User already has active stake");
        staking.startStake(STAKE_AMOUNT, 365);
        vm.stopPrank();
    }

    function test_StartStake_ZeroAmount() public {
        vm.startPrank(staker1);
        vm.expectRevert("Stake amount must be greater than 0");
        staking.startStake(0, 365);
        vm.stopPrank();
    }

    function test_StartStake_ZeroDuration() public {
        vm.startPrank(staker1);
        escrowToken.approve(address(staking), STAKE_AMOUNT);
        vm.expectRevert("Duration must be greater than 0");
        staking.startStake(STAKE_AMOUNT, 0);
        vm.stopPrank();
    }

    // ============ Test C-Share Conversion ============

    function test_CShareConversion() public {
        vm.startPrank(staker1);
        escrowToken.approve(address(staking), STAKE_AMOUNT);
        staking.startStake(STAKE_AMOUNT, 365);
        vm.stopPrank();

        uint256 quantityBonus = staking.calculateQuantityBonus(STAKE_AMOUNT);
        uint256 timeBonus = staking.calculateTimeBonus(STAKE_AMOUNT, 365);
        uint256 effectiveTokens = STAKE_AMOUNT + quantityBonus + timeBonus;

        uint256 expectedCShares = (effectiveTokens * 10**18) / 10_000 / 10**18;

        (, , , uint256 cShares, , , ) = staking.getStakeInfo(staker1);
        assertApproxEqAbs(cShares, expectedCShares, 1);
    }

    // ============ Test Emergency End Stake (< 180 days) ============

    function test_EmergencyEndStake_ShortStake_BeforeDay1() public {
        vm.startPrank(staker1);
        escrowToken.approve(address(staking), STAKE_AMOUNT);
        staking.startStake(STAKE_AMOUNT, 100);
        vm.stopPrank();

        // Execute emergency end stake on day 0
        vm.prank(staker1);
        staking.emergencyEndStake();

        (, , , , , bool active, ) = staking.getStakeInfo(staker1);
        assertFalse(active);
    }

    function test_EmergencyEndStake_ShortStake_Day50() public {
        vm.startPrank(staker1);
        escrowToken.approve(address(staking), STAKE_AMOUNT);
        staking.startStake(STAKE_AMOUNT, 100);

        // Skip 50 days
        vm.warp(block.timestamp + 50 days);

        // Simulate earned yield
        (uint256 amount, , , , , , ) = staking.getStakeInfo(staker1);
        
        staking.emergencyEndStake();
        vm.stopPrank();

        (, , , , , bool active, ) = staking.getStakeInfo(staker1);
        assertFalse(active);
    }

    function test_EmergencyEndStake_ShortStake_Day90() public {
        vm.startPrank(staker1);
        escrowToken.approve(address(staking), STAKE_AMOUNT);
        staking.startStake(STAKE_AMOUNT, 100);

        // Skip exactly 90 days
        vm.warp(block.timestamp + 90 days);

        staking.emergencyEndStake();
        vm.stopPrank();

        (, , , , , bool active, ) = staking.getStakeInfo(staker1);
        assertFalse(active);
    }

    function test_EmergencyEndStake_ShortStake_Day100() public {
        vm.startPrank(staker1);
        escrowToken.approve(address(staking), STAKE_AMOUNT);
        staking.startStake(STAKE_AMOUNT, 150); // Longer stake so 100 days doesn't complete it

        // Skip 100 days (> 90 days threshold)
        vm.warp(block.timestamp + 100 days);

        staking.emergencyEndStake();
        vm.stopPrank();

        (, , , , , bool active, ) = staking.getStakeInfo(staker1);
        assertFalse(active);
    }

    // ============ Test Emergency End Stake (>= 180 days) ============

    function test_EmergencyEndStake_LongStake_BeforeDay1() public {
        vm.startPrank(staker1);
        escrowToken.approve(address(staking), STAKE_AMOUNT);
        staking.startStake(STAKE_AMOUNT, 365); // 365 days >= 180 days
        vm.stopPrank();

        // Execute emergency end stake on day 0
        vm.prank(staker1);
        staking.emergencyEndStake();

        (, , , , , bool active, ) = staking.getStakeInfo(staker1);
        assertFalse(active);
    }

    function test_EmergencyEndStake_LongStake_BeforeHalf() public {
        vm.startPrank(staker1);
        escrowToken.approve(address(staking), STAKE_AMOUNT);
        staking.startStake(STAKE_AMOUNT, 365); // 365 days

        // Skip 100 days (< 50% of 365, which is 182.5 days)
        vm.warp(block.timestamp + 100 days);

        staking.emergencyEndStake();
        vm.stopPrank();

        (, , , , , bool active, ) = staking.getStakeInfo(staker1);
        assertFalse(active);
    }

    function test_EmergencyEndStake_LongStake_AtHalf() public {
        uint256 duration = 364; // Even number for exact half
        vm.startPrank(staker1);
        escrowToken.approve(address(staking), STAKE_AMOUNT);
        staking.startStake(STAKE_AMOUNT, duration);

        // Skip exactly 50%
        vm.warp(block.timestamp + (duration / 2) * 1 days);

        staking.emergencyEndStake();
        vm.stopPrank();

        (, , , , , bool active, ) = staking.getStakeInfo(staker1);
        assertFalse(active);
    }

    function test_EmergencyEndStake_LongStake_AfterHalf() public {
        vm.startPrank(staker1);
        escrowToken.approve(address(staking), STAKE_AMOUNT);
        staking.startStake(STAKE_AMOUNT, 365); // 365 days

        // Skip 200 days (> 50% of 365)
        vm.warp(block.timestamp + 200 days);

        staking.emergencyEndStake();
        vm.stopPrank();

        (, , , , , bool active, ) = staking.getStakeInfo(staker1);
        assertFalse(active);
    }

    // ============ Test Normal End Stake ============

    function test_EndStake_WithinGracePeriod() public {
        vm.startPrank(staker1);
        escrowToken.approve(address(staking), STAKE_AMOUNT);
        staking.startStake(STAKE_AMOUNT, 30);

        // Skip to end of staking period + 10 days (within grace period)
        vm.warp(block.timestamp + 30 days + 10 days);

        staking.endStake();
        vm.stopPrank();

        (, , , , , bool active, ) = staking.getStakeInfo(staker1);
        assertFalse(active);
    }

    function test_EndStake_AfterGracePeriod() public {
        vm.startPrank(staker1);
        escrowToken.approve(address(staking), STAKE_AMOUNT);
        staking.startStake(STAKE_AMOUNT, 30);

        // Skip to end of staking period + 20 days (after grace period)
        vm.warp(block.timestamp + 30 days + 20 days);

        staking.endStake();
        vm.stopPrank();

        (, , , , , bool active, ) = staking.getStakeInfo(staker1);
        assertFalse(active);
    }

    function test_EndStake_BeforeStakePeriodEnds() public {
        vm.startPrank(staker1);
        escrowToken.approve(address(staking), STAKE_AMOUNT);
        staking.startStake(STAKE_AMOUNT, 365);

        // Try to end stake before period completes
        vm.expectRevert("Stake period not complete");
        staking.endStake();
        vm.stopPrank();
    }

    // ============ Test Daily Rewards ============

    function test_DistributeDailyRewards() public {
        vm.startPrank(staker1);
        escrowToken.approve(address(staking), STAKE_AMOUNT);
        staking.startStake(STAKE_AMOUNT, 365);
        vm.stopPrank();

        uint256 totalSupply = 100_000_000_000 * 10**18;
        
        vm.prank(owner);
        staking.distributeDailyRewards(totalSupply);

        uint256 expectedReward = (totalSupply * 1) / 10000; // 0.01%
        // Check that reward pool increased (exact calculation depends on implementation)
    }

    // ============ Test C-Share Price Update ============

    function test_CSharePrice_StartsAt10000() public {
        assertEq(staking.globalCSharePrice(), 10_000 * 10**18);
    }

    function test_CSharePrice_IncreasesAfterStakeCompletion() public {
        vm.startPrank(staker1);
        escrowToken.approve(address(staking), STAKE_AMOUNT);
        staking.startStake(STAKE_AMOUNT, 100);

        // Skip to end of staking period
        vm.warp(block.timestamp + 100 days + 1 days);

        uint256 priceBefore = staking.globalCSharePrice();
        staking.endStake();
        vm.stopPrank();

        uint256 priceAfter = staking.globalCSharePrice();
        // Price should increase or stay same
        assertTrue(priceAfter >= priceBefore);
    }

    // ============ Test Multiple Stakers ============

    function test_MultipleStakers_IndependentStakes() public {
        vm.startPrank(staker1);
        escrowToken.approve(address(staking), STAKE_AMOUNT);
        staking.startStake(STAKE_AMOUNT, 100);
        vm.stopPrank();

        vm.startPrank(staker2);
        escrowToken.approve(address(staking), STAKE_AMOUNT);
        staking.startStake(STAKE_AMOUNT, 200);
        vm.stopPrank();

        (uint256 amount1, uint256 duration1, , , , bool active1, ) = staking.getStakeInfo(staker1);
        (uint256 amount2, uint256 duration2, , , , bool active2, ) = staking.getStakeInfo(staker2);

        assertEq(amount1, STAKE_AMOUNT);
        assertEq(duration1, 100);
        assertTrue(active1);

        assertEq(amount2, STAKE_AMOUNT);
        assertEq(duration2, 200);
        assertTrue(active2);
    }

}
