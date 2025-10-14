// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title EscrowToken ($ESCROW)
 * @dev Production-ready ERC20 token with comprehensive security features
 * @notice Main utility token for the iEscrow ecosystem
 * @custom:security-contact security@iescrow.com
 * @custom:audited-by Pending Certik Audit
 */
contract EscrowToken is ERC20, ERC20Burnable, ERC20Permit, AccessControl, Pausable {
    // ============ ROLES ============
    
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    
    // ============ STATE VARIABLES ============
    
    uint256 public constant MAX_SUPPLY = 100_000_000_000 * 1e18; // 100 billion tokens
    uint256 public totalMinted;
    
    // Anti-bot protection (optional, can be disabled after launch)
    mapping(address => bool) public blacklist;
    bool public tradingEnabled;
    uint256 public tradingEnabledTimestamp;
    
    // Fee configuration (optional, disabled by default)
    bool public feesEnabled;
    uint256 public transferFeeRate; // In basis points (10000 = 100%)
    address public feeCollector;
    uint256 public constant MAX_FEE_RATE = 500; // Max 5%
    
    // ============ EVENTS ============
    
    event TradingEnabled(uint256 timestamp);
    event BlacklistUpdated(address indexed account, bool status);
    event FeesConfigured(bool enabled, uint256 rate, address collector);
    event FeesCollected(address indexed from, address indexed to, uint256 amount);
    
    // ============ ERRORS ============
    
    error MaxSupplyExceeded();
    error TradingNotEnabled();
    error AccountBlacklisted();
    error InvalidFeeRate();
    error InvalidAddress();
    error Unauthorized();
    
    // ============ MODIFIERS ============
    
    modifier notBlacklisted(address account) {
        if (blacklist[account]) revert AccountBlacklisted();
        _;
    }
    
    modifier tradingActive() {
        if (!tradingEnabled && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert TradingNotEnabled();
        }
        _;
    }
    
    // ============ CONSTRUCTOR ============
    
    /**
     * @dev Initializes the token with name, symbol and sets up roles
     * @param admin Address that will receive DEFAULT_ADMIN_ROLE
     */
    constructor(address admin) 
        ERC20("ESCROW", "ESCROW") 
        ERC20Permit("ESCROW")
        AccessControl()
    {
        if (admin == address(0)) revert InvalidAddress();
        
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(BURNER_ROLE, admin);
        
        // Trading disabled by default, will be enabled after presale
        tradingEnabled = false;
        feesEnabled = false;
        transferFeeRate = 0;
    }
    
    // ============ MINTING FUNCTIONS ============
    
    /**
     * @dev Mints tokens to a specified address
     * @param to Address to receive tokens
     * @param amount Amount of tokens to mint
     * @notice Only addresses with MINTER_ROLE can call this
     * @notice Total supply cannot exceed MAX_SUPPLY
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (to == address(0)) revert InvalidAddress();
        
        uint256 newTotalMinted = totalMinted + amount;
        if (newTotalMinted > MAX_SUPPLY) revert MaxSupplyExceeded();
        
        totalMinted = newTotalMinted;
        _mint(to, amount);
    }
    
    /**
     * @dev Batch mint to multiple addresses
     * @param recipients Array of addresses to receive tokens
     * @param amounts Array of amounts corresponding to each recipient
     */
    function batchMint(address[] calldata recipients, uint256[] calldata amounts) 
        external 
        onlyRole(MINTER_ROLE) 
    {
        require(recipients.length == amounts.length, "Length mismatch");
        require(recipients.length <= 200, "Too many recipients");
        
        uint256 totalAmount;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }
        
        uint256 newTotalMinted = totalMinted + totalAmount;
        if (newTotalMinted > MAX_SUPPLY) revert MaxSupplyExceeded();
        
        totalMinted = newTotalMinted;
        
        for (uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i] != address(0)) {
                _mint(recipients[i], amounts[i]);
            }
        }
    }
    
    // ============ BURNING FUNCTIONS ============
    
    /**
     * @dev Burns tokens from a specific address
     * @param from Address to burn tokens from
     * @param amount Amount of tokens to burn
     * @notice Only addresses with BURNER_ROLE can burn from other accounts without allowance
     * @notice Regular users can burn using the inherited burnFrom with allowance
     */
    function burnFrom(address from, uint256 amount) 
        public 
        override 
    {
        if (!hasRole(BURNER_ROLE, msg.sender)) {
            // Non-burner role users must have allowance
            super.burnFrom(from, amount);
        } else {
            // BURNER_ROLE can burn without allowance
            _burn(from, amount);
        }
    }
    
    // ============ TRANSFER FUNCTIONS ============
    
    /**
     * @dev Override transfer to add security checks
     */
    function transfer(address to, uint256 amount) 
        public 
        virtual 
        override 
        whenNotPaused 
        tradingActive
        notBlacklisted(msg.sender)
        notBlacklisted(to)
        returns (bool) 
    {
        if (feesEnabled && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            return _transferWithFee(msg.sender, to, amount);
        }
        return super.transfer(to, amount);
    }
    
    /**
     * @dev Override transferFrom to add security checks
     */
    function transferFrom(address from, address to, uint256 amount) 
        public 
        virtual 
        override 
        whenNotPaused 
        tradingActive
        notBlacklisted(from)
        notBlacklisted(to)
        returns (bool) 
    {
        // Skip fees for presale payments to avoid circular dependencies
        // when using escrow token as payment method
        if (feesEnabled && !hasRole(DEFAULT_ADMIN_ROLE, from) && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            _spendAllowance(from, msg.sender, amount);
            return _transferWithFee(from, to, amount);
        }
        return super.transferFrom(from, to, amount);
    }
    
    /**
     * @dev Internal function to handle transfers with fees
     */
    function _transferWithFee(address from, address to, uint256 amount) 
        private 
        returns (bool) 
    {
        uint256 feeAmount = (amount * transferFeeRate) / 10000;
        uint256 amountAfterFee = amount - feeAmount;
        
        if (feeAmount > 0 && feeCollector != address(0)) {
            _transfer(from, feeCollector, feeAmount);
            emit FeesCollected(from, feeCollector, feeAmount);
        }
        
        _transfer(from, to, amountAfterFee);
        return true;
    }
    
    // ============ ADMIN FUNCTIONS ============
    
    /**
     * @dev Enables trading for all users
     * @notice Can only be called once by admin
     */
    function enableTrading() external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!tradingEnabled, "Trading already enabled");
        tradingEnabled = true;
        tradingEnabledTimestamp = block.timestamp;
        emit TradingEnabled(block.timestamp);
    }
    
    /**
     * @dev Updates blacklist status for an account
     * @param account Address to update
     * @param status True to blacklist, false to remove from blacklist
     */
    function updateBlacklist(address account, bool status) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        if (account == address(0)) revert InvalidAddress();
        blacklist[account] = status;
        emit BlacklistUpdated(account, status);
    }
    
    /**
     * @dev Batch update blacklist
     * @param accounts Array of addresses to update
     * @param status Status to set for all accounts
     */
    function batchUpdateBlacklist(address[] calldata accounts, bool status) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        for (uint256 i = 0; i < accounts.length; i++) {
            if (accounts[i] != address(0)) {
                blacklist[accounts[i]] = status;
                emit BlacklistUpdated(accounts[i], status);
            }
        }
    }
    
    /**
     * @dev Configures transfer fees
     * @param enabled Whether fees are enabled
     * @param rate Fee rate in basis points (10000 = 100%)
     * @param collector Address to collect fees
     */
    function configureFees(bool enabled, uint256 rate, address collector) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        if (rate > MAX_FEE_RATE) revert InvalidFeeRate();
        if (enabled && collector == address(0)) revert InvalidAddress();
        
        feesEnabled = enabled;
        transferFeeRate = rate;
        feeCollector = collector;
        
        emit FeesConfigured(enabled, rate, collector);
    }
    
    /**
     * @dev Pauses all token transfers
     * @notice Emergency function
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }
    
    /**
     * @dev Unpauses all token transfers
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
    
    // ============ VIEW FUNCTIONS ============
    
    /**
     * @dev Returns remaining mintable supply
     */
    function remainingSupply() external view returns (uint256) {
        return MAX_SUPPLY - totalMinted;
    }
    
    /**
     * @dev Returns complete token information
     */
    function getTokenInfo() external view returns (
        uint256 maxSupply,
        uint256 currentSupply,
        uint256 minted,
        uint256 burned,
        bool trading,
        bool isPaused
    ) {
        return (
            MAX_SUPPLY,
            totalSupply(),
            totalMinted,
            totalMinted - totalSupply(),
            tradingEnabled,
            paused()
        );
    }
    
    /**
     * @dev Returns fee configuration
     */
    function getFeeInfo() external view returns (
        bool enabled,
        uint256 rate,
        address collector
    ) {
        return (feesEnabled, transferFeeRate, feeCollector);
    }
    
    /**
     * @dev Checks if an account can transfer tokens
     */
    function canTransfer(address account) external view returns (bool) {
        return !paused() && 
               (tradingEnabled || hasRole(DEFAULT_ADMIN_ROLE, account)) &&
               !blacklist[account];
    }
}
