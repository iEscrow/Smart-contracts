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

contract GRO07AuditFixTest is Test {
    MultiTokenPresale presale;
    Authorizer authorizer;
    EscrowToken escrowToken;
    MockERC20 usdc;
    
    // GRO-02: Use hardcoded owner address from contract
    address owner = 0xd81d23f2e37248F8fda5e7BF0a6c047AE234F0A2;
    address buyer = address(0x2);
    address treasury = address(0x3);
    address staking = address(0x4);
    
    uint256 constant USDC_PRICE = 1 * 1e8; // $1 per USDC (8 decimals USD)
    uint256 constant PRESALE_RATE = 666666666666666667000; // Tokens per USD (18 decimals)
    uint256 constant MAX_TOKENS = 5000000000 * 1e18; // 5B tokens
    
    uint256 public signerPrivateKey = 0xB0B;
    address public signer = vm.addr(signerPrivateKey);
    
    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy mock tokens
        escrowToken = new EscrowToken();
        usdc = new MockERC20("USD Coin", "USDC", 6);
        
        // Deploy authorizer
        authorizer = new Authorizer(signer, owner);
        
        presale = new MultiTokenPresale(
            address(escrowToken),
            PRESALE_RATE,
            MAX_TOKENS
        );
        
        // Setup USDC token with standard price
        presale.setTokenPrice(
            address(usdc),
            USDC_PRICE,
            6, // USDC decimals
            true // active
        );
        
        // Configure authorizer and enable voucher system
        escrowToken.mintPresaleAllocation(address(presale), staking);
        presale.updateAuthorizer(address(authorizer));
        presale.setVoucherSystemEnabled(true);
        
        vm.stopPrank();
        
        // Mint USDC to buyer
        usdc.mint(buyer, 100000 * 1e6); // 100,000 USDC
        
        vm.deal(buyer, 100 ether);
    }
    
    function _createVoucher(
        address _buyer,
        address _beneficiary,
        address _paymentToken,
        uint256 _nonce
    ) internal view returns (Authorizer.Voucher memory) {
        return Authorizer.Voucher({
            buyer: _buyer,
            beneficiary: _beneficiary,
            paymentToken: _paymentToken,
            usdLimit: 10000 * 1e8,
            nonce: _nonce,
            deadline: block.timestamp + 3600,
            presale: address(presale)
        });
    }
    
    function _createVoucherWithCurrentNonce(
        address _buyer,
        address _beneficiary,
        address _paymentToken
    ) internal view returns (Authorizer.Voucher memory) {
        uint256 currentNonce = authorizer.getNonce(_buyer);
        return _createVoucher(_buyer, _beneficiary, _paymentToken, currentNonce);
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
    
    function testGRO07_SmallUSDCAmountRevertsBeforeTransfer() public {
        // With the voucher system USD calculation: (amount * priceUSD) / (10^decimals)
        // For usdAmount to be 0: (amount * priceUSD) / (10^decimals) < 1
        // With USDC (6 decimals), if we set a very small price, small amounts can result in 0 USD
        // For testing, let's use a very small price that makes this possible
        vm.startPrank(owner);
        presale.setTokenPrice(address(usdc), 1, 6, true); // Set very low price: $0.00000001 per USDC
        
        // Start presale after setting the price
        vm.warp(1762819200); // Nov 11, 2025
        presale.autoStartIEscrowPresale();
        vm.stopPrank();
        
        vm.startPrank(buyer);
        uint256 smallAmount = 50; // 50 micro-USDC, should result in usdAmount = 0
        
        // Approve USDC spending
        usdc.approve(address(presale), 10000);
        
        // Create voucher for small purchase
        Authorizer.Voucher memory voucher = _createVoucherWithCurrentNonce(
            buyer,
            buyer,
            address(usdc)
        );
        
        bytes memory signature = _signVoucher(voucher);
        
        // This should revert with "Payment amount too small" BEFORE transferring USDC
        uint256 balanceBefore = usdc.balanceOf(buyer);
        
        vm.expectRevert("Payment amount too small");
        presale.buyWithTokenVoucher(
            address(usdc),
            smallAmount,
            buyer,
            voucher,
            signature
        );
        
        // Verify no USDC was transferred
        uint256 balanceAfter = usdc.balanceOf(buyer);
        assertEq(balanceAfter, balanceBefore, "USDC should not have been transferred");
        
        vm.stopPrank();
    }
    
    function testGRO07_ViewFunctionRevertsForSmallAmounts() public {
        // Start presale first
        vm.warp(1762819200); // Nov 11, 2025
        presale.autoStartIEscrowPresale();
        
        // Test the view function also reverts for small amounts
        uint256 smallAmount = 1000; // Below threshold
        
        vm.expectRevert("Payment amount too small");
        presale.calculateTokenAmount(address(usdc), smallAmount, buyer);
    }
    
    function testGRO07_ValidAmountStillWorks() public {
        // Start presale first
        vm.warp(1762819200); // Nov 11, 2025
        presale.autoStartIEscrowPresale();
        
        vm.startPrank(buyer);
        
        // Use an amount that definitely results in > 0 tokens
        uint256 validAmount = 1000 * 1e6; // 1000 USDC = $1000
        
        // Approve USDC spending
        usdc.approve(address(presale), validAmount);
        
        // Create voucher for valid purchase
        Authorizer.Voucher memory voucher = _createVoucherWithCurrentNonce(
            buyer,
            buyer,
            address(usdc)
        );
        
        bytes memory signature = _signVoucher(voucher);
        
        // This should succeed
        uint256 balanceBefore = usdc.balanceOf(buyer);
        uint256 tokensBefore = presale.totalPurchased(buyer);
        
        presale.buyWithTokenVoucher(
            address(usdc),
            validAmount,
            buyer,
            voucher,
            signature
        );
        
        // Verify USDC was transferred and tokens were purchased
        uint256 balanceAfter = usdc.balanceOf(buyer);
        uint256 tokensAfter = presale.totalPurchased(buyer);
        
        assertLt(balanceAfter, balanceBefore, "USDC should have been transferred");
        assertGt(tokensAfter, tokensBefore, "Presale tokens should have been purchased");
        
        vm.stopPrank();
    }
    
    function testGRO07_CalculateThresholdEdgeCases() public {
        // Test the calculateTokenAmount function with realistic threshold
        
        // Set a low price to test the threshold where usdValue becomes 0
        vm.startPrank(owner);
        presale.setTokenPrice(address(usdc), 100, 6, true); // $0.000001 per USDC
        
        // Start presale after setting the price
        vm.warp(1762819200); // Nov 11, 2025
        presale.autoStartIEscrowPresale();
        vm.stopPrank();
        
        // With this price: usdValue = (amount * 100) / (10^6 * 10^8) = amount * 100 / 1e14
        // For usdValue = 1: amount = 1e14 / 100 = 1e12
        
        // Small amount should revert
        vm.expectRevert("Payment amount too small");
        presale.calculateTokenAmount(address(usdc), 1e11, buyer); // Below threshold
        
        // At threshold should work
        uint256 tokensAtThreshold = presale.calculateTokenAmount(address(usdc), 1e12, buyer);
        assertGt(tokensAtThreshold, 0, "Should get tokens at threshold");
        
        // Above threshold should definitely work
        uint256 tokensAboveThreshold = presale.calculateTokenAmount(address(usdc), 1e13, buyer);
        assertGt(tokensAboveThreshold, tokensAtThreshold, "Should get more tokens above threshold");
    }
}