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

    error InvalidSigner();
    error Unauthorized();
    error AlreadyVerified();
    error InvalidAdmin();

    /// @notice Constructor
    /// @param _kycSigner Address authorized to sign KYC data
    constructor(address _kycSigner) EIP712("KYCVerification", "1") {
        if (_kycSigner == address(0)) revert InvalidSigner();
        kycSigner = _kycSigner;
        admin = msg.sender; // deployer is admin
    }

    /// @notice Admin function to directly mark KYC = true for testing
    /// @param user Address to verify
    function adminSetVerified(address user) external {
        if (msg.sender != admin) revert Unauthorized();
        if (isVerified[user]) revert AlreadyVerified();
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
        if (msg.sender != admin) revert Unauthorized();
        isVerified[user] = false;
        emit UserVerified(user, false);
    }

    /// @notice Update admin address
    /// @param newAdmin New admin address
    function updateAdmin(address newAdmin) external {
        if (msg.sender != admin) revert Unauthorized();
        if (newAdmin == address(0)) revert InvalidAdmin();
        admin = newAdmin;
    }
}