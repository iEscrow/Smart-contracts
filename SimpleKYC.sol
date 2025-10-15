// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/// @title SimpleKYC
/// @notice Simplified KYC contract for testing purposes
/// @dev This contract is designed for testing and audit preparation only
contract SimpleKYC is EIP712 {
    address public kycSigner;
    address public admin;

    mapping(address => bool) public isVerified;

    event UserVerified(address indexed user, bool verified);

    /// @notice Constructor
    /// @param _kycSigner Address authorized to sign KYC data
    constructor(address _kycSigner) EIP712("KYCVerification", "1") {
        kycSigner = _kycSigner;
        admin = msg.sender; // deployer is admin
    }

    /// @notice Admin function to directly mark KYC = true for testing
    /// @param user Address to verify
    function adminSetVerified(address user) external {
        require(msg.sender == admin, "Only admin can set");
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
    function adminRevokeVerified(address user) external {
        require(msg.sender == admin, "Only admin can revoke");
        isVerified[user] = false;
        emit UserVerified(user, false);
    }

    /// @notice Update admin address
    /// @param newAdmin New admin address
    function updateAdmin(address newAdmin) external {
        require(msg.sender == admin, "Only admin can update");
        require(newAdmin != address(0), "Invalid admin address");
        admin = newAdmin;
    }
}