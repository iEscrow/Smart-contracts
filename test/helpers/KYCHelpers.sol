// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../KYCVerification.sol";

/// @title KYCHelpers
/// @notice Helper functions and utilities for comprehensive KYC testing
contract KYCHelpers is Test {
    
    // Standard private keys for testing
    uint256 public constant SIGNER_PRIVATE_KEY = 0x1234567890123456789012345678901234567890123456789012345678901234;
    uint256 public constant USER_PRIVATE_KEY = 0x9876543210987654321098765432109876543210987654321098765432109876;
    
    address public signerAddress;
    address public userAddress;
    
    KYCVerification public kycContract;
    
    constructor() {
        // Derive addresses from private keys
        signerAddress = vm.addr(SIGNER_PRIVATE_KEY);
        userAddress = vm.addr(USER_PRIVATE_KEY);
    }
    
    /// @notice Deploy a fresh KYC contract for testing
    /// @param _signerAddress Address to use as KYC signer (optional, uses default if zero)
    /// @return KYCVerification The deployed contract
    function deployKYCContract(address _signerAddress) public returns (KYCVerification) {
        address signer = _signerAddress == address(0) ? signerAddress : _signerAddress;
        kycContract = new KYCVerification(signer);
        return kycContract;
    }
    
    /// @notice Generate EIP712 signature for KYC data
    /// @param privateKey Private key to sign with
    /// @param user User address
    /// @param verified Verification status
    /// @param expiryTimestamp Expiry timestamp
    /// @param nonce Nonce for replay protection
    /// @param contractAddress KYC contract address for domain separator
    /// @return signature The generated signature bytes
    function signKYCData(
        uint256 privateKey,
        address user,
        bool verified,
        uint256 expiryTimestamp,
        uint256 nonce,
        address contractAddress
    ) public view returns (bytes memory signature) {
        bytes32 digest = _buildDigest(user, verified, expiryTimestamp, nonce, contractAddress);
        
        // Sign the digest
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        signature = abi.encodePacked(r, s, v);
    }
    
    /// @notice Internal function to build EIP712 digest
    function _buildDigest(
        address user,
        bool verified,
        uint256 expiryTimestamp,
        uint256 nonce,
        address contractAddress
    ) internal view returns (bytes32) {
        // EIP712 domain separator components
        bytes32 DOMAIN_TYPEHASH = keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
        
        bytes32 KYC_TYPEHASH = keccak256(
            "KYCData(address user,bool verified,uint256 expiryTimestamp,uint256 nonce)"
        );
        
        // Build domain separator
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes("KYCVerification")),
                keccak256(bytes("1")),
                block.chainid,
                contractAddress
            )
        );
        
        // Build struct hash
        bytes32 structHash = keccak256(
            abi.encode(KYC_TYPEHASH, user, verified, expiryTimestamp, nonce)
        );
        
        // Build final hash
        return keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );
    }
    
    /// @notice Generate a valid KYC signature using the default signer
    /// @param user User address to verify
    /// @param verified Verification status
    /// @param expiryTimestamp Expiry timestamp
    /// @param nonce Nonce for replay protection
    /// @param contractAddress KYC contract address
    /// @return signature The generated signature
    function generateValidSignature(
        address user,
        bool verified,
        uint256 expiryTimestamp,
        uint256 nonce,
        address contractAddress
    ) public view returns (bytes memory signature) {
        return signKYCData(
            SIGNER_PRIVATE_KEY,
            user,
            verified,
            expiryTimestamp,
            nonce,
            contractAddress
        );
    }
    
    /// @notice Generate an invalid signature using wrong private key
    /// @param user User address to verify
    /// @param verified Verification status
    /// @param expiryTimestamp Expiry timestamp
    /// @param nonce Nonce for replay protection
    /// @param contractAddress KYC contract address
    /// @return signature The generated signature
    function generateInvalidSignature(
        address user,
        bool verified,
        uint256 expiryTimestamp,
        uint256 nonce,
        address contractAddress
    ) public view returns (bytes memory signature) {
        return signKYCData(
            USER_PRIVATE_KEY, // Wrong key
            user,
            verified,
            expiryTimestamp,
            nonce,
            contractAddress
        );
    }
    
    /// @notice Setup test users with addresses and labels
    /// @param numUsers Number of users to create
    /// @return users Array of user addresses
    function setupTestUsers(uint256 numUsers) public returns (address[] memory users) {
        users = new address[](numUsers);
        
        for (uint256 i = 0; i < numUsers; i++) {
            users[i] = makeAddr(string(abi.encodePacked("user", i)));
            vm.deal(users[i], 1 ether); // Give some ETH for gas
        }
        
        return users;
    }
    
    /// @notice Verify KYC data matches expected values
    /// @param kyc KYC contract instance
    /// @param user User address to check
    /// @param expectedVerified Expected verification status
    /// @param expectedExpiry Expected expiry timestamp
    /// @param expectedNonce Expected nonce value
    function verifyKYCData(
        KYCVerification kyc,
        address user,
        bool expectedVerified,
        uint256 expectedExpiry,
        uint256 expectedNonce
    ) public view {
        assertEq(kyc.isVerified(user), expectedVerified, "Verification status mismatch");
        assertEq(kyc.kycExpiry(user), expectedExpiry, "Expiry timestamp mismatch");
        assertEq(kyc.nonces(user), expectedNonce, "Nonce mismatch");
    }
    
    /// @notice Test complete KYC verification flow
    /// @param kyc KYC contract instance
    /// @param user User to verify
    /// @param expiryOffset Offset from current time for expiry
    /// @return nonce The nonce used
    function performValidKYCVerification(
        KYCVerification kyc,
        address user,
        uint256 expiryOffset
    ) public returns (uint256 nonce) {
        nonce = kyc.nonces(user) + 1;
        uint256 expiryTimestamp = block.timestamp + expiryOffset;
        
        bytes memory signature = generateValidSignature(
            user,
            true,
            expiryTimestamp,
            nonce,
            address(kyc)
        );
        
        vm.prank(user);
        kyc.verifyKYC(user, true, expiryTimestamp, nonce, signature);
        
        // Verify state
        verifyKYCData(kyc, user, true, expiryTimestamp, nonce);
        assertTrue(kyc.isCurrentlyVerified(user), "User should be currently verified");
        
        return nonce;
    }
    
    /// @notice Simulate time passage to test expiry
    /// @param kyc KYC contract instance
    /// @param user User to check
    /// @param timeOffset Time to advance
    function advanceTimeAndCheckExpiry(
        KYCVerification kyc,
        address user,
        uint256 timeOffset
    ) public {
        uint256 originalExpiry = kyc.kycExpiry(user);
        vm.warp(block.timestamp + timeOffset);
        
        bool shouldBeExpired = block.timestamp > originalExpiry;
        assertEq(
            kyc.isCurrentlyVerified(user),
            !shouldBeExpired,
            shouldBeExpired ? "User should be expired" : "User should not be expired"
        );
    }
    
    /// @notice Test replay attack by attempting to reuse signature
    /// @param kyc KYC contract instance
    /// @param user User address
    /// @param originalNonce Nonce that was already used
    /// @param originalExpiry Original expiry timestamp
    /// @param signature Original signature to replay
    function testReplayAttack(
        KYCVerification kyc,
        address user,
        uint256 originalNonce,
        uint256 originalExpiry,
        bytes memory signature
    ) internal {
        vm.expectRevert(KYCVerification.InvalidNonce.selector);
        vm.prank(user);
        kyc.verifyKYC(user, true, originalExpiry, originalNonce, signature);
    }
    
    /// @notice Test unauthorized access to admin functions
    /// @param kyc KYC contract instance
    /// @param unauthorizedUser Address that should not have admin access
    function testUnauthorizedAccess(
        KYCVerification kyc,
        address unauthorizedUser
    ) internal {
        // Test updateSigner
        vm.expectRevert();
        vm.prank(unauthorizedUser);
        kyc.updateSigner(makeAddr("newSigner"));
        
        // Test revokeKYC
        vm.expectRevert();
        vm.prank(unauthorizedUser);
        kyc.revokeKYC(unauthorizedUser);
        
        // Test updateValidityPeriod
        vm.expectRevert();
        vm.prank(unauthorizedUser);
        kyc.updateValidityPeriod(180 days);
    }
    
    /// @notice Mass verification test with multiple users
    /// @param kyc KYC contract instance
    /// @param users Array of users to verify
    /// @param staggerExpiry Whether to stagger expiry times
    function massVerifyUsers(
        KYCVerification kyc,
        address[] memory users,
        bool staggerExpiry
    ) public {
        for (uint256 i = 0; i < users.length; i++) {
            uint256 expiryOffset = staggerExpiry ? 
                365 days + (i * 30 days) : // Stagger by months
                365 days; // All expire at same time
                
            performValidKYCVerification(kyc, users[i], expiryOffset);
        }
        
        // Verify all users are verified
        for (uint256 i = 0; i < users.length; i++) {
            assertTrue(kyc.isCurrentlyVerified(users[i]), "Mass verification failed");
        }
    }
    
    /// @notice Generate test data for edge case testing
    /// @param user User address
    /// @param contractAddress Contract address
    /// @return pastTimestamp Past timestamp for testing
    /// @return currentTimestamp Current timestamp
    /// @return futureTimestamp Future timestamp
    /// @return maxTimestamp Maximum possible timestamp
    /// @return validSig Valid signature for testing
    /// @return invalidSig Invalid signature for testing
    function generateEdgeCaseTestData(
        address user,
        address contractAddress
    ) public view returns (
        uint256 pastTimestamp,
        uint256 currentTimestamp,
        uint256 futureTimestamp,
        uint256 maxTimestamp,
        bytes memory validSig,
        bytes memory invalidSig
    ) {
        pastTimestamp = block.timestamp > 1 days ? block.timestamp - 1 days : 1;
        currentTimestamp = block.timestamp;
        futureTimestamp = block.timestamp + 365 days;
        maxTimestamp = type(uint256).max;
        
        validSig = generateValidSignature(
            user,
            true,
            futureTimestamp,
            1,
            contractAddress
        );
        
        invalidSig = generateInvalidSignature(
            user,
            true,
            futureTimestamp,
            1,
            contractAddress
        );
    }
}