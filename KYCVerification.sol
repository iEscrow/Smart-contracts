// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @title KYCVerification
/// @notice Handles KYC verification using EIP712 signatures from authorized backend
/// @dev Uses EIP712 for signature verification to prevent replay attacks and ensure data integrity
contract KYCVerification is EIP712, Ownable {
    using ECDSA for bytes32;

    // KYC signer (your backend wallet address)
    address public kycSigner;

    // Mapping to store KYC status
    mapping(address => bool) public isVerified;
    
    // Mapping to store KYC expiry timestamps
    mapping(address => uint256) public kycExpiry;

    // Prevent replay attacks
    mapping(address => uint256) public nonces;

    // KYC validity period (default: 1 year)
    uint256 public kycValidityPeriod = 365 days;

    // EIP712 typehash for KYC data
    bytes32 public constant KYC_TYPEHASH =
        keccak256("KYCData(address user,bool verified,uint256 expiryTimestamp,uint256 nonce)");

    // Events
    event UserVerified(address indexed user, bool verified, uint256 expiryTimestamp);
    event SignerUpdated(address indexed oldSigner, address indexed newSigner);
    event ValidityPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);
    event KYCRevoked(address indexed user);

    // Errors
    error InvalidNonce();
    error AlreadyVerified();
    error InvalidSignature();
    error InvalidSigner();
    error KYCExpired();
    error InvalidExpiryTimestamp();

    /// @notice Constructor
    /// @param _kycSigner Address authorized to sign KYC data
    constructor(address _kycSigner) 
        EIP712("KYCVerification", "1") 
        Ownable(msg.sender)
    {
        if (_kycSigner == address(0)) revert InvalidSigner();
        kycSigner = _kycSigner;
    }

    /// @notice User submits signed KYC proof from backend
    /// @param user Address of the user to verify
    /// @param verified Whether the user is verified
    /// @param expiryTimestamp When the KYC expires
    /// @param nonce Nonce for replay protection
    /// @param signature EIP712 signature from authorized signer
    function verifyKYC(
        address user,
        bool verified,
        uint256 expiryTimestamp,
        uint256 nonce,
        bytes calldata signature
    ) external {
        if (nonce != nonces[user] + 1) revert InvalidNonce();
        if (isVerified[user] && kycExpiry[user] > block.timestamp) revert AlreadyVerified();
        if (expiryTimestamp <= block.timestamp) revert InvalidExpiryTimestamp();

        // Verify EIP712 signature
        bytes32 structHash = keccak256(
            abi.encode(KYC_TYPEHASH, user, verified, expiryTimestamp, nonce)
        );

        bytes32 digest = _hashTypedDataV4(structHash);
        address recoveredSigner = ECDSA.recover(digest, signature);
        
        if (recoveredSigner != kycSigner) revert InvalidSignature();

        // Update user verification state
        isVerified[user] = verified;
        kycExpiry[user] = expiryTimestamp;
        nonces[user] = nonce;

        emit UserVerified(user, verified, expiryTimestamp);
    }

    /// @notice Check if user is currently verified (not expired)
    /// @param user Address to check
    /// @return bool Whether user is verified and not expired
    function isCurrentlyVerified(address user) external view returns (bool) {
        return isVerified[user] && kycExpiry[user] > block.timestamp;
    }

    /// @notice Admin function to revoke KYC for a user
    /// @param user Address to revoke KYC for
    function revokeKYC(address user) external onlyOwner {
        isVerified[user] = false;
        kycExpiry[user] = 0;
        emit KYCRevoked(user);
    }

    /// @notice Admin can change signer if needed
    /// @param newSigner New authorized signer address
    function updateSigner(address newSigner) external onlyOwner {
        if (newSigner == address(0)) revert InvalidSigner();
        address oldSigner = kycSigner;
        kycSigner = newSigner;
        emit SignerUpdated(oldSigner, newSigner);
    }

    /// @notice Update KYC validity period
    /// @param newPeriod New validity period in seconds
    function updateValidityPeriod(uint256 newPeriod) external onlyOwner {
        uint256 oldPeriod = kycValidityPeriod;
        kycValidityPeriod = newPeriod;
        emit ValidityPeriodUpdated(oldPeriod, newPeriod);
    }

    /// @notice Get domain separator for EIP712
    /// @return bytes32 Domain separator
    function getDomainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @notice Generate the hash for KYC data (useful for off-chain signature generation)
    /// @param user Address of the user
    /// @param verified Whether the user is verified  
    /// @param expiryTimestamp When the KYC expires
    /// @param nonce Nonce for replay protection
    /// @return bytes32 Hash to be signed
    function getKYCHash(
        address user,
        bool verified,
        uint256 expiryTimestamp,
        uint256 nonce
    ) external view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(KYC_TYPEHASH, user, verified, expiryTimestamp, nonce)
        );
        return _hashTypedDataV4(structHash);
    }
}