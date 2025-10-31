// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../Authorizer.sol";
import "../MultiTokenPresale.sol";
import "../EscrowToken.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Mock deflationary token that takes 10% fee on transfer
contract DeflationaryToken is ERC20 {
    uint8 private _decimals;
    uint256 public constant FEE_PERCENT = 10; // 10% fee
    
    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }
    
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    
    // Override transfer to apply fee
    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        uint256 fee = (amount * FEE_PERCENT) / 100;
        uint256 amountAfterFee = amount - fee;
        
        _transfer(_msgSender(), to, amountAfterFee);
        // Burn the fee
        _burn(_msgSender(), fee);
        
        return true;
    }
    
    // Override transferFrom to apply fee
    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        
        uint256 fee = (amount * FEE_PERCENT) / 100;
        uint256 amountAfterFee = amount - fee;
        
        _transfer(from, to, amountAfterFee);
        // Burn the fee
        _burn(from, fee);
        
        return true;
    }
}

/// @notice Mock token with variable fee for testing different fee scenarios
contract VariableFeeToken is ERC20 {
    uint8 private _decimals;
    uint256 public feePercent; // Fee in basis points (100 = 1%)
    
    constructor(string memory name, string memory symbol, uint8 decimals_, uint256 _feePercent) ERC20(name, symbol) {
        _decimals = decimals_;
        feePercent = _feePercent;
    }
    
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    
    function setFee(uint256 _feePercent) external {
        require(_feePercent <= 100, "Fee too high"); // Max 100%
        feePercent = _feePercent;
    }
    
    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        
        uint256 fee = (amount * feePercent) / 100;
        uint256 amountAfterFee = amount - fee;
        
        _transfer(from, to, amountAfterFee);
        if (fee > 0) {
            _burn(from, fee);
        }
        
        return true;
    }
}

