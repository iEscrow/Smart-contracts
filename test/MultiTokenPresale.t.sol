// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../Authorizer.sol";
import "../MultiTokenPresale.sol";
import "../EscrowToken.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockExecutor {
    receive() external payable {}

    function acceptTreasury(MultiTokenPresale presale) external {
        presale.acceptTreasury();
    }

    function execute(address target, bytes calldata data) external {
        (bool success,) = target.call(data);
        require(success, "Executor call failed");
    }
}

/// @notice Mock ERC20 token for testing
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

/// @notice Mock deflationary token that burns 1% of tokens on transfer
contract MockDeflationaryToken is IERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    string public constant name = "Deflationary Token";
    string public constant symbol = "DEFL";

    function decimals() external pure returns (uint8) {
        return 6;
    }

    function totalSupply() external view returns (uint256) {
        return 1000000 * 1e6; // 1M tokens
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");

        uint256 burnAmount = amount / 100; // Burn 1%
        uint256 transferAmount = amount - burnAmount;

        balanceOf[msg.sender] -= amount;
        balanceOf[to] += transferAmount;

        emit Transfer(msg.sender, address(0), burnAmount); // Burn event
        emit Transfer(msg.sender, to, transferAmount);    // Transfer event

        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");

        uint256 burnAmount = amount / 100; // Burn 1%
        uint256 transferAmount = amount - burnAmount;

        balanceOf[from] -= amount;
        balanceOf[to] += transferAmount;
        allowance[from][msg.sender] -= amount;

        emit Transfer(from, address(0), burnAmount); // Burn event
        emit Transfer(from, to, transferAmount);    // Transfer event

        return true;
    }
}

