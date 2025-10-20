// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @title SimpleKYC
/// @notice Simplified KYC contract for testing purposes
/// @dev This contract is designed for testing and audit preparation only
contract SimpleKYC is EIP712, Ownable {
    address public kycSigner;

    mapping(address => bool) public isVerified;

    event UserVerified(address indexed user, bool verified);

    /// @notice Constructor
    /// @param _kycSigner Address authorized to sign KYC data
    constructor(address _kycSigner) EIP712("KYCVerification", "1") Ownable(msg.sender) {
        kycSigner = _kycSigner;
    }

    /// @notice Admin function to directly mark KYC = true for testing
    /// @param user Address to verify
    function adminSetVerified(address user) external onlyOwner {
        require(!isVerified[user], "Already verified");
        isVerified[user] = true;

        emit UserVerified(user, true);
    }

    /// @notice Check if user is verified
    /// @param user Address to check
    /// @return bool Whether user is verified
    function isCurrentlyVerified(address user) external view returns (bool) {
        return isVerified[user];
    }

    /// @notice Admin function to revoke KYC for testing
    /// @param user Address to revoke KYC for
    function adminRevokeVerified(address user) external onlyOwner {
        isVerified[user] = false;
        emit UserVerified(user, false);
    }

    /// @notice Update admin address
    /// @param newAdmin New admin address
    function updateAdmin(address newAdmin) external onlyOwner {
        require(newAdmin != address(0), "Invalid admin address");
        // Note: Since using Ownable, this function is redundant, but kept for compatibility
    }
}