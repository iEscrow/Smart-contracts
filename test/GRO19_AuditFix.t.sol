// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../MultiTokenPresale.sol";
import "../EscrowToken.sol";
import "../Authorizer.sol";

/// @title GRO-19 Audit Fix Tests
/// @notice Tests for in-contract replay protection as defense-in-depth
contract GRO19_AuditFixTest is Test {
    MultiTokenPresale public presale;
    EscrowToken public escrowToken;
    Authorizer public authorizer;
    
    // GRO-02: Use hardcoded owner address from contract
    address public owner = 0xd81d23f2e37248F8fda5e7BF0a6c047AE234F0A2;
    address public user1 = address(0x2);
    address public treasury = address(0x4);
    address public staking = address(0x5);
    
    uint256 public signerPrivateKey = 0xB0B;
    address public signer = vm.addr(signerPrivateKey);
    
    uint256 public constant PRESALE_RATE = 666666666666666667000; // 666.67 tokens per USD
    uint256 public constant MAX_TOKENS = 5000000000 * 1e18; // 5B tokens
    uint256 public constant LAUNCH_DATE = 1762819200; // Nov 11, 2025
    
    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy EscrowToken
        escrowToken = new EscrowToken();
        
        // Deploy Authorizer
        authorizer = new Authorizer(signer, owner);
        
        // Deploy MultiTokenPresale
        presale = new MultiTokenPresale(
            address(escrowToken),
            PRESALE_RATE,
            MAX_TOKENS
        );
        
        // Setup authorizer
        presale.updateAuthorizer(address(authorizer));
        presale.setVoucherSystemEnabled(true);
        
        // Mint presale allocation to presale contract
        escrowToken.mintPresaleAllocation(address(presale), staking);
        
        vm.stopPrank();
        
        // Give user1 some ETH
        vm.deal(user1, 100 ether);
    }
    
    function _startPresale() internal {
        vm.warp(LAUNCH_DATE + 1);
        presale.autoStartIEscrowPresale();
    }
    
    /// @notice Test that in-contract replay protection prevents reusing a voucher
    function testCannotReuseVoucherInContract() public {
        _startPresale();
        
        // Create voucher
        Authorizer.Voucher memory voucher = Authorizer.Voucher({
            buyer: user1,
            beneficiary: user1,
            paymentToken: address(0), // Native ETH
            usdLimit: 1000 * 1e8, // $1000
            nonce: 0,
            deadline: block.timestamp + 1 hours,
            presale: address(presale)
        });
        
        bytes memory signature = _signVoucher(voucher, signerPrivateKey);
        
        // First purchase should succeed
        vm.prank(user1);
        presale.buyWithNativeVoucher{value: 0.1 ether}(user1, voucher, signature);
        
        // Verify purchase succeeded
        assertGt(presale.totalPurchased(user1), 0);
        
        // Try to reuse the same voucher - should fail with in-contract check
        vm.prank(user1);
        vm.expectRevert("Voucher already used in this contract");
        presale.buyWithNativeVoucher{value: 0.1 ether}(user1, voucher, signature);
    }
    
    /// @notice Test that voucher hash is properly tracked
    function testVoucherHashTracking() public {
        _startPresale();
        
        // Create voucher
        Authorizer.Voucher memory voucher = Authorizer.Voucher({
            buyer: user1,
            beneficiary: user1,
            paymentToken: address(0),
            usdLimit: 1000 * 1e8,
            nonce: 0,
            deadline: block.timestamp + 1 hours,
            presale: address(presale)
        });
        
        // Compute expected voucher hash
        bytes32 expectedHash = keccak256(abi.encode(
            voucher.buyer,
            voucher.beneficiary,
            voucher.paymentToken,
            voucher.usdLimit,
            voucher.nonce,
            voucher.deadline,
            voucher.presale
        ));
        
        // Verify voucher is not used yet
        assertFalse(presale.isVoucherUsed(expectedHash));
        
        bytes memory signature = _signVoucher(voucher, signerPrivateKey);
        
        // Make purchase
        vm.prank(user1);
        presale.buyWithNativeVoucher{value: 0.1 ether}(user1, voucher, signature);
        
        // Verify voucher is now marked as used
        assertTrue(presale.isVoucherUsed(expectedHash));
    }
    
    /// @notice Test that VoucherHashConsumed event is emitted
    function testVoucherHashConsumedEvent() public {
        _startPresale();
        
        Authorizer.Voucher memory voucher = Authorizer.Voucher({
            buyer: user1,
            beneficiary: user1,
            paymentToken: address(0),
            usdLimit: 1000 * 1e8,
            nonce: 0,
            deadline: block.timestamp + 1 hours,
            presale: address(presale)
        });
        
        bytes32 expectedHash = keccak256(abi.encode(
            voucher.buyer,
            voucher.beneficiary,
            voucher.paymentToken,
            voucher.usdLimit,
            voucher.nonce,
            voucher.deadline,
            voucher.presale
        ));
        
        bytes memory signature = _signVoucher(voucher, signerPrivateKey);
        
        // Expect VoucherHashConsumed event
        vm.expectEmit(true, true, false, false);
        emit VoucherHashConsumed(expectedHash, user1);
        
        vm.prank(user1);
        presale.buyWithNativeVoucher{value: 0.1 ether}(user1, voucher, signature);
    }
    
    /// @notice Test that different vouchers have different hashes
    function testDifferentVouchersHaveDifferentHashes() public {
        _startPresale();
        
        // Create first voucher
        Authorizer.Voucher memory voucher1 = Authorizer.Voucher({
            buyer: user1,
            beneficiary: user1,
            paymentToken: address(0),
            usdLimit: 1000 * 1e8,
            nonce: 0,
            deadline: block.timestamp + 1 hours,
            presale: address(presale)
        });
        
        // Create second voucher with different nonce
        Authorizer.Voucher memory voucher2 = Authorizer.Voucher({
            buyer: user1,
            beneficiary: user1,
            paymentToken: address(0),
            usdLimit: 1000 * 1e8,
            nonce: 1, // Different nonce
            deadline: block.timestamp + 1 hours,
            presale: address(presale)
        });
        
        bytes32 hash1 = keccak256(abi.encode(
            voucher1.buyer,
            voucher1.beneficiary,
            voucher1.paymentToken,
            voucher1.usdLimit,
            voucher1.nonce,
            voucher1.deadline,
            voucher1.presale
        ));
        
        bytes32 hash2 = keccak256(abi.encode(
            voucher2.buyer,
            voucher2.beneficiary,
            voucher2.paymentToken,
            voucher2.usdLimit,
            voucher2.nonce,
            voucher2.deadline,
            voucher2.presale
        ));
        
        // Hashes should be different
        assertTrue(hash1 != hash2);
        
        bytes memory signature1 = _signVoucher(voucher1, signerPrivateKey);
        bytes memory signature2 = _signVoucher(voucher2, signerPrivateKey);
        
        // First purchase
        vm.prank(user1);
        presale.buyWithNativeVoucher{value: 0.1 ether}(user1, voucher1, signature1);
        
        // Second purchase with different voucher should succeed
        vm.prank(user1);
        presale.buyWithNativeVoucher{value: 0.1 ether}(user1, voucher2, signature2);
        
        // Both voucher hashes should be marked as used
        assertTrue(presale.isVoucherUsed(hash1));
        assertTrue(presale.isVoucherUsed(hash2));
    }
    
    /// @notice Test replay protection works for ERC20 token purchases too
    function testReplayProtectionForTokenPurchase() public {
        // Deploy mock USDC
        MockERC20 usdc = new MockERC20("USDC", "USDC", 6);
        usdc.mint(user1, 10000 * 1e6); // 10,000 USDC
        
        // Setup USDC as accepted token BEFORE starting presale
        vm.prank(owner);
        presale.setTokenPrice(address(usdc), 1 * 1e8, 6, true);
        
        // Now start presale
        _startPresale();
        
        // Create voucher for USDC
        Authorizer.Voucher memory voucher = Authorizer.Voucher({
            buyer: user1,
            beneficiary: user1,
            paymentToken: address(usdc),
            usdLimit: 1000 * 1e8,
            nonce: 0,
            deadline: block.timestamp + 1 hours,
            presale: address(presale)
        });
        
        bytes memory signature = _signVoucher(voucher, signerPrivateKey);
        
        // Approve tokens
        vm.prank(user1);
        usdc.approve(address(presale), 1000 * 1e6);
        
        // First purchase should succeed
        vm.prank(user1);
        presale.buyWithTokenVoucher(address(usdc), 100 * 1e6, user1, voucher, signature);
        
        // Approve more tokens for second attempt
        vm.prank(user1);
        usdc.approve(address(presale), 1000 * 1e6);
        
        // Try to reuse the same voucher - should fail
        vm.prank(user1);
        vm.expectRevert("Voucher already used in this contract");
        presale.buyWithTokenVoucher(address(usdc), 100 * 1e6, user1, voucher, signature);
    }
    
    /// @notice Test that in-contract protection works even if external Authorizer is compromised
    /// This is a conceptual test - we simulate a broken Authorizer by replacing it
    function testProtectionEvenWithBrokenAuthorizer() public {
        _startPresale();
        
        // Create a broken authorizer that always returns true without proper checks
        BrokenAuthorizer brokenAuth = new BrokenAuthorizer(signer, owner);
        
        // Use a voucher first with the good authorizer
        Authorizer.Voucher memory voucher = Authorizer.Voucher({
            buyer: user1,
            beneficiary: user1,
            paymentToken: address(0),
            usdLimit: 1000 * 1e8,
            nonce: 0,
            deadline: block.timestamp + 1 hours,
            presale: address(presale)
        });
        
        bytes memory signature = _signVoucher(voucher, signerPrivateKey);
        
        // First purchase with good authorizer
        vm.prank(user1);
        presale.buyWithNativeVoucher{value: 0.1 ether}(user1, voucher, signature);
        
        // Now replace with broken authorizer
        vm.prank(owner);
        presale.updateAuthorizer(address(brokenAuth));
        
        // Even though the broken authorizer doesn't check for replays,
        // the in-contract check should still prevent reuse
        vm.prank(user1);
        vm.expectRevert("Voucher already used in this contract");
        presale.buyWithNativeVoucher{value: 0.1 ether}(user1, voucher, signature);
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
    
    event VoucherHashConsumed(bytes32 indexed voucherHash, address indexed buyer);
}

/// @notice Mock ERC20 token for testing
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    
    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

/// @notice Broken Authorizer that doesn't properly check for replays (for testing)
contract BrokenAuthorizer {
    address public signer;
    address public owner;
    
    mapping(address => uint256) public nonces;
    
    constructor(address _signer, address _owner) {
        signer = _signer;
        owner = _owner;
    }
    
    struct Voucher {
        address buyer;
        address beneficiary;
        address paymentToken;
        uint256 usdLimit;
        uint256 nonce;
        uint256 deadline;
        address presale;
    }
    
    // This broken implementation always returns true without proper checks
    function authorize(
        Voucher calldata /* voucher */,
        bytes calldata /* signature */,
        address /* paymentToken */,
        uint256 /* usdAmount */
    ) external pure returns (bool) {
        // Intentionally broken - no replay protection!
        return true;
    }
    
    function validateVoucher(
        Voucher calldata /* voucher */,
        bytes calldata /* signature */,
        address /* paymentToken */,
        uint256 /* usdAmount */
    ) external pure returns (bool, string memory) {
        return (true, "");
    }
}
