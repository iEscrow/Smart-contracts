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

/**
 * @title DevTreasuryIntegration
 * @notice Complete simulation test: User purchases tokens → DevTreasury receives 4% fee
 */
contract DevTreasuryIntegrationTest is Test {
    DevTreasury public devTreasury;
    MultiTokenPresale public presale;
    EscrowToken public escrowToken;
    Authorizer public authorizer;
    MockERC20 public usdc;
    
    // Real addresses from contract
    address public constant SURYA = 0x04435410a78192baAfa00c72C659aD3187a2C2cF;
    address public constant BHOM = 0x9005132849bC9585A948269D96F23f56e5981A61;
    address public constant ZALA = 0x1C5cf9Cb69effeeb31E261BB6519AF7247A97A74;
    address public constant MUHAMMAD = 0x507541B0Caf529a063E97c6C145E521d3F394264;
    
    address public owner = 0xd81d23f2e37248F8fda5e7BF0a6c047AE234F0A2;
    address public buyer1 = address(0x123);
    address public buyer2 = address(0x456);
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
        
        // Deploy temporary contracts to calculate addresses
        // We need: presale -> devTreasury (for fees) and devTreasury -> presale (for checking if ended)
        // Solution: Use deterministic address calculation
        
        // Calculate what the presale address WILL BE after we deploy devTreasury
        // Owner nonce is currently at some value, presale will be deployed at nonce+2
        address predictedPresaleAddr = vm.computeCreateAddress(owner, vm.getNonce(owner) + 1);
        
        // Deploy DevTreasury with predicted presale address
        devTreasury = new DevTreasury(predictedPresaleAddr);
        
        // Now deploy presale with devTreasury address (this MUST be at the predicted address)
        presale = new MultiTokenPresale(
            address(escrowToken),
            PRESALE_RATE,
            MAX_TOKENS,
            address(devTreasury)
        );
        
        // Set up presale
        escrowToken.mintPresaleAllocation(address(presale), staking);
        presale.updateAuthorizer(address(authorizer));
        presale.setVoucherSystemEnabled(true);
        
        // Deploy mock USDC
        usdc = new MockERC20("USD Coin", "USDC", 6);
        presale.setTokenPrice(address(usdc), 1 * 1e8, 6, true);
        
        // Start presale
        vm.warp(1762819200 + 1); // After launch date
        presale.autoStartIEscrowPresale();
        
        vm.stopPrank();
        
        // Give buyers funds
        vm.deal(buyer1, 100 ether);
        vm.deal(buyer2, 100 ether);
        usdc.mint(buyer1, 100000 * 1e6);
        usdc.mint(buyer2, 100000 * 1e6);
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
            usdLimit: 100000 * 1e8,
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
    
    // ============ COMPLETE SIMULATION TESTS ============
    
    /// @notice Complete simulation: User buys with ETH → DevTreasury gets 4%
    function testCompleteSimulation_ETHPurchase() public {
        console.log("\n=== COMPLETE SIMULATION: ETH Purchase ===");
        
        // Initial balances
        uint256 initialPresaleBalance = address(presale).balance;
        uint256 initialDevTreasuryBalance = address(devTreasury).balance;
        console.log("Initial Presale Balance:", initialPresaleBalance);
        console.log("Initial DevTreasury Balance:", initialDevTreasuryBalance);
        
        // User buys 10 ETH worth of tokens
        uint256 purchaseAmount = 10 ether;
        console.log("\n--- User buying with", purchaseAmount / 1e18, "ETH ---");
        
        Authorizer.Voucher memory voucher = _createVoucher(buyer1, buyer1, address(0), 0);
        bytes memory signature = _signVoucher(voucher);
        
        vm.prank(buyer1);
        presale.buyWithNativeVoucher{value: purchaseAmount}(buyer1, voucher, signature);
        
        // Check balances after purchase
        uint256 afterPresaleBalance = address(presale).balance;
        uint256 afterDevTreasuryBalance = address(devTreasury).balance;
        
        // Calculate expected amounts (after gas buffer)
        uint256 gasBuffer = presale.gasBuffer();
        uint256 amountAfterBuffer = purchaseAmount - gasBuffer;
        uint256 expectedDevFee = (amountAfterBuffer * 400) / 10000; // 4%
        // Note: There might be small rounding differences, so we check approximate values
        
        console.log("\n--- After Purchase ---");
        console.log("Presale Balance:", afterPresaleBalance);
        console.log("DevTreasury Balance:", afterDevTreasuryBalance);
        console.log("Expected DevTreasury (4%):", expectedDevFee);
        
        // Verify 4% went to DevTreasury (allow small rounding difference)
        assertApproxEqAbs(afterDevTreasuryBalance, expectedDevFee, 1e15, "DevTreasury should receive ~4%");
        assertTrue(afterPresaleBalance > 0, "Presale should have funds");
        assertTrue(afterDevTreasuryBalance > 0, "DevTreasury should have funds");
        
        // Verify user got tokens
        uint256 userTokens = presale.totalPurchased(buyer1);
        assertTrue(userTokens > 0, "User should receive tokens");
        console.log("User received tokens:", userTokens / 1e18);
        
        console.log("\n[PASS] TEST PASSED: DevTreasury received 4% fee!");
    }
    
    /// @notice Complete simulation: User buys with USDC → DevTreasury gets 4%
    function testCompleteSimulation_USDCPurchase() public {
        console.log("\n=== COMPLETE SIMULATION: USDC Purchase ===");
        
        // Initial balances
        uint256 initialPresaleBalance = usdc.balanceOf(address(presale));
        uint256 initialDevTreasuryBalance = usdc.balanceOf(address(devTreasury));
        console.log("Initial Presale USDC Balance:", initialPresaleBalance / 1e6);
        console.log("Initial DevTreasury USDC Balance:", initialDevTreasuryBalance / 1e6);
        
        // User buys with 5000 USDC
        uint256 purchaseAmount = 5000 * 1e6;
        console.log("\n--- User buying with", purchaseAmount / 1e6, "USDC ---");
        
        vm.startPrank(buyer1);
        usdc.approve(address(presale), purchaseAmount);
        
        Authorizer.Voucher memory voucher = _createVoucher(buyer1, buyer1, address(usdc), 0);
        bytes memory signature = _signVoucher(voucher);
        
        presale.buyWithTokenVoucher(address(usdc), purchaseAmount, buyer1, voucher, signature);
        vm.stopPrank();
        
        // Check balances after purchase
        uint256 afterPresaleBalance = usdc.balanceOf(address(presale));
        uint256 afterDevTreasuryBalance = usdc.balanceOf(address(devTreasury));
        
        // Calculate expected amounts
        uint256 expectedDevFee = (purchaseAmount * 400) / 10000; // 4%
        uint256 expectedPresaleBalance = purchaseAmount - expectedDevFee; // 96%
        
        console.log("\n--- After Purchase ---");
        console.log("Presale USDC Balance:", afterPresaleBalance / 1e6);
        console.log("DevTreasury USDC Balance:", afterDevTreasuryBalance / 1e6);
        console.log("Expected DevTreasury (4%):", expectedDevFee / 1e6);
        console.log("Expected Presale (96%):", expectedPresaleBalance / 1e6);
        
        // Verify 4% went to DevTreasury
        assertEq(afterDevTreasuryBalance, expectedDevFee, "DevTreasury should receive 4%");
        assertEq(afterPresaleBalance, expectedPresaleBalance, "Presale should keep 96%");
        
        // Verify user got tokens
        uint256 userTokens = presale.totalPurchased(buyer1);
        assertTrue(userTokens > 0, "User should receive tokens");
        console.log("User received tokens:", userTokens / 1e18);
        
        console.log("\n[PASS] TEST PASSED: DevTreasury received 4% fee!");
    }
    
    /// @notice Multiple purchases accumulate in DevTreasury
    function testCompleteSimulation_MultiplePurchases() public {
        console.log("\n=== COMPLETE SIMULATION: Multiple Purchases ===");
        
        // Buyer 1 purchases with ETH
        uint256 eth1 = 5 ether;
        console.log("\n--- Buyer1 purchasing", eth1 / 1e18, "ETH ---");
        Authorizer.Voucher memory voucher1 = _createVoucher(buyer1, buyer1, address(0), 0);
        bytes memory signature1 = _signVoucher(voucher1);
        vm.prank(buyer1);
        presale.buyWithNativeVoucher{value: eth1}(buyer1, voucher1, signature1);
        
        uint256 devBalanceAfter1 = address(devTreasury).balance;
        console.log("DevTreasury after buyer1:", devBalanceAfter1 / 1e18, "ETH");
        
        // Buyer 2 purchases with ETH
        uint256 eth2 = 3 ether;
        console.log("\n--- Buyer2 purchasing", eth2 / 1e18, "ETH ---");
        Authorizer.Voucher memory voucher2 = _createVoucher(buyer2, buyer2, address(0), 0);
        bytes memory signature2 = _signVoucher(voucher2);
        vm.prank(buyer2);
        presale.buyWithNativeVoucher{value: eth2}(buyer2, voucher2, signature2);
        
        uint256 devBalanceAfter2 = address(devTreasury).balance;
        console.log("DevTreasury after buyer2:", devBalanceAfter2 / 1e18, "ETH");
        
        // Buyer 1 purchases with USDC
        uint256 usdc1 = 2000 * 1e6;
        console.log("\n--- Buyer1 purchasing", usdc1 / 1e6, "USDC ---");
        vm.startPrank(buyer1);
        usdc.approve(address(presale), usdc1);
        Authorizer.Voucher memory voucher3 = _createVoucher(buyer1, buyer1, address(usdc), 1);
        bytes memory signature3 = _signVoucher(voucher3);
        presale.buyWithTokenVoucher(address(usdc), usdc1, buyer1, voucher3, signature3);
        vm.stopPrank();
        
        uint256 devUSDCBalance = usdc.balanceOf(address(devTreasury));
        console.log("DevTreasury USDC:", devUSDCBalance / 1e6);
        
        // Verify DevTreasury received fees from all purchases
        assertTrue(devBalanceAfter2 > devBalanceAfter1, "DevTreasury ETH should increase");
        assertTrue(devUSDCBalance > 0, "DevTreasury should have USDC");
        
        console.log("\n[PASS] TEST PASSED: DevTreasury accumulates fees from multiple purchases!");
    }
    
    /// @notice Full lifecycle: Purchase → Presale ends → Withdraw from DevTreasury
    function testCompleteSimulation_FullLifecycle() public {
        console.log("\n=== COMPLETE SIMULATION: Full Lifecycle ===");
        
        // Step 1: User purchases
        console.log("\n--- Step 1: User Purchase ---");
        uint256 purchaseAmount = 10 ether;
        Authorizer.Voucher memory voucher = _createVoucher(buyer1, buyer1, address(0), 0);
        bytes memory signature = _signVoucher(voucher);
        vm.prank(buyer1);
        presale.buyWithNativeVoucher{value: purchaseAmount}(buyer1, voucher, signature);
        
        uint256 devBalance = address(devTreasury).balance;
        console.log("DevTreasury balance:", devBalance / 1e18, "ETH");
        assertTrue(devBalance > 0, "DevTreasury should have funds");
        
        // Step 2: End presale
        console.log("\n--- Step 2: End Presale ---");
        vm.warp(block.timestamp + 35 days);
        vm.prank(owner);
        presale.endEscrowPresale();
        console.log("Presale ended");
        
        // Step 3: Withdraw from DevTreasury
        console.log("\n--- Step 3: Withdraw from DevTreasury ---");
        uint256 suryaBefore = SURYA.balance;
        uint256 bhomBefore = BHOM.balance;
        uint256 zalaBefore = ZALA.balance;
        uint256 muhammadBefore = MUHAMMAD.balance;
        
        devTreasury.withdrawETH();
        
        uint256 suryaReceived = SURYA.balance - suryaBefore;
        uint256 bhomReceived = BHOM.balance - bhomBefore;
        uint256 zalaReceived = ZALA.balance - zalaBefore;
        uint256 muhammadReceived = MUHAMMAD.balance - muhammadBefore;
        
        console.log("\n--- Distribution ---");
        console.log("Surya received:", suryaReceived / 1e18, "ETH (31.25%)");
        console.log("Bhom received:", bhomReceived / 1e18, "ETH (31.25%)");
        console.log("Zala received:", zalaReceived / 1e18, "ETH (12.5%)");
        console.log("Muhammad received:", muhammadReceived / 1e18, "ETH (25%)");
        
        // Verify distribution
        assertEq(suryaReceived, (devBalance * 3125) / 10000, "Surya should get 31.25%");
        assertEq(bhomReceived, (devBalance * 3125) / 10000, "Bhom should get 31.25%");
        assertEq(zalaReceived, (devBalance * 1250) / 10000, "Zala should get 12.5%");
        assertEq(muhammadReceived, (devBalance * 2500) / 10000, "Muhammad should get 25%");
        
        console.log("\n[PASS] TEST PASSED: Full lifecycle completed successfully!");
    }
}
