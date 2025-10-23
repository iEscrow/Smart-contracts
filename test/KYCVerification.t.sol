// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@forge-std/Test.sol";
import "@forge-std/console.sol";
import "../KYCVerification.sol";
import "./helpers/KYCHelpers.sol";

/// @title KYCVerificationTest
/// @notice Comprehensive test suite for KYC verification contract
contract KYCVerificationTest is Test, KYCHelpers {
    
    KYCVerification public kyc;
    
    address public owner;
    address public signer;
    address public user1;
    address public user2;
    address public user3;
    address public attacker;
    
    // Test events
    event UserVerified(address indexed user, bool verified, uint256 expiryTimestamp);
    event SignerUpdated(address indexed oldSigner, address indexed newSigner);
    event ValidityPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);
    event KYCRevoked(address indexed user);
    
    function setUp() public {
        console.log("=== KYC Verification Test Setup ===");
        
        // Set up addresses
        owner = address(this);
        signer = signerAddress;
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        attacker = makeAddr("attacker");
        
        // Deploy KYC contract
        kyc = deployKYCContract(signer);
        
        console.log("KYC contract deployed at:", address(kyc));
        console.log("Signer address:", signer);
        console.log("Owner address:", owner);
        
        // Give users some ETH for gas
        vm.deal(user1, 1 ether);
        vm.deal(user2, 1 ether);
        vm.deal(user3, 1 ether);
        vm.deal(attacker, 1 ether);
    }
    
    /// @notice Test basic contract deployment and initial state
    function test_Deployment() public {
        assertEq(kyc.kycSigner(), signer, "Signer address incorrect");
        assertEq(kyc.owner(), owner, "Owner address incorrect");
        assertEq(kyc.kycValidityPeriod(), 365 days, "Default validity period incorrect");
        
        // Test initial state for a user
        assertFalse(kyc.isVerified(user1), "User should not be verified initially");
        assertFalse(kyc.isCurrentlyVerified(user1), "User should not be currently verified");
        assertEq(kyc.kycExpiry(user1), 0, "Expiry should be 0 initially");
        assertEq(kyc.nonces(user1), 0, "Nonce should be 0 initially");
        
        console.log("[PASS] Deployment test passed");
    }
    
    /// @notice Test invalid signer in constructor
    function test_DeploymentWithInvalidSigner() public {
        vm.expectRevert(KYCVerification.InvalidSigner.selector);
        new KYCVerification(address(0));
        
        console.log("[PASS] Invalid signer deployment test passed");
    }
    
    /// @notice Test successful KYC verification
    function test_SuccessfulKYCVerification() public {
        uint256 nonce = 1;
        uint256 expiryTimestamp = block.timestamp + 365 days;
        
        bytes memory signature = generateValidSignature(
            user1,
            true,
            expiryTimestamp,
            nonce,
            address(kyc)
        );
        
        // Expect event emission
        vm.expectEmit(true, true, true, true);
        emit UserVerified(user1, true, expiryTimestamp);
        
        vm.prank(user1);
        kyc.verifyKYC(user1, true, expiryTimestamp, nonce, signature);
        
        // Verify state changes
        assertTrue(kyc.isVerified(user1), "User should be verified");
        assertTrue(kyc.isCurrentlyVerified(user1), "User should be currently verified");
        assertEq(kyc.kycExpiry(user1), expiryTimestamp, "Expiry timestamp incorrect");
        assertEq(kyc.nonces(user1), nonce, "Nonce not updated");
        
        console.log("[PASS] Successful KYC verification test passed");
    }
    
    /// @notice Test KYC verification with invalid signature
    function test_InvalidSignature() public {
        uint256 nonce = 1;
        uint256 expiryTimestamp = block.timestamp + 365 days;
        
        bytes memory invalidSignature = generateInvalidSignature(
            user1,
            true,
            expiryTimestamp,
            nonce,
            address(kyc)
        );
        
        vm.expectRevert(KYCVerification.InvalidSignature.selector);
        vm.prank(user1);
        kyc.verifyKYC(user1, true, expiryTimestamp, nonce, invalidSignature);
        
        console.log("[PASS] Invalid signature test passed");
    }
    
    /// @notice Test invalid nonce (replay attack protection)
    function test_InvalidNonce() public {
        uint256 wrongNonce = 2; // Should be 1 for first verification
        uint256 expiryTimestamp = block.timestamp + 365 days;
        
        bytes memory signature = generateValidSignature(
            user1,
            true,
            expiryTimestamp,
            wrongNonce,
            address(kyc)
        );
        
        vm.expectRevert(KYCVerification.InvalidNonce.selector);
        vm.prank(user1);
        kyc.verifyKYC(user1, true, expiryTimestamp, wrongNonce, signature);
        
        console.log("[PASS] Invalid nonce test passed");
    }
    
    /// @notice Test expired timestamp
    function test_InvalidExpiryTimestamp() public {
        uint256 nonce = 1;
        uint256 pastTimestamp = block.timestamp > 1 days ? block.timestamp - 1 days : 1;
        
        bytes memory signature = generateValidSignature(
            user1,
            true,
            pastTimestamp,
            nonce,
            address(kyc)
        );
        
        vm.expectRevert(KYCVerification.InvalidExpiryTimestamp.selector);
        vm.prank(user1);
        kyc.verifyKYC(user1, true, pastTimestamp, nonce, signature);
        
        console.log("[PASS] Invalid expiry timestamp test passed");
    }
    
    /// @notice Test already verified user
    function test_AlreadyVerified() public {
        // First verification
        performValidKYCVerification(kyc, user1, 365 days);
        
        // Try to verify again with same user
        uint256 nonce = 2;
        uint256 expiryTimestamp = block.timestamp + 365 days;
        
        bytes memory signature = generateValidSignature(
            user1,
            true,
            expiryTimestamp,
            nonce,
            address(kyc)
        );
        
        vm.expectRevert(KYCVerification.AlreadyVerified.selector);
        vm.prank(user1);
        kyc.verifyKYC(user1, true, expiryTimestamp, nonce, signature);
        
        console.log("[PASS] Already verified test passed");
    }
    
    /// @notice Test KYC expiry functionality
    function test_KYCExpiry() public {
        uint256 shortExpiry = 1 days;
        performValidKYCVerification(kyc, user1, shortExpiry);
        
        // User should be verified initially
        assertTrue(kyc.isCurrentlyVerified(user1), "User should be verified initially");
        
        // Advance time past expiry
        vm.warp(block.timestamp + shortExpiry + 1);
        
        // User should no longer be currently verified
        assertTrue(kyc.isVerified(user1), "User verification status should remain true");
        assertFalse(kyc.isCurrentlyVerified(user1), "User should not be currently verified after expiry");
        
        console.log("[PASS] KYC expiry test passed");
    }
    
    /// @notice Test renewal after expiry
    function test_RenewalAfterExpiry() public {
        // Initial verification with short expiry
        uint256 shortExpiry = 1 days;
        performValidKYCVerification(kyc, user1, shortExpiry);
        
        // Wait for expiry
        vm.warp(block.timestamp + shortExpiry + 1);
        assertFalse(kyc.isCurrentlyVerified(user1), "User should be expired");
        
        // Renew KYC
        uint256 nonce = 2;
        uint256 newExpiry = block.timestamp + 365 days;
        
        bytes memory signature = generateValidSignature(
            user1,
            true,
            newExpiry,
            nonce,
            address(kyc)
        );
        
        vm.prank(user1);
        kyc.verifyKYC(user1, true, newExpiry, nonce, signature);
        
        assertTrue(kyc.isCurrentlyVerified(user1), "User should be verified after renewal");
        assertEq(kyc.kycExpiry(user1), newExpiry, "New expiry should be set");
        
        console.log("[PASS] Renewal after expiry test passed");
    }
    
    /// @notice Test replay attack prevention
    function test_ReplayAttackPrevention() public {
        uint256 nonce = 1;
        uint256 expiryTimestamp = block.timestamp + 365 days;
        
        bytes memory signature = generateValidSignature(
            user1,
            true,
            expiryTimestamp,
            nonce,
            address(kyc)
        );
        
        // First verification should succeed
        vm.prank(user1);
        kyc.verifyKYC(user1, true, expiryTimestamp, nonce, signature);
        
        // Wait for expiry
        vm.warp(block.timestamp + 366 days);
        
        // Try to reuse the same signature (replay attack)
        testReplayAttack(kyc, user1, nonce, expiryTimestamp, signature);
        
        console.log("[PASS] Replay attack prevention test passed");
    }
    
    /// @notice Test admin functions - update signer
    function test_UpdateSigner() public {
        address newSigner = makeAddr("newSigner");
        
        vm.expectEmit(true, true, false, false);
        emit SignerUpdated(signer, newSigner);
        
        kyc.updateSigner(newSigner);
        
        assertEq(kyc.kycSigner(), newSigner, "Signer not updated");
        
        console.log("[PASS] Update signer test passed");
    }
    
    /// @notice Test admin functions - update signer with invalid address
    function test_UpdateSignerInvalidAddress() public {
        vm.expectRevert(KYCVerification.InvalidSigner.selector);
        kyc.updateSigner(address(0));
        
        console.log("[PASS] Update signer invalid address test passed");
    }
    
    /// @notice Test admin functions - revoke KYC
    function test_RevokeKYC() public {
        // First verify user
        performValidKYCVerification(kyc, user1, 365 days);
        
        // Revoke KYC
        vm.expectEmit(true, false, false, false);
        emit KYCRevoked(user1);
        
        kyc.revokeKYC(user1);
        
        assertFalse(kyc.isVerified(user1), "User should not be verified after revocation");
        assertFalse(kyc.isCurrentlyVerified(user1), "User should not be currently verified after revocation");
        assertEq(kyc.kycExpiry(user1), 0, "Expiry should be reset to 0");
        
        console.log("[PASS] Revoke KYC test passed");
    }
    
    /// @notice Test admin functions - update validity period
    function test_UpdateValidityPeriod() public {
        uint256 newPeriod = 180 days;
        
        vm.expectEmit(false, false, false, true);
        emit ValidityPeriodUpdated(365 days, newPeriod);
        
        kyc.updateValidityPeriod(newPeriod);
        
        assertEq(kyc.kycValidityPeriod(), newPeriod, "Validity period not updated");
        
        console.log("[PASS] Update validity period test passed");
    }
    
    /// @notice Test unauthorized access to admin functions
    function test_UnauthorizedAccess() public {
        testUnauthorizedAccess(kyc, attacker);
        
        console.log("[PASS] Unauthorized access test passed");
    }
    
    /// @notice Test EIP712 domain separator and hash functions
    function test_EIP712Functions() public {
        bytes32 domainSeparator = kyc.getDomainSeparator();
        assertNotEq(domainSeparator, bytes32(0), "Domain separator should not be empty");
        
        uint256 nonce = 1;
        uint256 expiryTimestamp = block.timestamp + 365 days;
        
        bytes32 kycHash = kyc.getKYCHash(user1, true, expiryTimestamp, nonce);
        assertNotEq(kycHash, bytes32(0), "KYC hash should not be empty");
        
        console.log("[PASS] EIP712 functions test passed");
    }
    
    /// @notice Test multiple users verification
    function test_MultipleUsersVerification() public {
        address[] memory users = setupTestUsers(5);
        
        // Mass verify all users
        massVerifyUsers(kyc, users, false);
        
        // Verify all are verified
        for (uint256 i = 0; i < users.length; i++) {
            assertTrue(kyc.isCurrentlyVerified(users[i]), "User should be verified");
        }
        
        console.log("[PASS] Multiple users verification test passed");
    }
    
    /// @notice Test staggered expiry times
    function test_StaggeredExpiryTimes() public {
        address[] memory users = setupTestUsers(3);
        
        // Verify users with different expiry times
        massVerifyUsers(kyc, users, true);
        
        // Advance time to middle expiry point - after first user expires but before last user
        vm.warp(block.timestamp + 366 days); // Just past first user's expiry
        
        // First user should be expired, but users with longer expiry should still be valid
        assertFalse(kyc.isCurrentlyVerified(users[0]), "First user should be expired");
        assertTrue(kyc.isCurrentlyVerified(users[2]), "Last user should still be verified");
        
        console.log("[PASS] Staggered expiry times test passed");
    }
    
    /// @notice Test gas optimization and efficiency
    function test_GasEfficiency() public {
        uint256 gasBefore = gasleft();
        
        performValidKYCVerification(kyc, user1, 365 days);
        
        uint256 gasUsed = gasBefore - gasleft();
        console.log("Gas used for KYC verification:", gasUsed);
        
        // Should be reasonable gas usage (less than 120k gas for EIP712 operations)
        assertLt(gasUsed, 120_000, "Gas usage should be reasonable");
        
        console.log("[PASS] Gas efficiency test passed");
    }
    
    /// @notice Test edge cases with boundary values
    function test_EdgeCases() public {
        (
            , // pastTimestamp - unused
            , // currentTimestamp - unused  
            , // futureTimestamp - unused
            uint256 maxTimestamp,
            , // validSig - unused
             // invalidSig - unused
        ) = generateEdgeCaseTestData(user1, address(kyc));
        
        // Test with maximum timestamp
        uint256 nonce = 1;
        bytes memory maxSig = generateValidSignature(
            user1,
            true,
            maxTimestamp,
            nonce,
            address(kyc)
        );
        
        vm.prank(user1);
        kyc.verifyKYC(user1, true, maxTimestamp, nonce, maxSig);
        
        assertTrue(kyc.isCurrentlyVerified(user1), "Should work with max timestamp");
        
        console.log("[PASS] Edge cases test passed");
    }
    
    /// @notice Test false verification (user marked as not verified)
    function test_FalseVerification() public {
        uint256 nonce = 1;
        uint256 expiryTimestamp = block.timestamp + 365 days;
        
        bytes memory signature = generateValidSignature(
            user1,
            false, // Not verified
            expiryTimestamp,
            nonce,
            address(kyc)
        );
        
        vm.prank(user1);
        kyc.verifyKYC(user1, false, expiryTimestamp, nonce, signature);
        
        assertFalse(kyc.isVerified(user1), "User should not be verified");
        assertFalse(kyc.isCurrentlyVerified(user1), "User should not be currently verified");
        
        console.log("[PASS] False verification test passed");
    }
    
    /// @notice Test signature with different chain ID (should fail)
    function test_CrossChainReplay() public {
        // This test ensures signatures from different chains can't be replayed
        uint256 originalChainId = block.chainid;
        
        // Create signature on current chain
        uint256 nonce = 1;
        uint256 expiryTimestamp = block.timestamp + 365 days;
        
        bytes memory signature = generateValidSignature(
            user1,
            true,
            expiryTimestamp,
            nonce,
            address(kyc)
        );
        
        // Change chain ID (simulate different chain)
        vm.chainId(999);
        
        // Deploy new contract on "different" chain
        KYCVerification differentChainKyc = new KYCVerification(signer);
        
        // Try to use signature from original chain (should fail)
        vm.expectRevert(KYCVerification.InvalidSignature.selector);
        vm.prank(user1);
        differentChainKyc.verifyKYC(user1, true, expiryTimestamp, nonce, signature);
        
        // Restore original chain ID
        vm.chainId(originalChainId);
        
        console.log("[PASS] Cross-chain replay test passed");
    }
    
    /// @notice Test stress testing with many operations
    function test_StressTesting() public {
        console.log("=== Stress Testing ===");
        
        uint256 numUsers = 20;
        address[] memory users = setupTestUsers(numUsers);
        
        // Verify all users
        for (uint256 i = 0; i < users.length; i++) {
            performValidKYCVerification(kyc, users[i], 365 days + (i * 1 days));
        }
        
        // Revoke half of them
        for (uint256 i = 0; i < users.length / 2; i++) {
            kyc.revokeKYC(users[i]);
            assertFalse(kyc.isCurrentlyVerified(users[i]), "Should be revoked");
        }
        
        // Update signer multiple times
        for (uint256 i = 0; i < 5; i++) {
            address newSigner = makeAddr(string(abi.encodePacked("signer", i)));
            kyc.updateSigner(newSigner);
        }
        
        console.log("[PASS] Stress testing passed");
    }
    
    /// @notice Test integration with external contracts (mock scenario)
    function test_IntegrationScenario() public {
        console.log("=== Integration Scenario ===");
        
        // Simulate a presale contract checking KYC
        performValidKYCVerification(kyc, user1, 365 days);
        
        // Mock presale contract behavior
        assertTrue(kyc.isCurrentlyVerified(user1), "User should pass KYC check");
        
        // Simulate time passage and re-check
        vm.warp(block.timestamp + 200 days);
        assertTrue(kyc.isCurrentlyVerified(user1), "User should still pass KYC check");
        
        // Simulate KYC expiry during presale 
        vm.warp(block.timestamp + 166 days); // Total: 366 days > 365 days
        assertFalse(kyc.isCurrentlyVerified(user1), "User should fail KYC check after expiry");
        
        console.log("[PASS] Integration scenario test passed");
    }
    
    /// @notice Comprehensive test of all functionality
    function test_ComprehensiveFlow() public {
        console.log("=== Comprehensive Flow Test ===");
        
        // 1. Deploy and verify initial state
        assertEq(kyc.owner(), address(this));
        assertEq(kyc.kycSigner(), signer);
        
        // 2. Perform valid verification
        performValidKYCVerification(kyc, user1, 365 days);
        
        // 3. Test admin functions
        kyc.updateValidityPeriod(180 days);
        address newSigner = makeAddr("newSigner");
        kyc.updateSigner(newSigner);
        
        // 4. Verify with new signer
        uint256 expiryTimestamp = block.timestamp + 180 days;
        
        // Update helper to use new signer
        bytes memory newSignature = signKYCData(
            SIGNER_PRIVATE_KEY,
            user2,
            true,
            expiryTimestamp,
            1,
            address(kyc)
        );
        
        // This should fail because we changed the signer but used old key
        vm.expectRevert(KYCVerification.InvalidSignature.selector);
        vm.prank(user2);
        kyc.verifyKYC(user2, true, expiryTimestamp, 1, newSignature);
        
        // 5. Test revocation
        kyc.revokeKYC(user1);
        assertFalse(kyc.isCurrentlyVerified(user1));
        
        console.log("[PASS] Comprehensive flow test passed");
        console.log("=== All KYC Tests Completed Successfully ===");
    }
}