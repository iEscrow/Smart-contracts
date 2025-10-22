// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../Authorizer.sol";
import "../MultiTokenPresale.sol";
import "../EscrowToken.sol";

contract AuthorizerIntegrationTest is Test {
    Authorizer public authorizer;
    MultiTokenPresale public presale;
    EscrowToken public escrowToken;
    
    address public owner = address(0x1);
    address public buyer = address(0x3);
    address public beneficiary = address(0x4);
    address public unauthorized = address(0x5);
    
    uint256 public signerPrivateKey = 0xB0B;
    address public signer = vm.addr(signerPrivateKey); // Derive address from private key
    
    // Test constants
    uint256 constant PRESALE_RATE = 666666666666666666; // 666.666... tokens per USD
    uint256 constant MAX_TOKENS = 5000000000 * 1e18; // 5B tokens
    uint256 constant ETH_PRICE = 4200 * 1e8; // $4200
    uint256 constant VOUCHER_LIMIT = 10000 * 1e8; // $10000 limit
    uint256 constant DEADLINE = type(uint256).max; // No expiry for tests
    
    event VoucherConsumed(address indexed buyer, uint256 nonce, bytes32 voucherHash);
    event VoucherPurchase(
        address indexed purchaser,
        address indexed beneficiary,
        address indexed paymentToken,
        uint256 paymentAmount,
        uint256 tokenAmount,
        bytes32 voucherHash
    );
    
    function setUp() public {
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
        escrowToken.mint(address(presale), MAX_TOKENS);
        presale.updateAuthorizer(address(authorizer));
        presale.setVoucherSystemEnabled(true);
        
        // Start presale
        vm.warp(1762819200 + 1); // After launch date
        presale.autoStartIEscrowPresale();
        
        vm.stopPrank();
        
        // Set up buyer with ETH
        vm.deal(buyer, 100 ether);
    }
    
    function testValidVoucherPurchase() public {
        // Create valid voucher
        Authorizer.Voucher memory voucher = Authorizer.Voucher({
            buyer: buyer,
            beneficiary: beneficiary,
            paymentToken: address(0), // Native ETH
            usdLimit: VOUCHER_LIMIT,
            nonce: 0,
            deadline: DEADLINE,
            presale: address(presale)
        });
        
        bytes memory signature = _signVoucher(voucher, signerPrivateKey);
        uint256 purchaseAmount = 0.01 ether; // Smaller test amount
        
        // Expect events
        vm.expectEmit(true, true, false, true);
        emit VoucherConsumed(buyer, 0, _hashVoucher(voucher));
        
        // Make purchase
        vm.prank(buyer);
        presale.buyWithNativeVoucher{value: purchaseAmount}(beneficiary, voucher, signature);
        
        // Verify purchase was successful
        uint256 expectedTokens = _calculateExpectedTokens(purchaseAmount);
        assertEq(presale.totalPurchased(beneficiary), expectedTokens);
        assertEq(authorizer.nonces(buyer), 1);
        assertTrue(authorizer.isVoucherConsumed(_hashVoucher(voucher)));
    }
    
    function testVoucherReplayPrevention() public {
        // Create and use voucher
        Authorizer.Voucher memory voucher = Authorizer.Voucher({
            buyer: buyer,
            beneficiary: beneficiary,
            paymentToken: address(0),
            usdLimit: VOUCHER_LIMIT,
            nonce: 0,
            deadline: DEADLINE,
            presale: address(presale)
        });
        
        bytes memory signature = _signVoucher(voucher, signerPrivateKey);
        uint256 purchaseAmount = 0.01 ether;
        
        // First purchase should succeed
        vm.prank(buyer);
        presale.buyWithNativeVoucher{value: purchaseAmount}(beneficiary, voucher, signature);
        
        // Second purchase with same voucher should fail (InvalidNonce since nonce incremented)
        vm.expectRevert(Authorizer.InvalidNonce.selector);
        vm.prank(buyer);
        presale.buyWithNativeVoucher{value: purchaseAmount}(beneficiary, voucher, signature);
    }
    
    function testExpiredVoucher() public {
        uint256 expiredDeadline = block.timestamp - 1;
        
        Authorizer.Voucher memory voucher = Authorizer.Voucher({
            buyer: buyer,
            beneficiary: beneficiary,
            paymentToken: address(0),
            usdLimit: VOUCHER_LIMIT,
            nonce: 0,
            deadline: expiredDeadline,
            presale: address(presale)
        });
        
        bytes memory signature = _signVoucher(voucher, signerPrivateKey);
        
        vm.expectRevert(Authorizer.VoucherExpired.selector);
        vm.prank(buyer);
        presale.buyWithNativeVoucher{value: 1 ether}(beneficiary, voucher, signature);
    }
    
    function testInvalidSigner() public {
        Authorizer.Voucher memory voucher = Authorizer.Voucher({
            buyer: buyer,
            beneficiary: beneficiary,
            paymentToken: address(0),
            usdLimit: VOUCHER_LIMIT,
            nonce: 0,
            deadline: DEADLINE,
            presale: address(presale)
        });
        
        // Sign with wrong private key
        uint256 wrongPrivateKey = 0xDEAD;
        bytes memory signature = _signVoucher(voucher, wrongPrivateKey);
        
        vm.expectRevert(Authorizer.InvalidSignature.selector);
        vm.prank(buyer);
        presale.buyWithNativeVoucher{value: 1 ether}(beneficiary, voucher, signature);
    }
    
    function testWrongPresaleAddress() public {
        address wrongPresale = address(0x999);
        
        Authorizer.Voucher memory voucher = Authorizer.Voucher({
            buyer: buyer,
            beneficiary: beneficiary,
            paymentToken: address(0),
            usdLimit: VOUCHER_LIMIT,
            nonce: 0,
            deadline: DEADLINE,
            presale: wrongPresale
        });
        
        bytes memory signature = _signVoucher(voucher, signerPrivateKey);
        
        vm.expectRevert(Authorizer.InvalidPresaleAddress.selector);
        vm.prank(buyer);
        presale.buyWithNativeVoucher{value: 1 ether}(beneficiary, voucher, signature);
    }
    
    function testWrongPaymentToken() public {
        address wrongToken = address(0x888);
        
        Authorizer.Voucher memory voucher = Authorizer.Voucher({
            buyer: buyer,
            beneficiary: beneficiary,
            paymentToken: wrongToken,
            usdLimit: VOUCHER_LIMIT,
            nonce: 0,
            deadline: DEADLINE,
            presale: address(presale)
        });
        
        bytes memory signature = _signVoucher(voucher, signerPrivateKey);
        
        vm.expectRevert("Invalid payment token");
        vm.prank(buyer);
        presale.buyWithNativeVoucher{value: 1 ether}(beneficiary, voucher, signature);
    }
    
    function testExceedsUSDLimit() public {
        uint256 lowLimit = 100 * 1e8; // $100 limit
        
        Authorizer.Voucher memory voucher = Authorizer.Voucher({
            buyer: buyer,
            beneficiary: beneficiary,
            paymentToken: address(0),
            usdLimit: lowLimit,
            nonce: 0,
            deadline: DEADLINE,
            presale: address(presale)
        });
        
        bytes memory signature = _signVoucher(voucher, signerPrivateKey);
        
        // Try to purchase $4200 worth (1 ETH at $4200/ETH)
        vm.expectRevert(Authorizer.InsufficientLimit.selector);
        vm.prank(buyer);
        presale.buyWithNativeVoucher{value: 1 ether}(beneficiary, voucher, signature);
    }
    
    function testWrongNonce() public {
        Authorizer.Voucher memory voucher = Authorizer.Voucher({
            buyer: buyer,
            beneficiary: beneficiary,
            paymentToken: address(0),
            usdLimit: VOUCHER_LIMIT,
            nonce: 5, // Wrong nonce (should be 0)
            deadline: DEADLINE,
            presale: address(presale)
        });
        
        bytes memory signature = _signVoucher(voucher, signerPrivateKey);
        
        vm.expectRevert(Authorizer.InvalidNonce.selector);
        vm.prank(buyer);
        presale.buyWithNativeVoucher{value: 1 ether}(beneficiary, voucher, signature);
    }
    
    function testUnauthorizedBuyerCantUseVoucher() public {
        Authorizer.Voucher memory voucher = Authorizer.Voucher({
            buyer: buyer,
            beneficiary: beneficiary,
            paymentToken: address(0),
            usdLimit: VOUCHER_LIMIT,
            nonce: 0,
            deadline: DEADLINE,
            presale: address(presale)
        });
        
        bytes memory signature = _signVoucher(voucher, signerPrivateKey);
        
        // Unauthorized user tries to use buyer's voucher
        vm.deal(unauthorized, 10 ether);
        vm.expectRevert("Only buyer can use voucher");
        vm.prank(unauthorized);
        presale.buyWithNativeVoucher{value: 1 ether}(beneficiary, voucher, signature);
    }
    
    function testBeneficiaryMismatch() public {
        address wrongBeneficiary = address(0x777);
        
        Authorizer.Voucher memory voucher = Authorizer.Voucher({
            buyer: buyer,
            beneficiary: beneficiary,
            paymentToken: address(0),
            usdLimit: VOUCHER_LIMIT,
            nonce: 0,
            deadline: DEADLINE,
            presale: address(presale)
        });
        
        bytes memory signature = _signVoucher(voucher, signerPrivateKey);
        
        vm.expectRevert("Beneficiary mismatch");
        vm.prank(buyer);
        presale.buyWithNativeVoucher{value: 1 ether}(wrongBeneficiary, voucher, signature);
    }
    
    function testVoucherSystemDisabled() public {
        // Disable voucher system
        vm.prank(owner);
        presale.setVoucherSystemEnabled(false);
        
        Authorizer.Voucher memory voucher = Authorizer.Voucher({
            buyer: buyer,
            beneficiary: beneficiary,
            paymentToken: address(0),
            usdLimit: VOUCHER_LIMIT,
            nonce: 0,
            deadline: DEADLINE,
            presale: address(presale)
        });
        
        bytes memory signature = _signVoucher(voucher, signerPrivateKey);
        
        vm.expectRevert("Voucher system not enabled");
        vm.prank(buyer);
        presale.buyWithNativeVoucher{value: 1 ether}(beneficiary, voucher, signature);
    }
    
    function testSequentialVoucherUsage() public {
        uint256 purchaseAmount = 0.001 ether; // Very small amount
        
        // First voucher (nonce 0)
        Authorizer.Voucher memory voucher1 = Authorizer.Voucher({
            buyer: buyer,
            beneficiary: beneficiary,
            paymentToken: address(0),
            usdLimit: VOUCHER_LIMIT,
            nonce: 0,
            deadline: DEADLINE,
            presale: address(presale)
        });
        
        bytes memory signature1 = _signVoucher(voucher1, signerPrivateKey);
        
        vm.prank(buyer);
        presale.buyWithNativeVoucher{value: purchaseAmount}(beneficiary, voucher1, signature1);
        
        // Verify nonce incremented
        assertEq(authorizer.nonces(buyer), 1);
        
        // Second voucher (nonce 1)
        Authorizer.Voucher memory voucher2 = Authorizer.Voucher({
            buyer: buyer,
            beneficiary: beneficiary,
            paymentToken: address(0),
            usdLimit: VOUCHER_LIMIT,
            nonce: 1,
            deadline: DEADLINE,
            presale: address(presale)
        });
        
        bytes memory signature2 = _signVoucher(voucher2, signerPrivateKey);
        
        vm.prank(buyer);
        presale.buyWithNativeVoucher{value: purchaseAmount}(beneficiary, voucher2, signature2);
        
        // Verify second purchase
        assertEq(authorizer.nonces(buyer), 2);
        uint256 expectedTotalTokens = _calculateExpectedTokens(purchaseAmount) * 2;
        assertEq(presale.totalPurchased(beneficiary), expectedTotalTokens);
    }
    
    function testValidateVoucherView() public {
        Authorizer.Voucher memory voucher = Authorizer.Voucher({
            buyer: buyer,
            beneficiary: beneficiary,
            paymentToken: address(0),
            usdLimit: VOUCHER_LIMIT,
            nonce: 0,
            deadline: DEADLINE,
            presale: address(presale)
        });
        
        bytes memory signature = _signVoucher(voucher, signerPrivateKey);
        uint256 purchaseAmount = 0.01 ether;
        uint256 usdAmount = (purchaseAmount * ETH_PRICE) / 1e18;
        
        (bool valid, string memory reason) = presale.validateVoucher(voucher, signature, address(0), usdAmount);
        assertTrue(valid);
        assertEq(reason, "");
    }
    
    function testAdminFunctions() public {
        vm.startPrank(owner);
        
        // Test updating authorizer
        Authorizer newAuthorizer = new Authorizer(signer, owner);
        presale.updateAuthorizer(address(newAuthorizer));
        (address authAddress, bool enabled) = presale.getAuthorizerInfo();
        assertEq(authAddress, address(newAuthorizer));
        
        // Test toggling voucher system
        presale.setVoucherSystemEnabled(false);
        (, enabled) = presale.getAuthorizerInfo();
        assertFalse(enabled);
        
        presale.setVoucherSystemEnabled(true);
        (, enabled) = presale.getAuthorizerInfo();
        assertTrue(enabled);
        
        vm.stopPrank();
    }
    
    // Helper functions
    function _signVoucher(Authorizer.Voucher memory voucher, uint256 privateKey) internal view returns (bytes memory) {
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
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
    
    function _hashVoucher(Authorizer.Voucher memory voucher) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            keccak256("Voucher(address buyer,address beneficiary,address paymentToken,uint256 usdLimit,uint256 nonce,uint256 deadline,address presale)"),
            voucher.buyer,
            voucher.beneficiary,
            voucher.paymentToken,
            voucher.usdLimit,
            voucher.nonce,
            voucher.deadline,
            voucher.presale
        ));
    }
    
    function _calculateExpectedTokens(uint256 ethAmount) internal view returns (uint256) {
        // Subtract estimated gas cost
        uint256 gasCost = 21000 * tx.gasprice * 120 / 100; // 20% buffer
        uint256 paymentAmount = ethAmount - gasCost;
        
        // Convert to USD (ETH price is $4200 with 8 decimals, ETH has 18 decimals)
        uint256 usdValue = (paymentAmount * ETH_PRICE) / 1e18;
        
        // Calculate tokens (presale rate has 18 decimals for tokens per USD)
        return usdValue * PRESALE_RATE;
    }
}