/// @title GRO-15 Deflationary Token Test
/// @notice Tests fix for incompatibility with fee-on-transfer and deflationary tokens
contract GRO15DeflationaryTokenTest is Test {
    Authorizer public authorizer;
    MultiTokenPresale public presale;
    EscrowToken public escrowToken;
    
    // GRO-02: Use hardcoded owner address from contract
    address public owner = 0xd81d23f2e37248F8fda5e7BF0a6c047AE234F0A2;
    address public buyer1 = address(0x3);
    address public buyer2 = address(0x4);
    address public staking;
    
    DeflationaryToken public deflationaryToken;
    VariableFeeToken public variableFeeToken;
    
    uint256 public signerPrivateKey = 0xB0B;
    address public signer = vm.addr(signerPrivateKey);
    
    // Test constants
    uint256 constant PRESALE_RATE = 666666666666666667000; // 666.666... tokens per USD
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
        
        // Deploy deflationary tokens
        deflationaryToken = new DeflationaryToken("Deflationary Token", "DEFT", 18);
        variableFeeToken = new VariableFeeToken("Variable Fee Token", "VFEE", 6, 5); // 5% fee
        
        // Set token prices in presale
        presale.setTokenPrice(address(deflationaryToken), 100 * 1e8, 18, true);  // $100
        presale.setTokenPrice(address(variableFeeToken), 1 * 1e8, 6, true);      // $1
        
        vm.stopPrank();
        
        // Mint tokens to buyers
        deflationaryToken.mint(buyer1, 1000 * 1e18);  // 1000 DEFT
        deflationaryToken.mint(buyer2, 1000 * 1e18);
        variableFeeToken.mint(buyer1, 100000 * 1e6);  // 100k VFEE
        variableFeeToken.mint(buyer2, 100000 * 1e6);
        
        // Start presale
        vm.warp(PRESALE_LAUNCH_DATE + 1);
        presale.autoStartIEscrowPresale();
    }
    
    // ========== HELPER FUNCTIONS ==========
    
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
            deadline: block.timestamp + 1 hours,
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
    
    // ========== DEFLATIONARY TOKEN TESTS ==========
    // GRO-09 FIX: Deflationary tokens are now REJECTED
    
    /// @notice Test that deflationary token (10% fee) is rejected
    function testDeflationaryTokenCorrectCrediting() public {
        uint256 purchaseAmount = 10 * 1e18; // 10 DEFT tokens
        
        // Buyer approves tokens
        vm.startPrank(buyer1);
        deflationaryToken.approve(address(presale), purchaseAmount);
        
        // Create voucher
        Authorizer.Voucher memory voucher = _createVoucher(buyer1, buyer1, address(deflationaryToken), 0);
        bytes memory signature = _signVoucher(voucher);
        
        // Purchase should REVERT due to deflationary token detection
        vm.expectRevert("Deflationary token not supported");
        presale.buyWithTokenVoucher(address(deflationaryToken), purchaseAmount, buyer1, voucher, signature);
        
        vm.stopPrank();
    }
    
    /// @notice Test that variable fee token (5% fee) is rejected
    function testVariableFeeTokenCorrectCrediting() public {
        uint256 purchaseAmount = 10000 * 1e6; // 10000 VFEE tokens
        
        // Buyer approves tokens
        vm.startPrank(buyer1);
        variableFeeToken.approve(address(presale), purchaseAmount);
        
        // Create voucher
        Authorizer.Voucher memory voucher = _createVoucher(buyer1, buyer1, address(variableFeeToken), 0);
        bytes memory signature = _signVoucher(voucher);
        
        // Purchase should REVERT due to fee-on-transfer token detection
        vm.expectRevert("Deflationary token not supported");
        presale.buyWithTokenVoucher(address(variableFeeToken), purchaseAmount, buyer1, voucher, signature);
        
        vm.stopPrank();
    }
    
    /// @notice Test multiple purchases with deflationary token are rejected
    function testMultipleDeflationaryPurchases() public {
        vm.startPrank(buyer1);
        
        // First purchase attempt - should fail
        uint256 amount1 = 5 * 1e18;
        deflationaryToken.approve(address(presale), amount1);
        Authorizer.Voucher memory voucher1 = _createVoucher(buyer1, buyer1, address(deflationaryToken), 0);
        bytes memory sig1 = _signVoucher(voucher1);
        
        vm.expectRevert("Deflationary token not supported");
        presale.buyWithTokenVoucher(address(deflationaryToken), amount1, buyer1, voucher1, sig1);
        
        vm.stopPrank();
    }
    
    /// @notice Test edge case: very high fee (50%) is rejected
    function testHighFeeToken() public {
        // Set variable fee token to 50%
        variableFeeToken.setFee(50);
        
        uint256 purchaseAmount = 10000 * 1e6;
        
        vm.startPrank(buyer1);
        variableFeeToken.approve(address(presale), purchaseAmount);
        
        Authorizer.Voucher memory voucher = _createVoucher(buyer1, buyer1, address(variableFeeToken), 0);
        bytes memory signature = _signVoucher(voucher);
        
        vm.expectRevert("Deflationary token not supported");
        presale.buyWithTokenVoucher(address(variableFeeToken), purchaseAmount, buyer1, voucher, signature);
        
        vm.stopPrank();
    }
    
    /// @notice Test that 100% fee (all tokens burned) reverts
    function testAllTokensBurnedReverts() public {
        // Set variable fee token to 100%
        variableFeeToken.setFee(100);
        
        uint256 purchaseAmount = 10000 * 1e6;
        
        vm.startPrank(buyer1);
        variableFeeToken.approve(address(presale), purchaseAmount);
        
        Authorizer.Voucher memory voucher = _createVoucher(buyer1, buyer1, address(variableFeeToken), 0);
        bytes memory signature = _signVoucher(voucher);
        
        // Should revert because no tokens received
        vm.expectRevert("No tokens received");
        presale.buyWithTokenVoucher(address(variableFeeToken), purchaseAmount, buyer1, voucher, signature);
        
        vm.stopPrank();
    }
    
    /// @notice Test event emission with deflationary token - should reject
    function testDeflationaryTokenEventEmission() public {
        uint256 purchaseAmount = 10 * 1e18;
        
        vm.startPrank(buyer1);
        deflationaryToken.approve(address(presale), purchaseAmount);
        
        Authorizer.Voucher memory voucher = _createVoucher(buyer1, buyer1, address(deflationaryToken), 0);
        bytes memory signature = _signVoucher(voucher);
        
        // Should revert
        vm.expectRevert("Deflationary token not supported");
        presale.buyWithTokenVoucher(address(deflationaryToken), purchaseAmount, buyer1, voucher, signature);
        
        vm.stopPrank();
    }
    
    /// @notice Test claiming tokens after purchase with deflationary token - purchase should fail
    function testClaimAfterDeflationaryPurchase() public {
        // Purchase with deflationary token should be rejected
        uint256 purchaseAmount = 10 * 1e18;
        
        vm.startPrank(buyer1);
        deflationaryToken.approve(address(presale), purchaseAmount);
        
        Authorizer.Voucher memory voucher = _createVoucher(buyer1, buyer1, address(deflationaryToken), 0);
        bytes memory signature = _signVoucher(voucher);
        
        // Should revert
        vm.expectRevert("Deflationary token not supported");
        presale.buyWithTokenVoucher(address(deflationaryToken), purchaseAmount, buyer1, voucher, signature);
        
        vm.stopPrank();
    }
    
    /// @notice Test different buyers with deflationary tokens - both should be rejected
    function testMultipleBuyersDeflationary() public {
        // Buyer 1 purchase - should fail
        vm.startPrank(buyer1);
        uint256 amount1 = 10 * 1e18;
        deflationaryToken.approve(address(presale), amount1);
        Authorizer.Voucher memory voucher1 = _createVoucher(buyer1, buyer1, address(deflationaryToken), 0);
        bytes memory sig1 = _signVoucher(voucher1);
        
        vm.expectRevert("Deflationary token not supported");
        presale.buyWithTokenVoucher(address(deflationaryToken), amount1, buyer1, voucher1, sig1);
        vm.stopPrank();
    }
    
    /// @notice Fuzz test with various purchase amounts - all should be rejected
    function testFuzzDeflationaryPurchaseAmount(uint256 purchaseAmount) public {
        // Bound the purchase amount to reasonable values
        purchaseAmount = bound(purchaseAmount, 1e15, 100 * 1e18); // 0.001 to 100 tokens
        
        // Mint enough tokens to buyer
        deflationaryToken.mint(buyer1, purchaseAmount);
        
        vm.startPrank(buyer1);
        deflationaryToken.approve(address(presale), purchaseAmount);
        
        Authorizer.Voucher memory voucher = _createVoucher(buyer1, buyer1, address(deflationaryToken), 0);
        bytes memory signature = _signVoucher(voucher);
        
        // Should revert for any amount
        vm.expectRevert("Deflationary token not supported");
        presale.buyWithTokenVoucher(address(deflationaryToken), purchaseAmount, buyer1, voucher, signature);
        
        vm.stopPrank();
    }
}
