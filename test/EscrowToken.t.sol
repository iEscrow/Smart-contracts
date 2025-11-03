// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../EscrowToken.sol";

contract MockStakingContract {
    EscrowToken public token;
    
    constructor(address _token) {
        token = EscrowToken(_token);
    }
    
    function mintRewards(address to, uint256 amount) external {
        token.mintRewards(to, amount);
    }
}

contract EscrowTokenTest is Test {
    EscrowToken public token;
    MockStakingContract public stakingContract;
    
    address public owner;
    address public presaleContract = address(0x1);
    address public teamVestingContract = address(0x2);
    address public user = address(0x3);
    address public unauthorized = address(0x4);
    
    uint256 constant MARKETING_ALLOCATION = 3_400_000_000 * 1e18;
    uint256 constant LIQUIDITY_ALLOCATION = 5_000_000_000 * 1e18;
    uint256 constant PRESALE_ALLOCATION = 5_000_000_000 * 1e18;
    uint256 constant TEAM_VESTING_ALLOCATION = 1_000_000_000 * 1e18;
    
    function setUp() public {
        owner = address(this);
        token = new EscrowToken();
    }
    
    // ============ CONSTRUCTOR TESTS ============
    
    function testConstructorMintsInitialAllocations() public view {
        assertEq(token.balanceOf(token.MARKETING_WALLET()), MARKETING_ALLOCATION);
        assertEq(token.balanceOf(token.LIQUIDITY_WALLET()), LIQUIDITY_ALLOCATION);
        assertEq(token.totalMinted(), MARKETING_ALLOCATION + LIQUIDITY_ALLOCATION);
    }
    
    function testTokenMetadata() public view {
        assertEq(token.name(), "Escrow Token");
        assertEq(token.symbol(), "ESCROW");
        assertEq(token.decimals(), 18);
    }
    
    // ============ TEAM VESTING TESTS ============
    
    function testOwnerCanSetTeamVestingContractAndMint() public {
        token.setTeamVestingContractAndMint(teamVestingContract);
        
        assertEq(token.teamVestingContract(), teamVestingContract);
        assertEq(token.balanceOf(teamVestingContract), TEAM_VESTING_ALLOCATION);
        assertTrue(token.isTeamVestingAllocationMinted());
    }
    
    function testCannotSetTeamVestingContractTwice() public {
        token.setTeamVestingContractAndMint(teamVestingContract);
        
        vm.expectRevert("Team vesting contract already set");
        token.setTeamVestingContractAndMint(address(0x999));
    }
    
    function testCannotSetZeroAddressAsVestingContract() public {
        vm.expectRevert("Invalid vesting contract");
        token.setTeamVestingContractAndMint(address(0));
    }
    
    function testNonOwnerCannotSetVestingContract() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        token.setTeamVestingContractAndMint(teamVestingContract);
    }
    
    function testCanSetTeamVestingAfterBootstrap() public {
        // Bootstrap first
        stakingContract = new MockStakingContract(address(token));
        token.mintPresaleAllocation(presaleContract, address(stakingContract));
        
        // Should still be able to set team vesting after bootstrap
        token.setTeamVestingContractAndMint(teamVestingContract);
        
        assertEq(token.teamVestingContract(), teamVestingContract);
        assertEq(token.balanceOf(teamVestingContract), TEAM_VESTING_ALLOCATION);
    }
    
    // ============ PRESALE ALLOCATION TESTS ============
    
    function testOwnerCanMintPresaleAllocation() public {
        stakingContract = new MockStakingContract(address(token));
        token.mintPresaleAllocation(presaleContract, address(stakingContract));
        
        assertEq(token.balanceOf(presaleContract), PRESALE_ALLOCATION);
        assertTrue(token.isPresaleAllocationMinted());
        assertTrue(token.bootstrapComplete());
        assertEq(token.stakingContract(), address(stakingContract));
    }
    
    function testCannotMintPresaleAllocationTwice() public {
        stakingContract = new MockStakingContract(address(token));
        token.mintPresaleAllocation(presaleContract, address(stakingContract));
        
        vm.expectRevert("Bootstrap already completed");
        token.mintPresaleAllocation(presaleContract, address(stakingContract));
    }
    
    function testCannotMintPresaleWithZeroAddress() public {
        stakingContract = new MockStakingContract(address(token));
        
        vm.expectRevert("Invalid presale contract");
        token.mintPresaleAllocation(address(0), address(stakingContract));
        
        vm.expectRevert("Invalid staking contract");
        token.mintPresaleAllocation(presaleContract, address(0));
    }
    
    function testNonOwnerCannotMintPresale() public {
        stakingContract = new MockStakingContract(address(token));
        
        vm.prank(unauthorized);
        vm.expectRevert();
        token.mintPresaleAllocation(presaleContract, address(stakingContract));
    }
    
    // ============ BOOTSTRAP TESTS ============
    
    function testBootstrapCompletesImmediatelyAfterPresaleMint() public {
        assertFalse(token.bootstrapComplete());
        
        stakingContract = new MockStakingContract(address(token));
        token.mintPresaleAllocation(presaleContract, address(stakingContract));
        
        assertTrue(token.bootstrapComplete());
    }
    
    function testOwnerCannotMintPresaleAfterBootstrap() public {
        stakingContract = new MockStakingContract(address(token));
        token.mintPresaleAllocation(presaleContract, address(stakingContract));
        
        // Owner cannot mint presale twice
        vm.expectRevert("Bootstrap already completed");
        token.mintPresaleAllocation(presaleContract, address(stakingContract));
    }
    
    // ============ STAKING REWARDS TESTS ============
    
    function testStakingContractCanMintRewards() public {
        stakingContract = new MockStakingContract(address(token));
        token.mintPresaleAllocation(presaleContract, address(stakingContract));
        
        uint256 rewardAmount = 1000 * 1e18;
        stakingContract.mintRewards(user, rewardAmount);
        
        assertEq(token.balanceOf(user), rewardAmount);
    }
    
    function testCannotMintRewardsBeforeBootstrap() public {
        vm.expectRevert("Caller is not staking contract");
        token.mintRewards(user, 1000 * 1e18);
    }
    
    function testOnlyStakingContractCanMintRewards() public {
        stakingContract = new MockStakingContract(address(token));
        token.mintPresaleAllocation(presaleContract, address(stakingContract));
        
        vm.prank(unauthorized);
        vm.expectRevert("Caller is not staking contract");
        token.mintRewards(user, 1000 * 1e18);
    }
    
    function testOwnerCannotMintRewards() public {
        stakingContract = new MockStakingContract(address(token));
        token.mintPresaleAllocation(presaleContract, address(stakingContract));
        
        vm.expectRevert("Caller is not staking contract");
        token.mintRewards(user, 1000 * 1e18);
    }
    
    function testCannotMintRewardsWithZeroAmount() public {
        stakingContract = new MockStakingContract(address(token));
        token.mintPresaleAllocation(presaleContract, address(stakingContract));
        
        vm.expectRevert("Invalid amount");
        stakingContract.mintRewards(user, 0);
    }
    
    function testCannotMintRewardsToZeroAddress() public {
        stakingContract = new MockStakingContract(address(token));
        token.mintPresaleAllocation(presaleContract, address(stakingContract));
        
        vm.expectRevert("Invalid recipient");
        stakingContract.mintRewards(address(0), 1000 * 1e18);
    }
    
    function testCannotExceedMaxSupply() public {
        stakingContract = new MockStakingContract(address(token));
        token.mintPresaleAllocation(presaleContract, address(stakingContract));
        
        uint256 maxSupply = token.MAX_SUPPLY();
        uint256 remaining = maxSupply - token.totalMinted();
        
        // This should succeed
        stakingContract.mintRewards(user, remaining);
        assertEq(token.totalMinted(), maxSupply);
        
        // This should fail
        vm.expectRevert("Exceeds max supply");
        stakingContract.mintRewards(user, 1);
    }
    
    // ============ MINTING FINALIZATION TESTS ============
    
    function testOwnerCanFinalizeMinting() public {
        token.finalizeMinting();
        assertTrue(token.mintingFinalized());
    }
    
    function testCannotFinalizeMintingTwice() public {
        token.finalizeMinting();
        
        vm.expectRevert("Already finalized");
        token.finalizeMinting();
    }
    
    function testCannotMintRewardsAfterFinalization() public {
        stakingContract = new MockStakingContract(address(token));
        token.mintPresaleAllocation(presaleContract, address(stakingContract));
        token.finalizeMinting();
        
        vm.expectRevert("Minting finalized");
        stakingContract.mintRewards(user, 1000 * 1e18);
    }
    
    // ============ VIEW FUNCTION TESTS ============
    
    function testRemainingSupply() public {
        uint256 maxSupply = token.MAX_SUPPLY();
        uint256 expected = maxSupply - (MARKETING_ALLOCATION + LIQUIDITY_ALLOCATION);
        assertEq(token.remainingSupply(), expected);
    }
    
    function testCanMint() public {
        // Before bootstrap
        assertFalse(token.canMint(address(this)));
        assertFalse(token.canMint(unauthorized));
        
        // After bootstrap
        stakingContract = new MockStakingContract(address(token));
        token.mintPresaleAllocation(presaleContract, address(stakingContract));
        
        assertTrue(token.canMint(address(stakingContract)));
        assertFalse(token.canMint(address(this)));
        assertFalse(token.canMint(unauthorized));
        
        // After finalization
        token.finalizeMinting();
        assertFalse(token.canMint(address(stakingContract)));
    }
    
    function testGetTokenInfo() public view {
        (
            string memory name,
            string memory symbol,
            uint8 decimals,
            uint256 maxSupply,
            uint256 currentSupply,
            uint256 remainingMintable,
            bool mintingComplete
        ) = token.getTokenInfo();
        
        assertEq(name, "Escrow Token");
        assertEq(symbol, "ESCROW");
        assertEq(decimals, 18);
        assertEq(maxSupply, token.MAX_SUPPLY());
        assertEq(currentSupply, MARKETING_ALLOCATION + LIQUIDITY_ALLOCATION);
        assertEq(remainingMintable, token.MAX_SUPPLY() - token.totalMinted());
        assertFalse(mintingComplete);
    }
    
    // ============ INTEGRATION TESTS ============
    
    function testFullDeploymentFlow() public {
        // 1. Mint presale allocation (completes bootstrap)
        stakingContract = new MockStakingContract(address(token));
        token.mintPresaleAllocation(presaleContract, address(stakingContract));
        
        // 2. Set team vesting contract and mint (can be done after bootstrap)
        token.setTeamVestingContractAndMint(teamVestingContract);
        
        // 3. Verify all allocations
        assertEq(token.balanceOf(token.MARKETING_WALLET()), MARKETING_ALLOCATION);
        assertEq(token.balanceOf(token.LIQUIDITY_WALLET()), LIQUIDITY_ALLOCATION);
        assertEq(token.balanceOf(teamVestingContract), TEAM_VESTING_ALLOCATION);
        assertEq(token.balanceOf(presaleContract), PRESALE_ALLOCATION);
        
        uint256 expectedTotal = MARKETING_ALLOCATION + LIQUIDITY_ALLOCATION + 
                                TEAM_VESTING_ALLOCATION + PRESALE_ALLOCATION;
        assertEq(token.totalMinted(), expectedTotal);
        
        // 4. Staking can mint rewards
        stakingContract.mintRewards(user, 1000 * 1e18);
        assertEq(token.balanceOf(user), 1000 * 1e18);
        
        // 5. Owner cannot mint presale anymore
        assertTrue(token.bootstrapComplete());
    }
    
    function testMultipleRewardMints() public {
        stakingContract = new MockStakingContract(address(token));
        token.mintPresaleAllocation(presaleContract, address(stakingContract));
        
        address user1 = address(0x11);
        address user2 = address(0x22);
        
        stakingContract.mintRewards(user1, 500 * 1e18);
        stakingContract.mintRewards(user2, 750 * 1e18);
        stakingContract.mintRewards(user1, 250 * 1e18);
        
        assertEq(token.balanceOf(user1), 750 * 1e18);
        assertEq(token.balanceOf(user2), 750 * 1e18);
    }
    
    // ============ BURNABLE TESTS ============
    
    function testUserCanBurnTokens() public {
        stakingContract = new MockStakingContract(address(token));
        token.mintPresaleAllocation(presaleContract, address(stakingContract));
        
        uint256 amount = 1000 * 1e18;
        stakingContract.mintRewards(user, amount);
        
        vm.prank(user);
        token.burn(500 * 1e18);
        
        assertEq(token.balanceOf(user), 500 * 1e18);
    }
    
    // ============ EMERGENCY WITHDRAWAL TESTS ============
    
    function testEmergencyWithdrawETH() public {
        // Send ETH to token contract
        vm.deal(address(token), 1 ether);
        
        uint256 balanceBefore = address(this).balance;
        token.emergencyWithdrawETH(payable(address(this)));
        uint256 balanceAfter = address(this).balance;
        
        assertEq(balanceAfter - balanceBefore, 1 ether);
        assertEq(address(token).balance, 0);
    }
    
    receive() external payable {}
}
