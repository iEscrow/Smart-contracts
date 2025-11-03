// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../DevTreasury.sol";
import "../MultiTokenPresale.sol";
import "../EscrowToken.sol";
import "../Authorizer.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    uint8 private _decimals;
    
    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }
    
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract DevTreasuryTest is Test {
    DevTreasury public devTreasury;
    MultiTokenPresale public presale;
    EscrowToken public escrowToken;
    Authorizer public authorizer;
    MockERC20 public usdc;
    
    // Developer addresses (from contract)
    address public developer1 = 0x04435410a78192baAfa00c72C659aD3187a2C2cF; // Surya - 1.25%
    address public developer2 = 0x9005132849bC9585A948269D96F23f56e5981A61; // Bhom - 1.25%
    address public developer3 = 0x1C5cf9Cb69effeeb31E261BB6519AF7247A97A74; // Zala - 0.5%
    address public developer4 = 0x507541B0Caf529a063E97c6C145E521d3F394264; // Muhammad - 1%
    
    address public owner = 0xd81d23f2e37248F8fda5e7BF0a6c047AE234F0A2;
    address public buyer = address(0x999);
    address public staking = address(0x888);
    
    uint256 public signerPrivateKey = 0xB0B;
    address public signer = vm.addr(signerPrivateKey);
    
    uint256 constant PRESALE_RATE = 666666666666666667000;
    uint256 constant MAX_TOKENS = 5000000000 * 1e18;
    
    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy contracts
        escrowToken = new EscrowToken();
        authorizer = new Authorizer(signer, owner);
        
        // Deploy presale with devTreasury placeholder (we'll update it)
        presale = new MultiTokenPresale(
            address(escrowToken),
            PRESALE_RATE,
            MAX_TOKENS,
            address(0x1) // Temporary, will deploy real DevTreasury
        );
        
        // Deploy DevTreasury with presale address (addresses are hardcoded in contract)
        devTreasury = new DevTreasury(address(presale));
        
        // Set up presale
        escrowToken.mintPresaleAllocation(address(presale));
        presale.updateAuthorizer(address(authorizer));
        presale.setVoucherSystemEnabled(true);
        
        // Deploy mock USDC
        usdc = new MockERC20("USD Coin", "USDC", 6);
        presale.setTokenPrice(address(usdc), 1 * 1e8, 6, true);
        
        vm.stopPrank();
        
        // Give buyer funds
        vm.deal(buyer, 100 ether);
        usdc.mint(buyer, 100000 * 1e6);
    }
    
    function testCannotWithdrawBeforePresaleEnds() public {
        // Send some ETH to devTreasury
        vm.deal(address(devTreasury), 10 ether);
        
        // Try to withdraw before presale ends
        vm.expectRevert("Presale not ended");
        devTreasury.withdrawETH();
    }
    
    function testWithdrawETHAfterPresaleEnds() public {
        // Send ETH to devTreasury (simulating 4% fees)
        vm.deal(address(devTreasury), 10 ether);
        
        // Start and end presale
        vm.warp(1762819200 + 1);
        presale.autoStartIEscrowPresale();
        vm.warp(block.timestamp + 35 days);
        vm.prank(owner);
        presale.endEscrowPresale();
        
        // Record balances before
        uint256 dev1Before = developer1.balance;
        uint256 dev2Before = developer2.balance;
        uint256 dev3Before = developer3.balance;
        uint256 dev4Before = developer4.balance;
        
        // Anyone can call withdraw
        devTreasury.withdrawETH();
        
        // Check distributions (31.25%, 31.25%, 12.5%, 25%)
        assertEq(developer1.balance - dev1Before, 3.125 ether); // 31.25%
        assertEq(developer2.balance - dev2Before, 3.125 ether); // 31.25%
        assertEq(developer3.balance - dev3Before, 1.25 ether);  // 12.5%
        assertEq(developer4.balance - dev4Before, 2.5 ether);   // 25%
    }
    
    function testWithdrawTokenAfterPresaleEnds() public {
        // Send USDC to devTreasury
        uint256 amount = 10000 * 1e6; // 10,000 USDC
        usdc.mint(address(devTreasury), amount);
        
        // Start and end presale
        vm.warp(1762819200 + 1);
        presale.autoStartIEscrowPresale();
        vm.warp(block.timestamp + 35 days);
        vm.prank(owner);
        presale.endEscrowPresale();
        
        // Anyone can call withdraw
        devTreasury.withdrawToken(address(usdc));
        
        // Check distributions
        assertEq(usdc.balanceOf(developer1), 3125 * 1e6); // 31.25%
        assertEq(usdc.balanceOf(developer2), 3125 * 1e6); // 31.25%
        assertEq(usdc.balanceOf(developer3), 1250 * 1e6); // 12.5%
        assertEq(usdc.balanceOf(developer4), 2500 * 1e6); // 25%
    }
    
    function testCannotWithdrawTwice() public {
        // Send ETH to devTreasury
        vm.deal(address(devTreasury), 10 ether);
        
        // Start and end presale
        vm.warp(1762819200 + 1);
        presale.autoStartIEscrowPresale();
        vm.warp(block.timestamp + 35 days);
        vm.prank(owner);
        presale.endEscrowPresale();
        
        // First withdrawal should succeed
        devTreasury.withdrawETH();
        
        // Second withdrawal should fail
        vm.expectRevert("ETH already withdrawn");
        devTreasury.withdrawETH();
    }
    
    function testCannotWithdrawTokenTwice() public {
        // Send USDC to devTreasury
        usdc.mint(address(devTreasury), 10000 * 1e6);
        
        // Start and end presale
        vm.warp(1762819200 + 1);
        presale.autoStartIEscrowPresale();
        vm.warp(block.timestamp + 35 days);
        vm.prank(owner);
        presale.endEscrowPresale();
        
        // First withdrawal should succeed
        devTreasury.withdrawToken(address(usdc));
        
        // Second withdrawal should fail
        vm.expectRevert("Token already withdrawn");
        devTreasury.withdrawToken(address(usdc));
    }
    
    function testGetBalances() public {
        vm.deal(address(devTreasury), 5 ether);
        usdc.mint(address(devTreasury), 1000 * 1e6);
        
        assertEq(devTreasury.getETHBalance(), 5 ether);
        assertEq(devTreasury.getTokenBalance(address(usdc)), 1000 * 1e6);
    }
    
    function testGetShares() public view {
        (uint256 share1, uint256 share2, uint256 share3, uint256 share4) = devTreasury.getShares();
        
        assertEq(share1, 3125); // 31.25%
        assertEq(share2, 3125); // 31.25%
        assertEq(share3, 1250); // 12.5%
        assertEq(share4, 2500); // 25%
    }
    
    function testHardcodedAddresses() public view {
        assertEq(devTreasury.DEVELOPER1(), developer1);
        assertEq(devTreasury.DEVELOPER2(), developer2);
        assertEq(devTreasury.DEVELOPER3(), developer3);
        assertEq(devTreasury.DEVELOPER4(), developer4);
    }
    
    function testPresaleEndedCheck() public {
        // Before presale starts
        assertFalse(devTreasury.isPresaleEnded());
        
        // Start presale
        vm.warp(1762819200 + 1);
        presale.autoStartIEscrowPresale();
        assertFalse(devTreasury.isPresaleEnded());
        
        // End presale
        vm.warp(block.timestamp + 35 days);
        vm.prank(owner);
        presale.endEscrowPresale();
        assertTrue(devTreasury.isPresaleEnded());
    }
}
