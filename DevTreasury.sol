// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IMultiTokenPresale {
    function presaleEnded() external view returns (bool);
    function escrowPresaleEnded() external view returns (bool);
}

/**
 * @title DevTreasury
 * @notice Treasury contract for developer incentives (4% of presale)
 * @dev Receives 4% fee from all presale purchases and distributes after presale ends
 * 
 * Distribution:
 * - 31.25% → Developer 1 (1.25% of total presale)
 * - 31.25% → Developer 2 (1.25% of total presale)
 * - 12.5% → Developer 3 (0.5% of total presale)
 * - 25% → Developer 4 (1% of total presale)
 */
contract DevTreasury is ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    // ============ IMMUTABLE ADDRESSES ============
    
    /// @notice Presale contract reference
    IMultiTokenPresale public immutable presale;
    
    /// @notice Developer addresses (hardcoded - cannot be changed)
    address public constant DEVELOPER1 = 0x04435410a78192baAfa00c72C659aD3187a2C2cF; // Surya - 31.25% (1.25% of presale)
    address public constant DEVELOPER2 = 0x9005132849bC9585A948269D96F23f56e5981A61; // Bhom - 31.25% (1.25% of presale)
    address public constant DEVELOPER3 = 0x1C5cf9Cb69effeeb31E261BB6519AF7247A97A74; // Zala - 12.5% (0.5% of presale)
    address public constant DEVELOPER4 = 0x403d8e7c3a1f7a0c7faf2a81b52cc74d775e9e21; // Muhammad - 25% (1% of presale)
    
    // ============ CONSTANTS ============
    
    uint256 private constant PERCENTAGE_BASE = 10000; // 100% = 10000 (for precision)
    uint256 private constant SHARE_DEV1 = 3125;      // 31.25%
    uint256 private constant SHARE_DEV2 = 3125;      // 31.25%
    uint256 private constant SHARE_DEV3 = 1250;      // 12.5%
    uint256 private constant SHARE_DEV4 = 2500;      // 25%
    
    // ============ STATE ============
    
    /// @notice Track if funds have been withdrawn for each token
    mapping(address => bool) public withdrawn;
    
    // ============ EVENTS ============
    
    event FundsDistributed(
        address indexed token,
        uint256 totalAmount,
        uint256 dev1Share,
        uint256 dev2Share,
        uint256 dev3Share,
        uint256 dev4Share
    );
    
    // ============ CONSTRUCTOR ============
    
    constructor(address _presale) {
        require(_presale != address(0), "Invalid presale address");
        presale = IMultiTokenPresale(_presale);
    }
    
    // ============ WITHDRAWAL FUNCTIONS ============
    
    /// @notice Withdraw and distribute ETH to all developers
    /// @dev Can be called by anyone after presale ends
    function withdrawETH() external nonReentrant {
        require(presale.presaleEnded() || presale.escrowPresaleEnded(), "Presale not ended");
        require(!withdrawn[address(0)], "ETH already withdrawn");
        
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");
        
        withdrawn[address(0)] = true;
        
        // Calculate shares
        uint256 dev1Share = (balance * SHARE_DEV1) / PERCENTAGE_BASE;
        uint256 dev2Share = (balance * SHARE_DEV2) / PERCENTAGE_BASE;
        uint256 dev3Share = (balance * SHARE_DEV3) / PERCENTAGE_BASE;
        uint256 dev4Share = (balance * SHARE_DEV4) / PERCENTAGE_BASE;
        
        // Transfer to each developer
        payable(DEVELOPER1).transfer(dev1Share);
        payable(DEVELOPER2).transfer(dev2Share);
        payable(DEVELOPER3).transfer(dev3Share);
        payable(DEVELOPER4).transfer(dev4Share);
        
        emit FundsDistributed(address(0), balance, dev1Share, dev2Share, dev3Share, dev4Share);
    }
    
    /// @notice Withdraw and distribute ERC20 tokens to all developers
    /// @dev Can be called by anyone after presale ends
    /// @param token ERC20 token address to withdraw
    function withdrawToken(address token) external nonReentrant {
        require(presale.presaleEnded() || presale.escrowPresaleEnded(), "Presale not ended");
        require(token != address(0), "Invalid token address");
        require(!withdrawn[token], "Token already withdrawn");
        
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "No tokens to withdraw");
        
        withdrawn[token] = true;
        
        // Calculate shares
        uint256 dev1Share = (balance * SHARE_DEV1) / PERCENTAGE_BASE;
        uint256 dev2Share = (balance * SHARE_DEV2) / PERCENTAGE_BASE;
        uint256 dev3Share = (balance * SHARE_DEV3) / PERCENTAGE_BASE;
        uint256 dev4Share = (balance * SHARE_DEV4) / PERCENTAGE_BASE;
        
        // Transfer to each developer
        IERC20(token).safeTransfer(DEVELOPER1, dev1Share);
        IERC20(token).safeTransfer(DEVELOPER2, dev2Share);
        IERC20(token).safeTransfer(DEVELOPER3, dev3Share);
        IERC20(token).safeTransfer(DEVELOPER4, dev4Share);
        
        emit FundsDistributed(token, balance, dev1Share, dev2Share, dev3Share, dev4Share);
    }
    
    // ============ VIEW FUNCTIONS ============
    
    /// @notice Get ETH balance in contract
    function getETHBalance() external view returns (uint256) {
        return address(this).balance;
    }
    
    /// @notice Get ERC20 token balance in contract
    function getTokenBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }
    
    /// @notice Check if presale has ended
    function isPresaleEnded() external view returns (bool) {
        return presale.presaleEnded() || presale.escrowPresaleEnded();
    }
    
    /// @notice Get developer shares (in basis points, 10000 = 100%)
    function getShares() external pure returns (uint256, uint256, uint256, uint256) {
        return (SHARE_DEV1, SHARE_DEV2, SHARE_DEV3, SHARE_DEV4);
    }
    
    // ============ RECEIVE FUNCTION ============
    
    /// @notice Receive ETH from presale
    receive() external payable {}
}
