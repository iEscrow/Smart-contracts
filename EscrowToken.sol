// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// EscrowToken - The utility token for the iEscrow ecosystem
// Standard ERC20 with 18 decimals (per whitepaper)
// ERC20Permit for gasless approvals
// Burnable tokens (required for future staking contract)
// Max supply: 100 billion tokens (per whitepaper)
// Presale allocation: 5 billion tokens
// Owner-controlled minting with finalization capability
contract EscrowToken is ERC20, ERC20Permit, ERC20Burnable, Ownable, ReentrancyGuard {
    
    // Constants (Per Whitepaper)
    uint256 public constant MAX_SUPPLY = 100_000_000_000 * 1e18; // 100 billion tokens
    uint256 public constant PRESALE_ALLOCATION = 5_000_000_000 * 1e18; // 5 billion for presale
    
    // State Variables
    uint256 public totalMinted;
    bool public mintingFinalized;
    mapping(address => bool) public isMinter;
    bool public presaleAllocationMinted;
    
    // Events
    event MinterUpdated(address indexed minter, bool status);
    event MintingFinalized();
    event PresaleAllocationMinted(address indexed presaleContract, uint256 amount);
    event EmergencyWithdrawal(address indexed token, address indexed to, uint256 amount);
    
    // Constructor
    constructor() 
        ERC20("Escrow Token", "ESCROW") 
        ERC20Permit("Escrow Token")
        Ownable(msg.sender)
    {
        // Token starts with 0 supply - all tokens minted on demand
    }
    
    // Mint the presale allocation (5B tokens) to presale contract
    function mintPresaleAllocation(address presaleContract) external onlyOwner {
        require(presaleContract != address(0), "Invalid presale contract");
        require(!mintingFinalized, "Minting finalized");
        require(!presaleAllocationMinted, "Presale allocation already minted");
        
        presaleAllocationMinted = true;
        totalMinted += PRESALE_ALLOCATION;
        
        _mint(presaleContract, PRESALE_ALLOCATION);
        emit PresaleAllocationMinted(presaleContract, PRESALE_ALLOCATION);
    }
    
    // Mint tokens to specified address (owner only, for team/treasury/LP allocations)
    function mint(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "Invalid recipient");
        require(!mintingFinalized, "Minting finalized");
        require(amount > 0, "Invalid amount");
        
        totalMinted += amount;
        require(totalMinted <= MAX_SUPPLY, "Exceeds max supply");
        
        _mint(to, amount);
    }
    
    // Allow authorized minters to mint tokens (for future staking rewards)
    function minterMint(address to, uint256 amount) external {
        require(isMinter[msg.sender], "Not authorized minter");
        require(!mintingFinalized, "Minting finalized");
        require(to != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");
        
        totalMinted += amount;
        require(totalMinted <= MAX_SUPPLY, "Exceeds max supply");
        
        _mint(to, amount);
    }
    
    // Set minter status for address (for future staking contract)
    function setMinter(address minter, bool status) external onlyOwner {
        require(minter != address(0), "Invalid minter address");
        isMinter[minter] = status;
        emit MinterUpdated(minter, status);
    }
    
    // Finalize minting - prevents any future minting
    // Use this after all allocations (presale, team, treasury, LP) are complete
    function finalizeMinting() external onlyOwner {
        require(!mintingFinalized, "Already finalized");
        mintingFinalized = true;
        emit MintingFinalized();
    }
    
    // Get remaining supply that can be minted
    function remainingSupply() external view returns (uint256) {
        return MAX_SUPPLY - totalMinted;
    }
    
    // Check if address is authorized minter
    function canMint(address account) external view returns (bool) {
        return isMinter[account] && !mintingFinalized;
    }
    
    // Check if presale allocation has been minted
    function isPresaleAllocationMinted() external view returns (bool) {
        return presaleAllocationMinted;
    }
    
    // Get token distribution info
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
    
    // Emergency withdrawal of stuck ERC20 tokens (not ESCROW)
    function emergencyWithdrawToken(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner nonReentrant {
        require(token != address(this), "Cannot withdraw ESCROW tokens");
        require(to != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");
        
        IERC20(token).transfer(to, amount);
        emit EmergencyWithdrawal(token, to, amount);
    }
    
    // Emergency withdrawal of stuck ETH
    function emergencyWithdrawETH(address payable to) external onlyOwner nonReentrant {
        require(to != address(0), "Invalid recipient");
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");
        
        to.transfer(balance);
        emit EmergencyWithdrawal(address(0), to, balance);
    }
    
    // Override decimals to ensure 18 decimals (per ERC20 standard and whitepaper)
    function decimals() public pure override returns (uint8) {
        return 18;
    }
}