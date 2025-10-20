// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title EscrowToken - The utility token for the iEscrow ecosystem
/// @notice Standard ERC20 with 18 decimals, ERC20Permit for gasless approvals, and burnable tokens
/// @dev Max supply: 100 billion tokens, Presale allocation: 5 billion tokens
contract EscrowToken is ERC20, ERC20Permit, ERC20Burnable, Ownable, ReentrancyGuard {
    
    // ============ CONSTANTS ============
    
    /// @notice Maximum total supply of tokens
    /// @dev 100 billion tokens
    uint256 public constant MAX_SUPPLY = 100_000_000_000 * 1e18; // 100 billion tokens
    /// @notice Allocation for presale
    /// @dev 5 billion tokens
    uint256 public constant PRESALE_ALLOCATION = 5_000_000_000 * 1e18; // 5 billion for presale
    
    // ============ STATE VARIABLES ============
    
    /// @notice Total amount of tokens minted so far
    uint256 public totalMinted;
    /// @notice Whether minting has been permanently finalized
    bool public mintingFinalized;
    /// @notice Mapping of addresses authorized to mint tokens
    mapping(address => bool) public isMinter;
    /// @notice Whether the presale allocation has been minted
    bool public presaleAllocationMinted;
    
    // ============ EVENTS ============
    
    /// @notice Emitted when a minter's status is updated
    /// @param minter The address whose minter status was updated
    /// @param status The new minter status
    event MinterUpdated(address indexed minter, bool status);
    /// @notice Emitted when minting is finalized
    event MintingFinalized();
    /// @notice Emitted when presale allocation is minted
    /// @param presaleContract The address of the presale contract
    /// @param amount The amount of tokens minted
    event PresaleAllocationMinted(address indexed presaleContract, uint256 amount);
    /// @notice Emitted when emergency withdrawal occurs
    /// @param token The address of the withdrawn token (0 for ETH)
    /// @param to The address receiving the withdrawal
    /// @param amount The amount withdrawn
    event EmergencyWithdrawal(address indexed token, address indexed to, uint256 amount);
    
    // ============ CONSTRUCTOR ============
    
    /// @notice Contract constructor
    /// @dev Initializes the ERC20 token with name and symbol, sets owner
    constructor() 
        ERC20("Escrow Token", "ESCROW") 
        ERC20Permit("Escrow Token")
        Ownable(msg.sender)
    {
        // Token starts with 0 supply - all tokens minted on demand
    }
    
    // ============ MINTING FUNCTIONS ============
    
    /// @notice Mint the presale allocation (5B tokens) to presale contract
    /// @param presaleContract Address of the presale contract
    function mintPresaleAllocation(address presaleContract) external onlyOwner {
        require(presaleContract != address(0), "Invalid presale contract");
        require(!mintingFinalized, "Minting finalized");
        require(!presaleAllocationMinted, "Presale allocation already minted");
        
        presaleAllocationMinted = true;
        totalMinted += PRESALE_ALLOCATION;
        
        _mint(presaleContract, PRESALE_ALLOCATION);
        emit PresaleAllocationMinted(presaleContract, PRESALE_ALLOCATION);
    }
    
    /// @notice Mint tokens to specified address (owner only, for team/treasury/LP allocations)
    /// @param to Address to mint tokens to
    /// @param amount Amount of tokens to mint
    function mint(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "Invalid recipient");
        require(!mintingFinalized, "Minting finalized");
        require(amount > 0, "Invalid amount");
        
        totalMinted += amount;
        require(totalMinted <= MAX_SUPPLY, "Exceeds max supply");
        
        _mint(to, amount);
    }
    
    /// @notice Allow authorized minters to mint tokens (for future staking rewards)
    /// @param to Address to mint tokens to
    /// @param amount Amount of tokens to mint
    function minterMint(address to, uint256 amount) external {
        require(isMinter[msg.sender], "Not authorized minter");
        require(!mintingFinalized, "Minting finalized");
        require(to != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");
        
        totalMinted += amount;
        require(totalMinted <= MAX_SUPPLY, "Exceeds max supply");
        
        _mint(to, amount);
    }
    
    /// @notice Set minter status for address (for future staking contract)
    /// @param minter Address to set minter status for
    /// @param status Whether the address can mint tokens
    function setMinter(address minter, bool status) external onlyOwner {
        require(minter != address(0), "Invalid minter address");
        isMinter[minter] = status;
        emit MinterUpdated(minter, status);
    }
    
    /// @notice Finalize minting - prevents any future minting
    /// @dev Use this after all allocations (presale, team, treasury, LP) are complete
    function finalizeMinting() external onlyOwner {
        require(!mintingFinalized, "Already finalized");
        mintingFinalized = true;
        emit MintingFinalized();
    }
    
    // ============ VIEW FUNCTIONS ============
    
    /// @notice Get remaining supply that can be minted
    /// @return Remaining tokens that can be minted
    function remainingSupply() external view returns (uint256) {
        return MAX_SUPPLY - totalMinted;
    }
    
    /// @notice Check if address is authorized minter
    /// @param account Address to check minter status for
    /// @return Whether the account can mint tokens
    function canMint(address account) external view returns (bool) {
        return isMinter[account] && !mintingFinalized;
    }
    
    /// @notice Check if presale allocation has been minted
    /// @return Whether the presale allocation has been minted
    function isPresaleAllocationMinted() external view returns (bool) {
        return presaleAllocationMinted;
    }
    
    /// @notice Get comprehensive token distribution information
    /// @return tokenName Name of the token
    /// @return tokenSymbol Symbol of the token
    /// @return tokenDecimals Number of decimals
    /// @return maxSupply Maximum supply of tokens
    /// @return currentSupply Current total supply
    /// @return remainingMintable Remaining tokens that can be minted
    /// @return mintingComplete Whether minting has been finalized
    function getTokenInfo() external view returns (
        string memory tokenName,
        string memory tokenSymbol,
        uint8 tokenDecimals,
        uint256 maxSupply,
        uint256 currentSupply,
        uint256 remainingMintable,
        bool mintingComplete
    ) {
        tokenName = name();
        tokenSymbol = symbol();
        tokenDecimals = decimals();
        maxSupply = MAX_SUPPLY;
        currentSupply = totalSupply();
        remainingMintable = MAX_SUPPLY - totalMinted;
        mintingComplete = mintingFinalized;
    }
    
    // ============ EMERGENCY FUNCTIONS ============
    
    /// @notice Emergency withdrawal of stuck ERC20 tokens (not ESCROW)
    /// @param token Address of the ERC20 token to withdraw
    /// @param to Address to send the tokens to
    /// @param amount Amount of tokens to withdraw
    function emergencyWithdrawToken(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner nonReentrant {
        require(token != address(this), "Cannot withdraw ESCROW tokens");
        require(to != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");
        
        SafeERC20.safeTransfer(IERC20(token), to, amount);
        emit EmergencyWithdrawal(token, to, amount);
    }
    
    /// @notice Emergency withdrawal of stuck ETH
    /// @param to Address to send the ETH to
    function emergencyWithdrawETH(address payable to) external onlyOwner nonReentrant {
        require(to != address(0), "Invalid recipient");
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");
        
        to.transfer(balance);
        emit EmergencyWithdrawal(address(0), to, balance);
    }
    
    // ============ OVERRIDES ============
    
    /// @notice Override decimals to ensure 18 decimals (per ERC20 standard and whitepaper)
    /// @return Number of decimals (always 18)
    function decimals() public pure override returns (uint8) {
        return 18;
    }
}