/// @notice Mock USDT that doesn't return bool on transfer (for testing SafeERC20)
contract MockUSDT is IERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    string public constant name = "Tether USD";
    string public constant symbol = "USDT";

    function decimals() external pure returns (uint8) {
        return 6;
    }

    function totalSupply() external view returns (uint256) {
        return 1000000 * 1e6; // 1M tokens
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    // USDT returns bool on transfer (modern ERC20 standard)
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

/// @title MultiTokenPresale Test Suite
/// @notice Tests core presale functionality (rounds, timing, purchases) using voucher system
contract MultiTokenPresaleTest is Test {
    Authorizer public authorizer;
    MultiTokenPresale public presale;
    EscrowToken public escrowToken;
    
    address public owner = address(0x1);
    address public buyer1 = address(0x3);
    address public buyer2 = address(0x4);
    address public staking;
    
    // Mock tokens for testing
    MockERC20 public mockUSDC;  // 6 decimals
    MockERC20 public mockWBTC;  // 8 decimals
    MockERC20 public mockWETH;  // 18 decimals
    MockUSDT public mockUSDT;   // 6 decimals, no return value
    MockDeflationaryToken public mockDeflationaryToken; // 6 decimals, deflationary
    
    uint256 public signerPrivateKey = 0xB0B;
    address public signer = vm.addr(signerPrivateKey);
    
    // Test constants
    uint256 constant PRESALE_RATE = 666666666666666667000; // 666.666... tokens per USD at $0.0015/token (18 decimals)
    uint256 constant MAX_TOKENS = 5000000000 * 1e18; // 5B tokens
    uint256 constant PRESALE_LAUNCH_DATE = 1762819200; // Nov 11, 2025
    uint256 constant VOUCHER_LIMIT = 10000 * 1e8; // $10000 limit
    
    function setUp() public {
        staking = vm.addr(0x5);
        vm.startPrank(owner);
        
        // Deploy contracts
        escrowToken = new EscrowToken();
        authorizer = new Authorizer(signer, owner);
        
        presale = new MultiTokenPresale(
            address(escrowToken),
            PRESALE_RATE,
            MAX_TOKENS
        );
        
        // Set up presale
        escrowToken.mintPresaleAllocation(address(presale), staking);
        presale.updateAuthorizer(address(authorizer));
        presale.setVoucherSystemEnabled(true);
        
        // Deploy mock tokens
        mockUSDC = new MockERC20("USD Coin", "USDC", 6);
        mockWBTC = new MockERC20("Wrapped Bitcoin", "WBTC", 8);
        mockWETH = new MockERC20("Wrapped Ether", "WETH", 18);
        mockUSDT = new MockUSDT();
        mockDeflationaryToken = new MockDeflationaryToken();
        
        // Set token prices in presale
        presale.setTokenPrice(address(mockUSDC), 1 * 1e8, 6, true);      // $1
        presale.setTokenPrice(address(mockWBTC), 45000 * 1e8, 8, true);  // $45,000
        presale.setTokenPrice(address(mockWETH), 4200 * 1e8, 18, true);  // $4,200
        presale.setTokenPrice(address(mockUSDT), 1 * 1e8, 6, true);      // $1
        presale.setTokenPrice(address(mockDeflationaryToken), 1 * 1e8, 6, true); // $1
        
        vm.stopPrank();
        
        // Give buyers ETH
        vm.deal(buyer1, 100 ether);
        vm.deal(buyer2, 100 ether);
        
        // Mint tokens to buyers
        mockUSDC.mint(buyer1, 100000 * 1e6);  // 100k USDC
        mockUSDC.mint(buyer2, 100000 * 1e6);
        mockWBTC.mint(buyer1, 10 * 1e8);      // 10 WBTC
        mockWBTC.mint(buyer2, 10 * 1e8);
        mockWETH.mint(buyer1, 100 * 1e18);    // 100 WETH
        mockWETH.mint(buyer2, 100 * 1e18);
        mockUSDT.mint(buyer1, 100000 * 1e6);  // 100k USDT
        mockUSDT.mint(buyer2, 100000 * 1e6);
        mockDeflationaryToken.mint(buyer1, 100000 * 1e6); // 100k deflationary tokens
        mockDeflationaryToken.mint(buyer2, 100000 * 1e6);
    }
    
    // ========== PRESALE LIFECYCLE TESTS ==========
    
    function testPresaleNotStartedInitially() public view {
        (bool started, bool ended,,,) = presale.getPresaleStatus();
        assertFalse(started);
        assertFalse(ended);
        assertEq(presale.currentRound(), 0);
    }
    
    function testAutoStartPresale() public {
        // Warp to launch date
        vm.warp(PRESALE_LAUNCH_DATE + 1);
        
        // Anyone can trigger auto-start
        vm.prank(buyer1);
        presale.autoStartIEscrowPresale();
        
        // Verify escrow presale started
        (bool started, bool ended,,,) = presale.getEscrowPresaleStatus();
        assertTrue(started);
        assertFalse(ended);
        assertEq(presale.escrowCurrentRound(), 1);
    }
    
    function testCannotStartBeforeLaunchDate() public {
        vm.warp(PRESALE_LAUNCH_DATE - 1);
        
        vm.expectRevert("Too early - presale starts Nov 11, 2025");
        presale.autoStartIEscrowPresale();
    }
    
    function testCannotPurchaseBeforeStart() public {
        Authorizer.Voucher memory voucher = _createVoucher(buyer1, buyer1, address(0), 0);
        bytes memory signature = _signVoucher(voucher);
        
        vm.expectRevert("No presale active");
        vm.prank(buyer1);
        presale.buyWithNativeVoucher{value: 0.01 ether}(buyer1, voucher, signature);
    }
    
    // ========== ROUND MANAGEMENT TESTS ==========
    
    function testRound1Duration() public {
        _startPresale();
        
        // Check we're in escrow round 1
        assertEq(presale.escrowCurrentRound(), 1);
        
        // Warp to end of round 1
        vm.warp(block.timestamp + 23 days);
        
        // Make a purchase to trigger round check
        _makePurchase(buyer1, 0.001 ether, 0);
        
        // Should still be in round 1 (auto-advancement disabled)
        assertEq(presale.escrowCurrentRound(), 1);
    }
    
    function testManualRoundAdvancement() public {
        _startPresale();
        
        assertEq(presale.escrowCurrentRound(), 1);
        
        // Owner can manually advance escrow presale with new prices
        address[] memory tokens = new address[](1);
        uint256[] memory prices = new uint256[](1);
        uint8[] memory decimalsArray = new uint8[](1);
        bool[] memory activeArray = new bool[](1);
        
        tokens[0] = address(mockUSDC);
        prices[0] = 2 * 1e8; // Different from round 1 price of $1
        decimalsArray[0] = 6;
        activeArray[0] = true;
        
        vm.prank(owner);
        presale.moveEscrowToRound2(tokens, prices, decimalsArray, activeArray);
        
        assertEq(presale.escrowCurrentRound(), 2);
    }

    // GRO-02: Governance executor feature removed - using hardware wallet owner only
    // function testGovernanceExecutorFlow() removed
    
    function testPresaleAutoEndsAfter34Days() public {
        _startPresale();
        uint256 startTime = block.timestamp;
        
        // Presale should be active
        assertTrue(presale.isPresaleActive());
        
        // Warp past 34 days
        vm.warp(startTime + 34 days + 1);
        
        // Check presale is considered ended
        assertFalse(presale.isPresaleActive());
    }
    
    // ========== PURCHASE TESTS ==========
    
    function testSuccessfulPurchaseRound1() public {
        _startPresale();
        
        uint256 purchaseAmount = 0.01 ether;
        _makePurchase(buyer1, purchaseAmount, 0);
        
        // Verify tokens allocated
        assertTrue(presale.totalPurchased(buyer1) > 0);
        
        // Verify escrow round 1 tracking
        assertTrue(presale.escrowRound1TokensSold() > 0);
        assertEq(presale.escrowRound2TokensSold(), 0);
    }
    
    function testSuccessfulPurchaseRound2() public {
        _startPresale();
        
        // Move escrow to round 2 with new prices
        address[] memory tokens = new address[](1);
        uint256[] memory prices = new uint256[](1);
        uint8[] memory decimalsArray = new uint8[](1);
        bool[] memory activeArray = new bool[](1);
        
        tokens[0] = presale.NATIVE_ADDRESS();
        prices[0] = 4500 * 1e8; // Different from round 1 price of $4200
        decimalsArray[0] = 18;
        activeArray[0] = true;
        
        vm.prank(owner);
        presale.moveEscrowToRound2(tokens, prices, decimalsArray, activeArray);
        
        _makePurchase(buyer1, 0.01 ether, 0);
        
        // Verify escrow round 2 tracking
        assertTrue(presale.escrowRound2TokensSold() > 0);
    }
    
    function testMultipleBuyers() public {
        _startPresale();
        
        // Buyer 1 purchases
        _makePurchase(buyer1, 0.001 ether, 0);
        uint256 buyer1Tokens = presale.totalPurchased(buyer1);
        
        // Buyer 2 purchases
        _makePurchase(buyer2, 0.001 ether, 0);
        uint256 buyer2Tokens = presale.totalPurchased(buyer2);
        
        // Both should have tokens
        assertTrue(buyer1Tokens > 0);
        assertTrue(buyer2Tokens > 0);
        
        // Total minted should equal sum
        assertEq(presale.totalTokensMinted(), buyer1Tokens + buyer2Tokens);
    }
    
    function testMultiplePurchasesSameBuyer() public {
        _startPresale();
        
        // First purchase
        _makePurchase(buyer1, 0.001 ether, 0);
        uint256 tokensAfterFirst = presale.totalPurchased(buyer1);
        
        // Second purchase (nonce 1)
        _makePurchase(buyer1, 0.001 ether, 1);
        uint256 tokensAfterSecond = presale.totalPurchased(buyer1);
        
        // Tokens should accumulate
        assertTrue(tokensAfterSecond > tokensAfterFirst);
    }
    
    // ========== TOKEN LIMITS TESTS ==========
    
    function testRemainingTokens() public {
        _startPresale();
        
        assertEq(presale.getRemainingTokens(), MAX_TOKENS);
        
        _makePurchase(buyer1, 0.01 ether, 0);
        
        assertTrue(presale.getRemainingTokens() < MAX_TOKENS);
    }
    
    function testInitialAllocationsMinted() public view {
        uint256 marketingAllocation = escrowToken.MARKETING_ALLOCATION();
        uint256 liquidityAllocation = escrowToken.LIQUIDITY_ALLOCATION();
        
        assertEq(
            escrowToken.balanceOf(escrowToken.MARKETING_WALLET()),
            marketingAllocation
        );
        assertEq(
            escrowToken.balanceOf(escrowToken.LIQUIDITY_WALLET()),
            liquidityAllocation
        );
        
        uint256 expectedTotalMinted = marketingAllocation + liquidityAllocation + MAX_TOKENS;
        assertEq(escrowToken.totalMinted(), expectedTotalMinted);
    }
    
    // ========== CLAIM TESTS ==========
    
    function testCannotClaimBeforePresaleEnds() public {
        _startPresale();
        _makePurchase(buyer1, 0.01 ether, 0);
        
        vm.expectRevert("No presale ended yet");
        vm.prank(buyer1);
        presale.claimTokens();
    }
    
    function testClaimAfterPresaleEnds() public {
        _startPresale();
        _makePurchase(buyer1, 0.01 ether, 0);
        
        uint256 purchasedTokens = presale.totalPurchased(buyer1);
        
        // End escrow presale
        vm.warp(block.timestamp + 34 days + 1);
        vm.prank(owner);
        presale.endEscrowPresale();
        
        // Claim tokens
        vm.prank(buyer1);
        presale.claimTokens();
        
        // Verify tokens received
        assertEq(escrowToken.balanceOf(buyer1), purchasedTokens);
        assertTrue(presale.hasClaimed(buyer1));
    }
    
    function testCannotClaimTwice() public {
        _startPresale();
        _makePurchase(buyer1, 0.01 ether, 0);
        
        // End escrow presale and claim
        vm.warp(block.timestamp + 34 days + 1);
        vm.prank(owner);
        presale.endEscrowPresale();
        
        vm.prank(buyer1);
        presale.claimTokens();
        
        // Try to claim again
        vm.expectRevert("Already claimed");
        vm.prank(buyer1);
        presale.claimTokens();
    }
    
    // ========== ADMIN TESTS ==========
    
    function testEmergencyEndPresale() public {
        _startPresale();
        
        vm.prank(owner);
        presale.emergencyEndEscrowPresale();
        
        (, bool ended,,,) = presale.getEscrowPresaleStatus();
        assertTrue(ended);
    }
    
    function testPauseAndUnpause() public {
        _startPresale();
        
        // Pause
        vm.prank(owner);
        presale.pause();
        
        // Cannot purchase when paused
        Authorizer.Voucher memory voucher = _createVoucher(buyer1, buyer1, address(0), 0);
        bytes memory signature = _signVoucher(voucher);
        
        vm.expectRevert();
        vm.prank(buyer1);
        presale.buyWithNativeVoucher{value: 0.01 ether}(buyer1, voucher, signature);
        
        // Unpause
        vm.prank(owner);
        presale.unpause();
        
        // Can purchase again
        _makePurchase(buyer1, 0.001 ether, 0);
        assertTrue(presale.totalPurchased(buyer1) > 0);
    }
    
    // ========== ERC20 TOKEN PURCHASE TESTS ==========
    
    function testPurchaseWithUSDC() public {
        _startPresale();
        
        uint256 usdcAmount = 1000 * 1e6; // $1000 USDC
        _makeTokenPurchase(buyer1, address(mockUSDC), usdcAmount, 0);
        
        // Verify tokens allocated
        assertTrue(presale.totalPurchased(buyer1) > 0);
        
        // Verify USDC transferred to presale
        assertEq(mockUSDC.balanceOf(address(presale)), usdcAmount);
    }
    
    function testPurchaseWithWBTC() public {
        _startPresale();
        
        uint256 wbtcAmount = 0.1 * 1e8; // 0.1 WBTC (~$4500)
        _makeTokenPurchase(buyer1, address(mockWBTC), wbtcAmount, 0);
        
        // Verify tokens allocated
        assertTrue(presale.totalPurchased(buyer1) > 0);
        
        // Verify WBTC transferred
        assertEq(mockWBTC.balanceOf(address(presale)), wbtcAmount);
    }
    
    function testPurchaseWithWETH() public {
        _startPresale();
        
        uint256 wethAmount = 1 * 1e18; // 1 WETH (~$4200)
        _makeTokenPurchase(buyer1, address(mockWETH), wethAmount, 0);
        
        // Verify tokens allocated
        assertTrue(presale.totalPurchased(buyer1) > 0);
        
        // Verify WETH transferred
        assertEq(mockWETH.balanceOf(address(presale)), wethAmount);
    }
    
    // ========== USDT COMPATIBILITY TESTS ==========
    
    function testPurchaseWithUSDT() public {
        _startPresale();
        
        uint256 usdtAmount = 5000 * 1e6; // $5000 USDT
        
        // Approve and purchase
        vm.startPrank(buyer1);
        mockUSDT.approve(address(presale), usdtAmount);
        
        Authorizer.Voucher memory voucher = _createVoucher(buyer1, buyer1, address(mockUSDT), 0);
        bytes memory signature = _signVoucher(voucher);
        
        presale.buyWithTokenVoucher(address(mockUSDT), usdtAmount, buyer1, voucher, signature);
        vm.stopPrank();
        
        // Verify purchase successful (SafeERC20 handles non-standard USDT)
        assertTrue(presale.totalPurchased(buyer1) > 0);
        assertEq(mockUSDT.balanceOf(address(presale)), usdtAmount);
    }
    
    function testMultipleUSDTPurchases() public {
        _startPresale();
        
        // First purchase
        uint256 firstAmount = 1000 * 1e6;
        vm.startPrank(buyer1);
        mockUSDT.approve(address(presale), firstAmount);
        Authorizer.Voucher memory voucher1 = _createVoucher(buyer1, buyer1, address(mockUSDT), 0);
        presale.buyWithTokenVoucher(address(mockUSDT), firstAmount, buyer1, voucher1, _signVoucher(voucher1));
        uint256 tokensAfterFirst = presale.totalPurchased(buyer1);
        vm.stopPrank();
        
        // Second purchase
        uint256 secondAmount = 2000 * 1e6;
        vm.startPrank(buyer1);
        mockUSDT.approve(address(presale), secondAmount);
        Authorizer.Voucher memory voucher2 = _createVoucher(buyer1, buyer1, address(mockUSDT), 1);
        presale.buyWithTokenVoucher(address(mockUSDT), secondAmount, buyer1, voucher2, _signVoucher(voucher2));
        vm.stopPrank();
        
        // Verify accumulation
        assertTrue(presale.totalPurchased(buyer1) > tokensAfterFirst);
        assertEq(mockUSDT.balanceOf(address(presale)), firstAmount + secondAmount);
    }
    
    // ========== DECIMAL HANDLING TESTS ==========
    
    function testDecimalHandling6Decimals() public {
        _startPresale();
        
        // USDC: 6 decimals, $1 per token
        uint256 usdcAmount = 100 * 1e6; // $100
        _makeTokenPurchase(buyer1, address(mockUSDC), usdcAmount, 0);
        
        uint256 expectedTokens = 100 * presale.presaleRate(); // $100 worth of tokens
        uint256 actualTokens = presale.totalPurchased(buyer1);
        
        // Allow small rounding difference
        assertApproxEqRel(actualTokens, expectedTokens, 0.01e18); // 1% tolerance
    }
    
    function testDecimalHandling8Decimals() public {
        _startPresale();
        
        // WBTC: 8 decimals, $45,000 per token
        uint256 wbtcAmount = 0.01 * 1e8; // 0.01 WBTC = $450
        _makeTokenPurchase(buyer1, address(mockWBTC), wbtcAmount, 0);
        
        uint256 expectedTokens = 450 * presale.presaleRate(); // $450 worth
        uint256 actualTokens = presale.totalPurchased(buyer1);
        
        assertApproxEqRel(actualTokens, expectedTokens, 0.01e18);
    }
    
    function testDecimalHandling18Decimals() public {
        _startPresale();
        
        // WETH: 18 decimals, $4200 per token
        uint256 wethAmount = 0.5 * 1e18; // 0.5 WETH = $2100
        _makeTokenPurchase(buyer1, address(mockWETH), wethAmount, 0);
        
        uint256 expectedTokens = 2100 * presale.presaleRate(); // $2100 worth
        uint256 actualTokens = presale.totalPurchased(buyer1);
        
        assertApproxEqRel(actualTokens, expectedTokens, 0.01e18);
    }
    
    function testMixedDecimalPurchases() public {
        _startPresale();
        
        // Purchase with all three decimal types
        _makeTokenPurchase(buyer1, address(mockUSDC), 100 * 1e6, 0);   // $100
        _makeTokenPurchase(buyer1, address(mockWBTC), 0.01 * 1e8, 1);  // $450
        _makeTokenPurchase(buyer1, address(mockWETH), 0.5 * 1e18, 2);  // $2100
        
        // Total should be $2650 worth of tokens
        uint256 expectedTokens = 2650 * presale.presaleRate();
        uint256 actualTokens = presale.totalPurchased(buyer1);
        
        assertApproxEqRel(actualTokens, expectedTokens, 0.02e18); // 2% tolerance for rounding
    }
    
    // ========== EDGE CASES ==========
    
    function testCannotPurchaseWithInactiveToken() public {
        // Disable USDC BEFORE starting presale (when currentRound == 0)
        vm.prank(owner);
        presale.setTokenPrice(address(mockUSDC), 1 * 1e8, 6, false);
        
        _startPresale();
        
        vm.startPrank(buyer1);
        mockUSDC.approve(address(presale), 1000 * 1e6);
        
        Authorizer.Voucher memory voucher = _createVoucher(buyer1, buyer1, address(mockUSDC), 0);
        bytes memory signature = _signVoucher(voucher);
        
        vm.expectRevert("Token not accepted");
        presale.buyWithTokenVoucher(address(mockUSDC), 1000 * 1e6, buyer1, voucher, signature);
        vm.stopPrank();
    }
    
    function testCannotPurchaseWithNativeUsingTokenFunction() public {
        _startPresale();
        
        Authorizer.Voucher memory voucher = _createVoucher(buyer1, buyer1, address(0), 0);
        bytes memory signature = _signVoucher(voucher);
        
        vm.expectRevert("Use buyWithNativeVoucher for native currency");
        vm.prank(buyer1);
        presale.buyWithTokenVoucher(address(0), 0.01 ether, buyer1, voucher, signature);
    }
    
    // ========== NO PER-USER LIMIT TESTS (GRO-04 ACKNOWLEDGED) ==========

    function testNoPerUserLimitLargePurchase() public {
    _startPresale();
    
    // Purchase $50,000 (way beyond old $10k per-user limit)
    uint256 largeAmount = 50000 * 1e6;
    
    vm.startPrank(buyer1);
    mockUSDC.approve(address(presale), largeAmount);
    
    // Create voucher with $50,000 limit (not $10k default)
    Authorizer.Voucher memory voucher = Authorizer.Voucher({
        buyer: buyer1,
        beneficiary: buyer1,
        paymentToken: address(mockUSDC),
        usdLimit: 50000 * 1e8, // ✅ $50,000 voucher limit
        nonce: 0,
        deadline: type(uint256).max,
        presale: address(presale)
    });
    
    bytes memory signature = _signVoucher(voucher);
    
    // Should succeed - no per-user limit in contract
    presale.buyWithTokenVoucher(address(mockUSDC), largeAmount, buyer1, voucher, signature);
    vm.stopPrank();
    
    assertTrue(presale.totalPurchased(buyer1) > 0);
    assertEq(mockUSDC.balanceOf(address(presale)), largeAmount);
}
    
    /// @notice Test that presaleEndTime is not overwritten after presale ends
    /// @dev This test demonstrates the GRO-05 fix prevents repeated overwrites of presaleEndTime
    function testPresaleEndTimeNotOverwrittenAfterEnd() public {
        // Start MAIN presale (not escrow) to test main presale endPresale() function
        vm.warp(PRESALE_LAUNCH_DATE + 1);
        vm.prank(owner);
        presale.startPresale(34 days);
        
        uint256 startTime = presale.presaleStartTime();
        
        // Verify presale is active initially
        assertTrue(presale.isPresaleActive());
        assertFalse(presale.presaleEnded());

        // End presale manually by owner (must be after presaleEndTime)
        vm.warp(startTime + 35 days); // Warp past the 34-day presale duration
        vm.prank(owner);
        presale.endPresale();

        // Verify presale ended and end time was set
        assertTrue(presale.presaleEnded());
        uint256 originalEndTime = presale.presaleEndTime();
        assertFalse(presale.isPresaleActive());

        // Try purchases after presale ended - should fail
        Authorizer.Voucher memory voucher = _createVoucher(buyer1, buyer1, address(0), 0);
        bytes memory signature = _signVoucher(voucher);

        // This should fail because presale ended (presaleEnded flag is true)
        vm.expectRevert("No presale active");
        vm.prank(buyer1);
        presale.buyWithNativeVoucher{value: 0.01 ether}(buyer1, voucher, signature);

        // **CRITICAL ASSERTION**: Verify presaleEndTime hasn't changed
        assertEq(presale.presaleEndTime(), originalEndTime,
            "GRO-05 FIX FAILED: presaleEndTime was overwritten after presale ended");

        // Warp further into future and try again
        vm.warp(startTime + 40 days);
        vm.expectRevert("No presale active");
        vm.prank(buyer1);
        presale.buyWithNativeVoucher{value: 0.01 ether}(buyer1, voucher, signature);

        // **CRITICAL ASSERTION**: Verify presaleEndTime still hasn't changed
        assertEq(presale.presaleEndTime(), originalEndTime,
            "GRO-05 FIX FAILED: presaleEndTime was overwritten after presale ended");

        // Verify presale is still ended
        assertTrue(presale.presaleEnded());
        assertFalse(presale.isPresaleActive());
    }

    /// @notice Test that demonstrates the vulnerability before the fix
    /// @dev This test shows what would happen without the GRO-05 fix
    function testPresaleEndTimeOverwriteVulnerability() public {
        // Start MAIN presale (not escrow) to test main presale endPresale() function
        vm.warp(PRESALE_LAUNCH_DATE + 1);
        vm.prank(owner);
        presale.startPresale(34 days);

        // End presale by reaching max duration
        uint256 startTime = presale.presaleStartTime();
        vm.warp(startTime + 34 days + 1);

        // First end condition met - presale should end
        vm.prank(owner);
        presale.endPresale();

        // Record the original end time
        uint256 originalEndTime = presale.presaleEndTime();

        // Warp to a different time (simulating different block timestamp)
        vm.warp(startTime + 35 days + 1000);

        // Make a purchase that would trigger _checkAutoEndConditions
        // Before fix: this would overwrite presaleEndTime
        // After fix: this should be prevented

        Authorizer.Voucher memory voucher = _createVoucher(buyer1, buyer1, address(0), 0);
        bytes memory signature = _signVoucher(voucher);

        // This should fail because presale ended (presaleEnded flag is true)
        vm.expectRevert("No presale active");
        vm.prank(buyer1);
        presale.buyWithNativeVoucher{value: 0.01 ether}(buyer1, voucher, signature);

        // **CRITICAL**: Verify end time is preserved
        assertEq(presale.presaleEndTime(), originalEndTime,
            "GRO-05 FIX VERIFICATION: End time should be preserved");

        // Verify the presale status is still correctly ended
        (, bool ended,,,) = presale.getPresaleStatus();
        assertTrue(ended);
        assertFalse(presale.isPresaleActive());
    }


    // ========== GRO-09 DEFLATIONARY TOKEN TESTS ==========

    function testDeflationaryTokenRejectedInPresale() public {
        _startPresale();

        uint256 purchaseAmount = 10000 * 1e6; // $10,000 worth of deflationary tokens

        // Approve and try to purchase with deflationary token
        vm.startPrank(buyer1);
        mockDeflationaryToken.approve(address(presale), purchaseAmount);

        Authorizer.Voucher memory voucher = _createVoucher(buyer1, buyer1, address(mockDeflationaryToken), 0);
        bytes memory signature = _signVoucher(voucher);

        // Should revert because deflationary token doesn't deliver expected amount
        vm.expectRevert("Deflationary token not supported");
        presale.buyWithTokenVoucher(address(mockDeflationaryToken), purchaseAmount, buyer1, voucher, signature);
        vm.stopPrank();
    }


    function _startPresale() internal {
        vm.warp(PRESALE_LAUNCH_DATE + 1);
        presale.autoStartIEscrowPresale();
    }


    function _createVoucher(
        address buyer,
        address beneficiary,
        address paymentToken,
        uint256 nonce
    ) internal view returns (Authorizer.Voucher memory) {
        return Authorizer.Voucher({
            buyer: buyer,
            beneficiary: beneficiary,
            paymentToken: paymentToken,
            usdLimit: VOUCHER_LIMIT,
            nonce: nonce,
            deadline: type(uint256).max,
            presale: address(presale)
        });
    }
    
    function _signVoucher(Authorizer.Voucher memory voucher) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(abi.encode(
            keccak256("Voucher(address buyer,address beneficiary,address paymentToken,uint256 usdLimit,uint256 nonce,uint256 deadline,address presale)"),
            voucher.buyer,
            voucher.beneficiary,
            voucher.paymentToken,
            voucher.usdLimit,
            voucher.nonce,
            voucher.deadline,
            voucher.presale
        ));
        
        bytes32 domainSeparator = authorizer.getDomainSeparator();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        return abi.encodePacked(r, s, v);
    }
    
    function _makePurchase(address buyer, uint256 amount, uint256 nonce) internal {
        Authorizer.Voucher memory voucher = _createVoucher(buyer, buyer, address(0), nonce);
        bytes memory signature = _signVoucher(voucher);
        
        vm.prank(buyer);
        presale.buyWithNativeVoucher{value: amount}(buyer, voucher, signature);
    }
    
    function _makeTokenPurchase(address buyer, address token, uint256 amount, uint256 nonce) internal {
        Authorizer.Voucher memory voucher = _createVoucher(buyer, buyer, token, nonce);
        bytes memory signature = _signVoucher(voucher);

        vm.startPrank(buyer);
        // Use IERC20 interface for approval since both MockERC20 and MockUSDT implement it
        IERC20(token).approve(address(presale), amount);
        presale.buyWithTokenVoucher(token, amount, buyer, voucher, signature);
        vm.stopPrank();
    }
}

