// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title EscrowToken - The utility token for the iEscrow ecosystem
/// @notice Standard ERC20 with 18 decimals, ERC20Permit for gasless approvals, and burnable tokens
/// @dev Max supply: 100 billion tokens, Presale allocation: 5 billion tokens
contract EscrowToken is ERC20, ERC20Permit, ERC20Burnable, Ownable, ReentrancyGuard {
    
    using SafeERC20 for IERC20;
    // ============ CONSTANTS ============
    
    /// @notice Maximum total supply of tokens
    /// @dev 100 billion tokens
    uint256 public constant MAX_SUPPLY = 100_000_000_000 * 1e18; // 100 billion tokens
    /// @notice Allocation for presale
    /// @dev 5 billion tokens
    uint256 public constant PRESALE_ALLOCATION = 5_000_000_000 * 1e18; // 5 billion for presale
    /// @notice Allocation for marketing, CEX listings and partnerships
    uint256 public constant MARKETING_ALLOCATION = 3_400_000_000 * 1e18; // 3.4 billion for marketing/partnerships
    /// @notice Allocation for initial DEX liquidity
    uint256 public constant LIQUIDITY_ALLOCATION = 5_000_000_000 * 1e18; // 5 billion for liquidity provision
    
    /// @notice Wallet receiving the marketing/partnership allocation
    address public constant MARKETING_WALLET = 0xa315b46cA80982278eD28A3496718B1524Df467b;
    /// @notice Wallet receiving the initial liquidity allocation
    address public constant LIQUIDITY_WALLET = 0x5f5868Bb7E708aAb9C25c80AEBFA0131735233af;
    
    // ============ STATE VARIABLES ============
    
    /// @notice Total amount of tokens minted so far
    uint256 public totalMinted;
    /// @notice Whether minting has been permanently finalized
    bool public mintingFinalized;
    /// @notice Whether the presale allocation has been minted
    bool public presaleAllocationMinted;
    /// @notice Flag signalling bootstrap phase is complete and owner minting is disabled
    bool public bootstrapComplete;
    /// @notice Address of the staking contract that is allowed to mint rewards
    address public stakingContract;
    
    // ============ EVENTS ============
    
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
    /// @notice Emitted when bootstrap is completed and the staking contract is set
    /// @param staking The staking contract that is now authorised to mint rewards
    event BootstrapCompleted(address indexed staking);

    modifier onlyBeforeBootstrap() {
        require(!bootstrapComplete, "Bootstrap already completed");
        _;
    }

    modifier onlyStakingContract() {
        require(msg.sender == stakingContract, "Caller is not staking contract");
        _;
    }

    // ============ CONSTRUCTOR ============
    
    /// @notice Contract constructor
    /// @dev Initializes the ERC20 token with name and symbol, sets owner
    constructor() 
        ERC20("Escrow Token", "ESCROW") 
        ERC20Permit("Escrow Token")
        Ownable(msg.sender)
    {
        _mintInitialAllocation(MARKETING_WALLET, MARKETING_ALLOCATION);
        _mintInitialAllocation(LIQUIDITY_WALLET, LIQUIDITY_ALLOCATION);
    }
    
    /// @notice Helper for constructor to mint initial allocations and track totals
    /// @param to Address receiving the allocation
    /// @param amount Amount of tokens to mint
    function _mintInitialAllocation(address to, uint256 amount) internal {
        require(to != address(0), "Invalid allocation recipient");
        totalMinted += amount;
        require(totalMinted <= MAX_SUPPLY, "Exceeds max supply");
        _mint(to, amount);
    }
    
    // ============ MINTING FUNCTIONS ============
    
    /// @notice Mint the presale allocation (5B tokens), set staking contract, and complete bootstrap
    /// @param presaleContract Address of the presale contract
    /// @param staking Address of the staking contract authorised to mint rewards
    function mintPresaleAllocation(address presaleContract, address staking) external onlyOwner onlyBeforeBootstrap {
        require(presaleContract != address(0), "Invalid presale contract");
        require(staking != address(0), "Invalid staking contract");
        require(!mintingFinalized, "Minting finalized");
        require(!presaleAllocationMinted, "Presale allocation already minted");
        
        presaleAllocationMinted = true;
        totalMinted += PRESALE_ALLOCATION;
        
        _mint(presaleContract, PRESALE_ALLOCATION);
        emit PresaleAllocationMinted(presaleContract, PRESALE_ALLOCATION);
        
        stakingContract = staking;
        bootstrapComplete = true;
        emit BootstrapCompleted(staking);
    }
    
    /// @notice Mint rewards, callable only by the staking contract after bootstrap
    /// @param to Address receiving the freshly minted tokens
    /// @param amount Amount of tokens to mint
    function mintRewards(address to, uint256 amount) external onlyStakingContract {
        require(bootstrapComplete, "Bootstrap incomplete");
        require(!mintingFinalized, "Minting finalized");
        require(to != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");

        totalMinted += amount;
        require(totalMinted <= MAX_SUPPLY, "Exceeds max supply");

        _mint(to, amount);
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
        return bootstrapComplete && !mintingFinalized && account == stakingContract;
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
        
        IERC20(token).safeTransfer(to, amount);
        emit EmergencyWithdrawal(token, to, amount);
    }
    
    /// @notice Emergency withdrawal of stuck ETH
    /// @param to Address to send the ETH to
    function emergencyWithdrawETH(address payable to) external onlyOwner nonReentrant {
        require(to != address(0), "Invalid recipient");
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");
        
        Address.sendValue(payable(to), balance);
        emit EmergencyWithdrawal(address(0), to, balance);
    }
    
    // ============ OVERRIDES ============
    
    /// @notice Override decimals to ensure 18 decimals (per ERC20 standard and whitepaper)
    /// @return Number of decimals (always 18)
    function decimals() public pure override returns (uint8) {
        return 18;
    }
}
