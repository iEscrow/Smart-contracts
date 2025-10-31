// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../MultiTokenPresale.sol";
import "../Authorizer.sol";
import "../EscrowToken.sol";
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

contract GRO08AuditFixTest is Test {
    MultiTokenPresale presale;
    Authorizer authorizer;
    EscrowToken escrowToken;
    MockERC20 wbtc;
    MockERC20 weth;
    
    // GRO-02: Use hardcoded owner address from contract
    address owner = 0xd81d23f2e37248F8fda5e7BF0a6c047AE234F0A2;
    address buyer = address(0x2);
    address staking = address(0x4);
    
    uint256 public signerPrivateKey = 0xB0B;
    address public signer = vm.addr(signerPrivateKey);
    
    uint256 constant PRESALE_RATE = 666666666666666667000;
    uint256 constant MAX_TOKENS = 5000000000 * 1e18;
    uint256 constant PRESALE_LAUNCH_DATE = 1762819200;
    
    // Round 1 prices
    uint256 constant WBTC_PRICE_R1 = 45000 * 1e8; // $45,000
    uint256 constant WETH_PRICE_R1 = 4200 * 1e8;  // $4,200
    
    // Round 2 prices (different)
    uint256 constant WBTC_PRICE_R2 = 50000 * 1e8; // $50,000
    uint256 constant WETH_PRICE_R2 = 4500 * 1e8;  // $4,500
    
    event PriceUpdated(address indexed token, uint256 newPrice);
    event RoundAdvanced(uint256 fromRound, uint256 toRound, uint256 timestamp);
    
    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy contracts
        escrowToken = new EscrowToken();
        wbtc = new MockERC20("Wrapped Bitcoin", "WBTC", 8);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        
        authorizer = new Authorizer(signer, owner);
        
        presale = new MultiTokenPresale(
            address(escrowToken),
            PRESALE_RATE,
            MAX_TOKENS
        );
        
        // Setup contracts
        escrowToken.mintPresaleAllocation(address(presale), staking);
        presale.updateAuthorizer(address(authorizer));
        presale.setVoucherSystemEnabled(true);
        
        vm.stopPrank();
        
        // Mint tokens to buyer
        wbtc.mint(buyer, 10 * 1e8); // 10 WBTC
        weth.mint(buyer, 100 * 1e18); // 100 WETH
        vm.deal(buyer, 100 ether);
    }
    
    function _startPresale() internal {
        vm.warp(PRESALE_LAUNCH_DATE + 1);
        presale.autoStartIEscrowPresale();
    }
    
    function _startMainPresale() internal {
        vm.startPrank(owner);
        presale.startPresale(presale.MAX_PRESALE_DURATION());
        vm.stopPrank();
    }
    
    function testGRO08_CannotChangePricesDuringRound1() public {
        _startPresale();
        
        // Verify we're in round 1
        assertEq(presale.escrowCurrentRound(), 1);
        
        // Try to change WBTC price during round 1 - should revert
        vm.prank(owner);
        vm.expectRevert("Cannot change prices during active presale");
        presale.setTokenPrice(address(wbtc), 50000 * 1e8, 8, true);
    }
    
    function testGRO08_CannotChangePricesArrayDuringRound1() public {
        _startPresale();
        
        // Verify we're in round 1
        assertEq(presale.escrowCurrentRound(), 1);
        
        // Prepare arrays for bulk price update
        address[] memory tokens = new address[](2);
        uint256[] memory prices = new uint256[](2);
        uint8[] memory decimalsArray = new uint8[](2);
        bool[] memory activeArray = new bool[](2);
        
        tokens[0] = address(wbtc);
        tokens[1] = address(weth);
        prices[0] = WBTC_PRICE_R2;
        prices[1] = WETH_PRICE_R2;
        decimalsArray[0] = 8;
        decimalsArray[1] = 18;
        activeArray[0] = true;
        activeArray[1] = true;
        
        // Try to change prices during round 1 - should revert
        vm.prank(owner);
        vm.expectRevert("Cannot change prices during active presale");
        presale.setTokenPrices(tokens, prices, decimalsArray, activeArray);
    }
    
    function testGRO08_CanChangePricesWhenNoRoundActive() public {
        // Before presale starts (round 0), price changes should be allowed
        assertEq(presale.escrowCurrentRound(), 0);
        
        vm.prank(owner);
        presale.setTokenPrice(address(wbtc), 50000 * 1e8, 8, true);
        
        // Verify price was updated
        MultiTokenPresale.TokenPrice memory price = presale.getTokenPrice(address(wbtc));
        assertEq(price.priceUSD, 50000 * 1e8);
    }
    
    function testGRO08_MoveToRound2RequiresPriceUpdate() public {
        _startPresale();
        
        // Try to move to round 2 without providing prices - should revert
        address[] memory emptyTokens = new address[](0);
        uint256[] memory emptyPrices = new uint256[](0);
        uint8[] memory emptyDecimals = new uint8[](0);
        bool[] memory emptyActive = new bool[](0);
        
        vm.prank(owner);
        vm.expectRevert("Must provide round 2 prices");
        presale.moveEscrowToRound2(emptyTokens, emptyPrices, emptyDecimals, emptyActive);
    }
    
    function testGRO08_MoveToRound2RequiresDifferentPrices() public {
        _startPresale();
        
        // Use NATIVE_ADDRESS (ETH) which has a configured price
        address nativeToken = presale.NATIVE_ADDRESS();
        MultiTokenPresale.TokenPrice memory currentPrice = presale.getTokenPrice(nativeToken);
        
        // Try to set the same price for round 2 - should revert
        address[] memory tokens = new address[](1);
        uint256[] memory prices = new uint256[](1);
        uint8[] memory decimalsArray = new uint8[](1);
        bool[] memory activeArray = new bool[](1);
        
        tokens[0] = nativeToken;
        prices[0] = currentPrice.priceUSD; // Same price as round 1
        decimalsArray[0] = 18;
        activeArray[0] = true;
        
        vm.prank(owner);
        vm.expectRevert("Round 2 price must differ from round 1");
        presale.moveEscrowToRound2(tokens, prices, decimalsArray, activeArray);
    }
    
    function testGRO08_SuccessfulMoveToRound2WithNewPrices() public {
        _startPresale();
        
        // Prepare round 2 prices (different from round 1)
        address[] memory tokens = new address[](2);
        uint256[] memory prices = new uint256[](2);
        uint8[] memory decimalsArray = new uint8[](2);
        bool[] memory activeArray = new bool[](2);
        
        tokens[0] = address(wbtc);
        tokens[1] = address(weth);
        prices[0] = WBTC_PRICE_R2;
        prices[1] = WETH_PRICE_R2;
        decimalsArray[0] = 8;
        decimalsArray[1] = 18;
        activeArray[0] = true;
        activeArray[1] = true;
        
        // Expect events for price updates and round advancement
        vm.expectEmit(true, false, false, true);
        emit PriceUpdated(address(wbtc), WBTC_PRICE_R2);
        
        vm.expectEmit(true, false, false, true);
        emit PriceUpdated(address(weth), WETH_PRICE_R2);
        
        vm.expectEmit(false, false, false, true);
        emit RoundAdvanced(1, 2, block.timestamp);
        
        // Move to round 2 with new prices
        vm.prank(owner);
        presale.moveEscrowToRound2(tokens, prices, decimalsArray, activeArray);
        
        // Verify we're now in round 2
        assertEq(presale.escrowCurrentRound(), 2);
        
        // Verify prices were updated
        MultiTokenPresale.TokenPrice memory wbtcPrice = presale.getTokenPrice(address(wbtc));
        MultiTokenPresale.TokenPrice memory wethPrice = presale.getTokenPrice(address(weth));
        
        assertEq(wbtcPrice.priceUSD, WBTC_PRICE_R2);
        assertEq(wethPrice.priceUSD, WETH_PRICE_R2);
    }
    
    function testGRO08_CannotChangePricesDuringRound2() public {
        _startPresale();
        
        // Move to round 2
        address[] memory tokens = new address[](1);
        uint256[] memory prices = new uint256[](1);
        uint8[] memory decimalsArray = new uint8[](1);
        bool[] memory activeArray = new bool[](1);
        
        tokens[0] = address(wbtc);
        prices[0] = WBTC_PRICE_R2;
        decimalsArray[0] = 8;
        activeArray[0] = true;
        
        vm.prank(owner);
        presale.moveEscrowToRound2(tokens, prices, decimalsArray, activeArray);
        
        // Verify we're in round 2
        assertEq(presale.escrowCurrentRound(), 2);
        
        // Try to change prices during round 2 - should revert
        vm.prank(owner);
        vm.expectRevert("Cannot change prices during active presale");
        presale.setTokenPrice(address(wbtc), 55000 * 1e8, 8, true);
    }
    
    function testGRO08_EmergencyPriceUpdateOnlyDuringActivePresale() public {
        // Try emergency price update before presale starts - should revert
        address[] memory tokens = new address[](1);
        uint256[] memory prices = new uint256[](1);
        uint8[] memory decimalsArray = new uint8[](1);
        bool[] memory activeArray = new bool[](1);
        
        tokens[0] = address(wbtc);
        prices[0] = WBTC_PRICE_R2;
        decimalsArray[0] = 8;
        activeArray[0] = true;
        
        vm.prank(owner);
        vm.expectRevert("Presale not active");
        presale.emergencyUpdatePrices(tokens, prices, decimalsArray, activeArray);
    }
    
    function testGRO08_EmergencyPriceUpdateWorksWhenNeeded() public {
        // Set initial WBTC price before starting presale
        vm.prank(owner);
        presale.setTokenPrice(address(wbtc), WBTC_PRICE_R1, 8, true);
        
        // Start main presale for emergency update test
        _startMainPresale();
        
        // Move to round 2
        address[] memory tokens = new address[](1);
        uint256[] memory prices = new uint256[](1);
        uint8[] memory decimalsArray = new uint8[](1);
        bool[] memory activeArray = new bool[](1);
        
        tokens[0] = address(wbtc);
        prices[0] = WBTC_PRICE_R2;
        decimalsArray[0] = 8;
        activeArray[0] = true;
        
        vm.prank(owner);
        presale.moveToRound2(tokens, prices, decimalsArray, activeArray);
        
        // Now use emergency function to adjust prices (simulating emergency situation)
        prices[0] = 52000 * 1e8; // Emergency price adjustment
        
        vm.prank(owner);
        presale.emergencyUpdatePrices(tokens, prices, decimalsArray, activeArray);
        
        // Verify price was updated
        MultiTokenPresale.TokenPrice memory newPrice = presale.getTokenPrice(address(wbtc));
        assertEq(newPrice.priceUSD, 52000 * 1e8);
    }
    
    function testGRO08_PriceChangesAffectTokenCalculations() public {
        // First, set up WBTC with an initial price before starting presale
        vm.prank(owner);
        presale.setTokenPrice(address(wbtc), WBTC_PRICE_R1, 8, true);
        
        _startPresale();
        
        // Calculate tokens with round 1 WBTC price
        uint256 wbtcAmount = 0.01 * 1e8; // 0.01 WBTC
        uint256 tokensRound1 = presale.calculateTokenAmount(address(wbtc), wbtcAmount, buyer);
        
        // Move to round 2 with higher WBTC price
        address[] memory tokens = new address[](1);
        uint256[] memory prices = new uint256[](1);
        uint8[] memory decimalsArray = new uint8[](1);
        bool[] memory activeArray = new bool[](1);
        
        tokens[0] = address(wbtc);
        prices[0] = WBTC_PRICE_R2; // Higher price
        decimalsArray[0] = 8;
        activeArray[0] = true;
        
        vm.prank(owner);
        presale.moveEscrowToRound2(tokens, prices, decimalsArray, activeArray);
        
        // Calculate tokens with round 2 WBTC price
        uint256 tokensRound2 = presale.calculateTokenAmount(address(wbtc), wbtcAmount, buyer);
        
        // Round 2 should give more tokens due to higher WBTC price
        assertGt(tokensRound2, tokensRound1);
    }
    
    function testGRO08_CannotMoveToRound2WhenNotInRound1() public {
        // Try to move to round 2 when presale hasn't started (round 0)
        address[] memory tokens = new address[](1);
        uint256[] memory prices = new uint256[](1);
        uint8[] memory decimalsArray = new uint8[](1);
        bool[] memory activeArray = new bool[](1);
        
        tokens[0] = address(wbtc);
        prices[0] = WBTC_PRICE_R2;
        decimalsArray[0] = 8;
        activeArray[0] = true;
        
        vm.prank(owner);
        vm.expectRevert("Escrow presale not in round 1");
        presale.moveEscrowToRound2(tokens, prices, decimalsArray, activeArray);
    }
    
    function testGRO08_ArrayLengthMismatchReverts() public {
        _startPresale();
        
        // Mismatched array lengths
        address[] memory tokens = new address[](2);
        uint256[] memory prices = new uint256[](1); // Different length
        uint8[] memory decimalsArray = new uint8[](2);
        bool[] memory activeArray = new bool[](2);
        
        tokens[0] = address(wbtc);
        tokens[1] = address(weth);
        prices[0] = WBTC_PRICE_R2;
        decimalsArray[0] = 8;
        decimalsArray[1] = 18;
        activeArray[0] = true;
        activeArray[1] = true;
        
        vm.prank(owner);
        vm.expectRevert("Array length mismatch");
        presale.moveEscrowToRound2(tokens, prices, decimalsArray, activeArray);
    }
}