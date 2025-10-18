// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../EscrowToken.sol";
import "../MultiTokenPresale.sol";
import "../SimpleKYC.sol";

contract EscrowTokenTest is Test {
    EscrowToken public escrowToken;
    MultiTokenPresale public presale;
    SimpleKYC public kyc;
    
    address public owner = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public presaleContract = address(0x3);
    address public stakingContract = address(0x4);
    
    // Token constants
    uint256 public constant MAX_SUPPLY = 100_000_000_000 * 1e18; // 100B
    uint256 public constant PRESALE_ALLOCATION = 5_000_000_000 * 1e18; // 5B
    
    function setUp() public {
        // Deploy EscrowToken
        escrowToken = new EscrowToken();
        
        // Deploy KYC contract
        kyc = new SimpleKYC(address(this)); // Use test contract as KYC signer
        
        console.log("EscrowToken deployed at:", address(escrowToken));
        console.log("Owner:", owner);
    }
    
    // Allow test contract to receive ETH
    receive() external payable {}
    
    // ============ BASIC TOKEN FUNCTIONALITY TESTS ============
    
    function test_TokenBasics() public view {
        assertEq(escrowToken.name(), "Escrow Token");
        assertEq(escrowToken.symbol(), "ESCROW");
        assertEq(escrowToken.decimals(), 18);
        assertEq(escrowToken.totalSupply(), 0); // Starts with 0 supply
        assertEq(escrowToken.MAX_SUPPLY(), MAX_SUPPLY);
        assertEq(escrowToken.PRESALE_ALLOCATION(), PRESALE_ALLOCATION);
    }
    
    function test_InitialState() public view {
        assertEq(escrowToken.totalMinted(), 0);
        assertFalse(escrowToken.mintingFinalized());
        assertFalse(escrowToken.presaleAllocationMinted());
        assertEq(escrowToken.remainingSupply(), MAX_SUPPLY);
    }
    
    // ============ PRESALE ALLOCATION TESTS ============
    
    function test_MintPresaleAllocation() public {
        // Should mint 5B tokens to presale contract
        escrowToken.mintPresaleAllocation(presaleContract);
        
        assertEq(escrowToken.balanceOf(presaleContract), PRESALE_ALLOCATION);
        assertEq(escrowToken.totalSupply(), PRESALE_ALLOCATION);
        assertEq(escrowToken.totalMinted(), PRESALE_ALLOCATION);
        assertTrue(escrowToken.presaleAllocationMinted());
        assertEq(escrowToken.remainingSupply(), MAX_SUPPLY - PRESALE_ALLOCATION);
    }
    
    function test_CannotMintPresaleAllocationTwice() public {
        escrowToken.mintPresaleAllocation(presaleContract);
        
        // Should revert on second attempt
        vm.expectRevert("Presale allocation already minted");
        escrowToken.mintPresaleAllocation(presaleContract);
    }
    
    function test_CannotMintPresaleAllocationToZeroAddress() public {
        vm.expectRevert("Invalid presale contract");
        escrowToken.mintPresaleAllocation(address(0));
    }
    
    function test_OnlyOwnerCanMintPresaleAllocation() public {
        vm.prank(user1);
        vm.expectRevert();
        escrowToken.mintPresaleAllocation(presaleContract);
    }
    
    // ============ REGULAR MINTING TESTS ============
    
    function test_OwnerCanMint() public {
        uint256 mintAmount = 1_000_000 * 1e18; // 1M tokens
        
        escrowToken.mint(user1, mintAmount);
        
        assertEq(escrowToken.balanceOf(user1), mintAmount);
        assertEq(escrowToken.totalSupply(), mintAmount);
        assertEq(escrowToken.totalMinted(), mintAmount);
    }
    
    function test_CannotMintToZeroAddress() public {
        vm.expectRevert("Invalid recipient");
        escrowToken.mint(address(0), 1000 * 1e18);
    }
    
    function test_CannotMintZeroAmount() public {
        vm.expectRevert("Invalid amount");
        escrowToken.mint(user1, 0);
    }
    
    function test_CannotExceedMaxSupply() public {
        // Try to mint more than max supply
        vm.expectRevert("Exceeds max supply");
        escrowToken.mint(user1, MAX_SUPPLY + 1);
    }
    
    function test_OnlyOwnerCanMint() public {
        vm.prank(user1);
        vm.expectRevert();
        escrowToken.mint(user1, 1000 * 1e18);
    }
    
    // ============ MINTER AUTHORIZATION TESTS ============
    
    function test_SetMinter() public {
        assertFalse(escrowToken.isMinter(stakingContract));
        assertFalse(escrowToken.canMint(stakingContract));
        
        escrowToken.setMinter(stakingContract, true);
        
        assertTrue(escrowToken.isMinter(stakingContract));
        assertTrue(escrowToken.canMint(stakingContract));
    }
    
    function test_AuthorizedMinterCanMint() public {
        uint256 mintAmount = 500_000 * 1e18;
        
        // Set staking contract as minter
        escrowToken.setMinter(stakingContract, true);
        
        // Minter can mint tokens
        vm.prank(stakingContract);
        escrowToken.minterMint(user1, mintAmount);
        
        assertEq(escrowToken.balanceOf(user1), mintAmount);
        assertEq(escrowToken.totalMinted(), mintAmount);
    }
    
    function test_UnauthorizedMinterCannotMint() public {
        vm.prank(stakingContract);
        vm.expectRevert("Not authorized minter");
        escrowToken.minterMint(user1, 1000 * 1e18);
    }
    
    function test_RevokeMinter() public {
        // Set minter
        escrowToken.setMinter(stakingContract, true);
        assertTrue(escrowToken.canMint(stakingContract));
        
        // Revoke minter
        escrowToken.setMinter(stakingContract, false);
        assertFalse(escrowToken.canMint(stakingContract));
        
        // Should not be able to mint anymore
        vm.prank(stakingContract);
        vm.expectRevert("Not authorized minter");
        escrowToken.minterMint(user1, 1000 * 1e18);
    }
    
    function test_OnlyOwnerCanSetMinter() public {
        vm.prank(user1);
        vm.expectRevert();
        escrowToken.setMinter(stakingContract, true);
    }
    
    // ============ MINTING FINALIZATION TESTS ============
    
    function test_FinalizeMinting() public {
        assertFalse(escrowToken.mintingFinalized());
        
        escrowToken.finalizeMinting();
        
        assertTrue(escrowToken.mintingFinalized());
    }
    
    function test_CannotMintAfterFinalization() public {
        escrowToken.finalizeMinting();
        
        vm.expectRevert("Minting finalized");
        escrowToken.mint(user1, 1000 * 1e18);
    }
    
    function test_CannotMintPresaleAfterFinalization() public {
        escrowToken.finalizeMinting();
        
        vm.expectRevert("Minting finalized");
        escrowToken.mintPresaleAllocation(presaleContract);
    }
    
    function test_MinterCannotMintAfterFinalization() public {
        escrowToken.setMinter(stakingContract, true);
        escrowToken.finalizeMinting();
        
        assertFalse(escrowToken.canMint(stakingContract)); // Should be false after finalization
        
        vm.prank(stakingContract);
        vm.expectRevert("Minting finalized");
        escrowToken.minterMint(user1, 1000 * 1e18);
    }
    
    function test_CannotFinalizeMintingTwice() public {
        escrowToken.finalizeMinting();
        
        vm.expectRevert("Already finalized");
        escrowToken.finalizeMinting();
    }
    
    // ============ INTEGRATION TESTS WITH PRESALE ============
    
    function test_IntegrationWithPresale() public {
        // Deploy presale contract with EscrowToken
        presale = new MultiTokenPresale(
            address(escrowToken),
            666666666666666666, // 0.0015 USD per token
            PRESALE_ALLOCATION,   // 5B tokens max
            address(kyc)
        );
        
        // Mint presale allocation to presale contract
        escrowToken.mintPresaleAllocation(address(presale));
        
        // Verify presale contract has the tokens
        assertEq(escrowToken.balanceOf(address(presale)), PRESALE_ALLOCATION);
        
        // Verify presale validation passes
        (bool hasTokens, bool startDate, bool limits, bool deposited, string memory issues) = 
            presale.validateIEscrowSetup();
        
        assertTrue(hasTokens);
        assertTrue(startDate);
        assertTrue(limits);
        assertTrue(deposited);
        assertEq(issues, "Setup validated - ready for launch");
    }
    
    // ============ ERC20 STANDARD COMPLIANCE TESTS ============
    
    function test_Transfer() public {
        uint256 amount = 1000 * 1e18;
        escrowToken.mint(user1, amount);
        
        vm.prank(user1);
        escrowToken.transfer(user2, amount / 2);
        
        assertEq(escrowToken.balanceOf(user1), amount / 2);
        assertEq(escrowToken.balanceOf(user2), amount / 2);
    }
    
    function test_Approve() public {
        uint256 amount = 1000 * 1e18;
        escrowToken.mint(user1, amount);
        
        vm.prank(user1);
        escrowToken.approve(user2, amount);
        
        assertEq(escrowToken.allowance(user1, user2), amount);
    }
    
    function test_TransferFrom() public {
        uint256 amount = 1000 * 1e18;
        escrowToken.mint(user1, amount);
        
        vm.prank(user1);
        escrowToken.approve(user2, amount);
        
        vm.prank(user2);
        escrowToken.transferFrom(user1, user2, amount);
        
        assertEq(escrowToken.balanceOf(user1), 0);
        assertEq(escrowToken.balanceOf(user2), amount);
    }
    
    function test_BurnTokens() public {
        uint256 amount = 1000 * 1e18;
        escrowToken.mint(user1, amount);
        
        vm.prank(user1);
        escrowToken.burn(amount / 2);
        
        assertEq(escrowToken.balanceOf(user1), amount / 2);
        assertEq(escrowToken.totalSupply(), amount / 2);
        // Note: totalMinted doesn't decrease on burn
        assertEq(escrowToken.totalMinted(), amount);
    }
    
    // ============ VIEW FUNCTIONS TESTS ============
    
    function test_GetTokenInfo() public {
        escrowToken.mint(user1, 1000 * 1e18);
        
        (
            string memory tokenName,
            string memory tokenSymbol,
            uint8 tokenDecimals,
            uint256 maxSupply,
            uint256 currentSupply,
            uint256 remainingMintable,
            bool mintingComplete
        ) = escrowToken.getTokenInfo();
        
        assertEq(tokenName, "Escrow Token");
        assertEq(tokenSymbol, "ESCROW");
        assertEq(tokenDecimals, 18);
        assertEq(maxSupply, MAX_SUPPLY);
        assertEq(currentSupply, 1000 * 1e18);
        assertEq(remainingMintable, MAX_SUPPLY - 1000 * 1e18);
        assertFalse(mintingComplete);
    }
    
    // ============ EMERGENCY FUNCTIONS TESTS ============
    
    function test_EmergencyWithdrawETH() public {
        // Send some ETH to token contract
        vm.deal(address(escrowToken), 1 ether);
        
        uint256 initialBalance = address(this).balance;
        escrowToken.emergencyWithdrawETH(payable(address(this)));
        
        assertEq(address(this).balance, initialBalance + 1 ether);
        assertEq(address(escrowToken).balance, 0);
    }
    
    function test_CannotEmergencyWithdrawEscrowTokens() public {
        vm.expectRevert("Cannot withdraw ESCROW tokens");
        escrowToken.emergencyWithdrawToken(address(escrowToken), owner, 1000);
    }
    
    // ============ COMPREHENSIVE SCENARIO TESTS ============
    
    function test_FullPresaleScenario() public {
        // 1. Deploy presale
        presale = new MultiTokenPresale(
            address(escrowToken),
            666666666666666666,
            PRESALE_ALLOCATION,
            address(kyc)
        );
        
        // 2. Mint presale allocation
        escrowToken.mintPresaleAllocation(address(presale));
        
        // 3. Set up KYC
        kyc.adminSetVerified(user1);
        
        // 4. Simulate time to presale start
        vm.warp(1762819200); // Nov 11, 2025
        
        // 5. Start presale
        presale.autoStartIEscrowPresale();
        
        // 6. User makes purchase
        vm.deal(user1, 10 ether);
        vm.prank(user1);
        presale.buyWithNative{value: 1 ether}(user1);
        
        // 7. Check purchase recorded
        assertGt(presale.totalPurchased(user1), 0);
        
        // 8. End presale
        vm.warp(1762819200 + 35 days);
        presale.checkAutoEndConditions();
        
        // 9. Claim tokens
        uint256 claimAmount = presale.totalPurchased(user1);
        vm.prank(user1);
        presale.claimTokens();
        
        // 10. Verify user received tokens
        assertEq(escrowToken.balanceOf(user1), claimAmount);
        assertTrue(presale.hasClaimed(user1));
        
        console.log("Full presale scenario completed successfully");
        console.log("User claimed tokens:", claimAmount / 1e18);
    }
    
    function test_StakingPreparation() public {
        // Test that token is ready for future staking integration
        
        // 1. Mint some tokens to users
        escrowToken.mint(user1, 10000 * 1e18);
        escrowToken.mint(user2, 5000 * 1e18);
        
        // 2. Set staking contract as minter
        escrowToken.setMinter(stakingContract, true);
        
        // 3. Test that staking contract can mint rewards
        vm.prank(stakingContract);
        escrowToken.minterMint(user1, 1000 * 1e18); // Simulate staking rewards
        
        assertEq(escrowToken.balanceOf(user1), 11000 * 1e18);
        
        // 4. Test that users can burn tokens (for staking)
        vm.prank(user1);
        escrowToken.burn(5000 * 1e18);
        
        assertEq(escrowToken.balanceOf(user1), 6000 * 1e18);
        
        console.log("Staking preparation tests passed");
    }
}