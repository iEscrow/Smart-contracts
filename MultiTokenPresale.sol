// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./Authorizer.sol";

contract MultiTokenPresale is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    
    // Gas buffer for native currency purchases
    uint256 public gasBuffer = 0.0005 ether; // Default 0.0005 ETH buffer
    
    // Token price structure
    struct TokenPrice {
        uint256 priceUSD;        // Price in USD (8 decimals)
        bool isActive;           // Whether this token is accepted
        uint8 decimals;          // Token decimals
    }
    
    // Presale token details
    IERC20 public presaleToken;
    uint256 public presaleRate;  // Tokens per USD (18 decimals)
    uint256 public maxTokensToMint;
    uint256 public totalTokensMinted;
    
    // Authorizer integration for voucher-based purchases
    Authorizer public authorizer;
    bool public voucherSystemEnabled = false; // Disabled by default for compatibility
    
    // Price management
    mapping(address => TokenPrice) public tokenPrices;
    // mapping(address => uint256) public maxPurchasePerToken;
    uint256 public maxTotalPurchasePerUser; // Total USD value limit per user
    
    // User tracking
    mapping(address => mapping(address => uint256)) public purchasedAmounts; // user => token => amount
    mapping(address => uint256) public totalPurchased; // Total tokens purchased by user
    mapping(address => uint256) public totalUsdPurchased; // User's cumulative USD spent (8 decimals)
    mapping(address => bool) public hasClaimed;
    
    // Presale timing controls
    uint256 public presaleStartTime;
    uint256 public presaleEndTime;
    bool public presaleEnded;
    
    // Scheduled launch and two rounds
    uint256 public constant PRESALE_LAUNCH_DATE = 1762819200; // Nov 11, 2025 00:00 UTC
    uint256 public constant MAX_PRESALE_DURATION = 34 days;
    uint256 public constant ROUND1_DURATION = 23 days;
    uint256 public constant ROUND2_DURATION = 11 days;
    
    uint256 public currentRound = 0; // 0 = not started, 1 = round 1, 2 = round 2
    uint256 public round1EndTime;
    uint256 public round1TokensSold;
    uint256 public round2TokensSold;
    
    // Constants
    address public constant NATIVE_ADDRESS = address(0); // ETH on Ethereum
    uint256 public constant USD_DECIMALS = 8;
    
    // Ethereum Mainnet Token Addresses
    address public constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant WBNB_ADDRESS = 0x418D75f65a02b3D53B2418FB8E1fe493759c7605;
    address public constant LINK_ADDRESS = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address public constant WBTC_ADDRESS = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT_ADDRESS = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    
    // Events
    event TokenPurchase(
        address indexed purchaser,
        address indexed beneficiary,
        address indexed paymentToken,
        uint256 paymentAmount,
        uint256 tokenAmount
    );
    
    event TokensClaimed(address indexed user, uint256 amount);
    event PriceUpdated(address indexed token, uint256 newPrice);
    event TokenStatusUpdated(address indexed token, bool isActive);
    event PresaleStarted(uint256 startTime, uint256 endTime);
    event PresaleEnded(uint256 endTime);
    event PresaleEndedEarly(string reason, uint256 endTime);
    event RoundAdvanced(uint256 fromRound, uint256 toRound, uint256 timestamp);
    event EmergencyEnd(uint256 timestamp);
    event AutoStartTriggered(uint256 timestamp);
    event GasBufferUpdated(uint256 oldBuffer, uint256 newBuffer);
    event MaxPurchasePerUserUpdated(uint256 oldMax, uint256 newMax);
    event AuthorizerUpdated(address indexed oldAuthorizer, address indexed newAuthorizer);
    event VoucherSystemToggled(bool enabled);
    event VoucherPurchase(
        address indexed purchaser,
        address indexed beneficiary,
        address indexed paymentToken,
        uint256 paymentAmount,
        uint256 tokenAmount,
        bytes32 voucherHash
    );
    
    constructor(
        address _presaleToken,
        uint256 _presaleRate, // 0.0015 dollar per token => 666.666... tokens per USD with 18 decimals: ~666666666666666667000
        uint256 _maxTokensToMint // 5 billion tokens to presale
    ) Ownable(msg.sender) {
        require(_presaleToken != address(0), "Invalid presale token");
        require(_presaleRate > 0, "Invalid presale rate");
        require(_maxTokensToMint > 0, "Invalid max tokens");
        
        presaleToken = IERC20(_presaleToken);
        presaleRate = _presaleRate;
        maxTokensToMint = _maxTokensToMint;
        
        // Initialize default token prices and limits
        _initializeDefaultTokens();
    }
    
    // ============ MODIFIERS ============
    
    // Initialize default token settings for UnityFinance presale
    function _initializeDefaultTokens() internal {
        // ETH (Native) - $4200, 18 decimals, per-token cap disabled (use global cap)
        tokenPrices[NATIVE_ADDRESS] = TokenPrice({
            priceUSD: 4200 * 1e8,  // $4200
            isActive: true,
            decimals: 18
        });
        
        // WETH - $4200, 18 decimals, per-token cap disabled (use global cap)
        tokenPrices[WETH_ADDRESS] = TokenPrice({
            priceUSD: 4200 * 1e8,  // $4200
            isActive: true,
            decimals: 18
        });

        // WBNB - $1000, 18 decimals, per-token cap disabled (use global cap)
        tokenPrices[WBNB_ADDRESS] = TokenPrice({
            priceUSD: 1000 * 1e8,   // $1000
            isActive: true,
            decimals: 18
        });
        
        
        // LINK - $20, 18 decimals, per-token cap disabled (use global cap)
        tokenPrices[LINK_ADDRESS] = TokenPrice({
            priceUSD: 20 * 1e8,    // $20
            isActive: true,
            decimals: 18
        });        
        // WBTC - $45000, 8 decimals, per-token cap disabled (use global cap)
        tokenPrices[WBTC_ADDRESS] = TokenPrice({
            priceUSD: 45000 * 1e8, // $45000
            isActive: true,
            decimals: 8
        });
        
        // USDC - $1, 6 decimals, per-token cap disabled (use global cap)
        tokenPrices[USDC_ADDRESS] = TokenPrice({
            priceUSD: 1 * 1e8,     // $1
            isActive: true,
            decimals: 6
        });
        
        // USDT - $1, 6 decimals, per-token cap disabled (use global cap)
        tokenPrices[USDT_ADDRESS] = TokenPrice({
            priceUSD: 1 * 1e8,     // $1
            isActive: true,
            decimals: 6
        });
        
        // Set total USD limit per user to $10,000 (all tokens combined)
        maxTotalPurchasePerUser = 10000 * 1e8; // $10,000 total
    }
    
    // ============ PRICE MANAGEMENT ============
    
    function setTokenPrice(
        address token,
        uint256 priceUSD,
        uint8 decimals,
        bool isActive
    ) external onlyOwner {
        require(priceUSD > 0, "Invalid price");
        require(decimals <= 18, "Invalid decimals");
        
        tokenPrices[token] = TokenPrice({
            priceUSD: priceUSD,
            isActive: isActive,
            decimals: decimals
        });
        
        emit PriceUpdated(token, priceUSD);
        emit TokenStatusUpdated(token, isActive);
    }
    
    // Presale timing controls
    function startPresale(uint256 _duration) external onlyOwner {
        require(presaleStartTime == 0, "Presale already started");
        require(_duration == MAX_PRESALE_DURATION, "Duration must match schedule");
        require(
            presaleToken.balanceOf(address(this)) >= maxTokensToMint,
            "Insufficient presale tokens in contract"
        );

        presaleStartTime = block.timestamp;
        round1EndTime = block.timestamp + ROUND1_DURATION;
        presaleEndTime = block.timestamp + _duration;
        currentRound = 1;
        presaleEnded = false;

        emit PresaleStarted(presaleStartTime, presaleEndTime);
        emit RoundAdvanced(0, 1, block.timestamp);
    }
    
    // Auto-start presale on November 11, 2025 - Anyone can trigger
    function autoStartIEscrowPresale() external {
        require(presaleStartTime == 0, "Presale already started");
        require(block.timestamp >= PRESALE_LAUNCH_DATE, "Too early - presale starts Nov 11, 2025");
        
        // Verify contract has enough presale tokens (5B $ESCROW)
        uint256 contractBalance = presaleToken.balanceOf(address(this));
        require(contractBalance >= maxTokensToMint, "Insufficient presale tokens in contract");
        
        // Start Round 1
        presaleStartTime = block.timestamp;
        round1EndTime = block.timestamp + ROUND1_DURATION;
        presaleEndTime = block.timestamp + MAX_PRESALE_DURATION;
        currentRound = 1;
        
        emit PresaleStarted(presaleStartTime, presaleEndTime);
        emit AutoStartTriggered(block.timestamp);
        emit RoundAdvanced(0, 1, block.timestamp);
    }
    
    function endPresale() external onlyOwner {
        require(presaleStartTime > 0, "Presale not started");
        require(!presaleEnded, "Presale already ended");
        if(block.timestamp < presaleEndTime) revert("Presale not ended yet");
        presaleEnded = true;
        presaleEndTime = block.timestamp;
        emit PresaleEnded(presaleEndTime);
    }
    
    function extendPresale(uint256 _additionalDuration) external onlyOwner {
        require(presaleStartTime > 0, "Presale not started");
        require(!presaleEnded, "Presale already ended");
        require(_additionalDuration <= 7 days, "Cannot extend more than 7 days");
        uint256 newEnd = presaleEndTime + _additionalDuration;
        require(
            newEnd <= presaleStartTime + MAX_PRESALE_DURATION,
            "Cannot extend beyond max duration"
        );
        presaleEndTime = newEnd;
    }
    
    // Emergency end presale immediately
    function emergencyEndPresale() external onlyOwner {
        require(presaleStartTime > 0, "Presale not started");
        require(!presaleEnded, "Presale already ended");
        
        presaleEnded = true;
        presaleEndTime = block.timestamp;
        
        emit EmergencyEnd(block.timestamp);
        emit PresaleEnded(presaleEndTime);
    }
    
    // Manually advance from Round 1 to Round 2
    function moveToRound2() external onlyOwner {
        require(currentRound == 1, "Not in round 1");
        require(!presaleEnded, "Presale already ended");
        
        currentRound = 2;
        round1EndTime = block.timestamp;
        
        emit RoundAdvanced(1, 2, block.timestamp);
    }
    
    // ============ VOUCHER-ONLY PURCHASE FUNCTIONS ============
    // NOTE: All purchases MUST use vouchers (KYC verified off-chain)
    // No direct purchase functions to prevent non-KYC purchases
    
    // ============ VOUCHER-BASED PURCHASE FUNCTIONS ============
    
    /// @notice Purchase with native currency using voucher authorization
    /// @param beneficiary Address that will receive the tokens
    /// @param voucher Purchase voucher containing authorization details
    /// @param signature EIP-712 signature of the voucher
    function buyWithNativeVoucher(
        address beneficiary,
        Authorizer.Voucher calldata voucher,
        bytes calldata signature
    ) external payable nonReentrant whenNotPaused {
        require(voucherSystemEnabled, "Voucher system not enabled");
        require(address(authorizer) != address(0), "Authorizer not set");
        require(beneficiary != address(0), "Invalid beneficiary");
        require(msg.value > 0, "No native currency sent");
        require(presaleStartTime > 0, "Presale not started");
        require(block.timestamp >= presaleStartTime, "Presale not started yet");
        require(block.timestamp <= presaleEndTime, "Presale ended");
        require(!presaleEnded, "Presale ended");
        require(voucher.buyer == msg.sender, "Only buyer can use voucher");
        require(voucher.beneficiary == beneficiary, "Beneficiary mismatch");
        require(voucher.paymentToken == NATIVE_ADDRESS, "Invalid payment token");
        
        TokenPrice memory nativePrice = tokenPrices[NATIVE_ADDRESS];
        require(nativePrice.isActive, "Native currency not accepted");
        
        // Estimate gas cost and deduct from payment
        uint256 gasCost = _estimateGasCost();
        require(msg.value > gasCost, "Insufficient payment after gas");
        
        uint256 paymentAmount = msg.value - gasCost;
        
        // Calculate USD amount for authorization
        uint256 usdAmount = (paymentAmount * nativePrice.priceUSD) / (10 ** nativePrice.decimals);
        
        // Authorize purchase with voucher
        bool authorized = authorizer.authorize(voucher, signature, NATIVE_ADDRESS, usdAmount);
        require(authorized, "Voucher authorization failed");
        
        uint256 tokenAmount = _calculateTokenAmountForVoucher(NATIVE_ADDRESS, paymentAmount, beneficiary, usdAmount);
        _processVoucherPurchase(beneficiary, NATIVE_ADDRESS, paymentAmount, tokenAmount, voucher);
    }
    
    /// @notice Purchase with ERC20 tokens using voucher authorization
    /// @param token Payment token address
    /// @param amount Payment token amount
    /// @param beneficiary Address that will receive the tokens
    /// @param voucher Purchase voucher containing authorization details
    /// @param signature EIP-712 signature of the voucher
    function buyWithTokenVoucher(
        address token,
        uint256 amount,
        address beneficiary,
        Authorizer.Voucher calldata voucher,
        bytes calldata signature
    ) external nonReentrant whenNotPaused {
        require(voucherSystemEnabled, "Voucher system not enabled");
        require(address(authorizer) != address(0), "Authorizer not set");
        require(beneficiary != address(0), "Invalid beneficiary");
        require(amount > 0, "Invalid amount");
        require(token != NATIVE_ADDRESS, "Use buyWithNativeVoucher for native currency");
        require(presaleStartTime > 0, "Presale not started");
        require(block.timestamp >= presaleStartTime, "Presale not started yet");
        require(block.timestamp <= presaleEndTime, "Presale ended");
        require(!presaleEnded, "Presale ended");
        require(voucher.buyer == msg.sender, "Only buyer can use voucher");
        require(voucher.beneficiary == beneficiary, "Beneficiary mismatch");
        require(voucher.paymentToken == token, "Invalid payment token");
        
        TokenPrice memory tokenPrice = tokenPrices[token];
        require(tokenPrice.isActive, "Token not accepted");
        
        // Calculate USD amount for authorization
        uint256 usdAmount = (amount * tokenPrice.priceUSD) / (10 ** tokenPrice.decimals);
        
        // Authorize purchase with voucher
        bool authorized = authorizer.authorize(voucher, signature, token, usdAmount);
        require(authorized, "Voucher authorization failed");
        
        // Transfer tokens with deflationary token compatibility check
        uint256 beforeBalance = IERC20(token).balanceOf(address(this));
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        uint256 received = IERC20(token).balanceOf(address(this)) - beforeBalance;
        require(received == amount, "Deflationary token not supported");
        
        uint256 tokenAmount = _calculateTokenAmountForVoucher(token, amount, beneficiary, usdAmount);
        _processVoucherPurchase(beneficiary, token, amount, tokenAmount, voucher);
    }
    
    // ============ INTERNAL FUNCTIONS ============
    
    function _calculateTokenAmount(address paymentToken, uint256 paymentAmount, address beneficiary) internal returns (uint256) {
        TokenPrice memory price = tokenPrices[paymentToken];
        require(price.isActive, "Token not accepted");
        
        // Convert payment amount to USD value
        uint256 usdValue = (paymentAmount * price.priceUSD) / (10 ** price.decimals * 10 ** USD_DECIMALS);

        // GRO-04: Enforce per-user purchase limit
        require(totalUsdPurchased[beneficiary] + usdValue * 1e8 <= maxTotalPurchasePerUser, "Exceeds per-user cap");
        
        // Track USD spent for analytics
        totalUsdPurchased[beneficiary] += usdValue * 1e8;
        
        // Calculate presale tokens (limit enforced at total token level in _processPurchase)
        return (usdValue * presaleRate) ;
    }
    
    /// @notice Calculate token amount for voucher purchases (USD amount already calculated in 8 decimals)
    function _calculateTokenAmountForVoucher(address paymentToken, uint256 paymentAmount, address beneficiary, uint256 usdAmount) internal returns (uint256) {
        TokenPrice memory price = tokenPrices[paymentToken];
        require(price.isActive, "Token not accepted");
        
        // GRO-04: Enforce per-user purchase limit
        require(totalUsdPurchased[beneficiary] + usdAmount <= maxTotalPurchasePerUser, "Exceeds per-user cap");
        
        // Track USD spent for analytics (usdAmount already has 8 decimals)
        totalUsdPurchased[beneficiary] += usdAmount;
        
        // Calculate presale tokens: usdAmount (8 dec) * presaleRate (18 dec) / 1e8 = tokens (18 dec)
        return (usdAmount * presaleRate) / 1e8;
    }
    
    function _processPurchase(
        address beneficiary,
        address paymentToken,
        uint256 paymentAmount,
        uint256 tokenAmount
    ) internal {     
        // Check if we can mint enough tokens
        require(totalTokensMinted + tokenAmount <= maxTokensToMint, "Not enough tokens left");
        
        // Update tracking
        purchasedAmounts[beneficiary][paymentToken] += paymentAmount;
        totalPurchased[beneficiary] += tokenAmount;
        totalTokensMinted += tokenAmount;
        
        // Track tokens sold per round
        if (currentRound == 1) {
            round1TokensSold += tokenAmount;
        } else if (currentRound == 2) {
            round2TokensSold += tokenAmount;
        }
        
        emit TokenPurchase(msg.sender, beneficiary, paymentToken, paymentAmount, tokenAmount);
        
        // Check auto-end conditions
        _checkAutoEndConditions();
    }
    
    /// @notice Process voucher-based purchase
    function _processVoucherPurchase(
        address beneficiary,
        address paymentToken,
        uint256 paymentAmount,
        uint256 tokenAmount,
        Authorizer.Voucher calldata voucher
    ) internal {     
        // Check if we can mint enough tokens
        require(totalTokensMinted + tokenAmount <= maxTokensToMint, "Not enough tokens left");
        
        // Update tracking
        purchasedAmounts[beneficiary][paymentToken] += paymentAmount;
        totalPurchased[beneficiary] += tokenAmount;
        totalTokensMinted += tokenAmount;
        
        // Track tokens sold per round
        if (currentRound == 1) {
            round1TokensSold += tokenAmount;
        } else if (currentRound == 2) {
            round2TokensSold += tokenAmount;
        }
        
        // Generate voucher hash for event
        bytes32 voucherHash = keccak256(abi.encode(
            voucher.buyer,
            voucher.beneficiary,
            voucher.paymentToken,
            voucher.usdLimit,
            voucher.nonce,
            voucher.deadline,
            voucher.presale
        ));
        
        emit VoucherPurchase(msg.sender, beneficiary, paymentToken, paymentAmount, tokenAmount, voucherHash);
        emit TokenPurchase(msg.sender, beneficiary, paymentToken, paymentAmount, tokenAmount);
        
        // Check auto-end conditions
        _checkAutoEndConditions();
    }
    
    // Check if presale should auto-end
    function _checkAutoEndConditions() internal {
        // Prevent overwrites if already ended
        if (presaleEnded) return;

        // End if all tokens sold
        if (totalTokensMinted >= maxTokensToMint) {
            presaleEnded = true;
            presaleEndTime = block.timestamp;
            emit PresaleEndedEarly("All tokens sold", block.timestamp);
            emit PresaleEnded(block.timestamp);
            return;
        }
        
        // End if 34 days passed
        if (block.timestamp >= presaleStartTime + MAX_PRESALE_DURATION) {
            presaleEnded = true;
            presaleEndTime = block.timestamp;
            emit PresaleEndedEarly("Maximum duration reached", block.timestamp);
            emit PresaleEnded(block.timestamp);
            return;
        }
        
        // Auto-advance from Round 1 to Round 2 if Round 1 time is up
        if (currentRound == 1 && block.timestamp >= round1EndTime) {
            currentRound = 2;
            round1EndTime = block.timestamp; // Mark actual end time
            emit RoundAdvanced(1, 2, block.timestamp);
        }
    }
    
    // ============ CLAIM FUNCTIONS ============
    
    function claimTokens() external nonReentrant whenNotPaused {
        require(totalPurchased[msg.sender] > 0, "No tokens to claim");
        require(!hasClaimed[msg.sender], "Already claimed");
        require(presaleEnded, "Presale not ended yet");
        
        uint256 claimAmount = totalPurchased[msg.sender];
        hasClaimed[msg.sender] = true;
        
        presaleToken.safeTransfer(msg.sender, claimAmount);
        
        emit TokensClaimed(msg.sender, claimAmount);
    }
    
    // ============ ADMIN FUNCTIONS ============
    
    function withdrawNative() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No native currency to withdraw");
        payable(owner()).transfer(balance);
    }
    
    function withdrawToken(address token) external onlyOwner {
        require(token != address(presaleToken), "Cannot withdraw presale tokens directly");

        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "No tokens to withdraw");
        IERC20(token).safeTransfer(owner(), balance);
    }
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    // ============ VIEW FUNCTIONS ============
    
    function getTokenPrice(address token) external view returns (TokenPrice memory) {
        return tokenPrices[token];
    }
    
    function getUserPurchases(address user) external view returns (
        uint256 nativeAmount,
        uint256 totalTokens,
        bool claimed
    ) {
        nativeAmount = purchasedAmounts[user][NATIVE_ADDRESS];
        totalTokens = totalPurchased[user];
        claimed = hasClaimed[user];
    }
    
    function calculateTokenAmount(address paymentToken, uint256 paymentAmount, address beneficiary) external view returns (uint256) {
        TokenPrice memory price = tokenPrices[paymentToken];
        require(price.isActive, "Token not accepted");
        
        // Convert payment amount to USD value
        uint256 usdValue = (paymentAmount * price.priceUSD) / (10 ** price.decimals * 10 ** USD_DECIMALS);
        
        // View function for external queries - no limits enforced here
        // Per-user and total token supply limits enforced in actual purchase functions
        // Calculate presale tokens
        return (usdValue * presaleRate);
    }
    
    function getRemainingTokens() external view returns (uint256) {
        return maxTokensToMint - totalTokensMinted;
    }
    
    // Presale status functions
    function getPresaleStatus() external view returns (
        bool started,
        bool ended,
        uint256 startTime,
        uint256 endTime,
        uint256 currentTime
    ) {
        started = presaleStartTime > 0;
        ended = presaleEnded;
        startTime = presaleStartTime;
        endTime = presaleEndTime;
        currentTime = block.timestamp;
    }
    
    function isPresaleActive() external view returns (bool) {
        return presaleStartTime > 0 && 
               block.timestamp >= presaleStartTime && 
               block.timestamp <= presaleEndTime && 
               !presaleEnded;
    }
    
    function canClaim() external view returns (bool) {
        return presaleEnded;
    }
    
    // Get comprehensive presale status
    function getIEscrowPresaleStatus() external view returns (
        uint256 currentRoundNumber,
        uint256 roundTimeRemaining,
        uint256 totalTimeRemaining,
        uint256 tokensRemainingTotal,
        uint256 round1Sold,
        uint256 round2Sold,
        bool canPurchase,
        string memory statusMessage
    ) {
        currentRoundNumber = currentRound;
        round1Sold = round1TokensSold;
        round2Sold = round2TokensSold;
        tokensRemainingTotal = maxTokensToMint - totalTokensMinted;
        
        if (presaleEnded) {
            canPurchase = false;
            statusMessage = "Presale ended";
            roundTimeRemaining = 0;
            totalTimeRemaining = 0;
        } else if (currentRound == 0) {
            canPurchase = false;
            statusMessage = "Presale starts Nov 11, 2025";
            roundTimeRemaining = block.timestamp >= PRESALE_LAUNCH_DATE ? 0 : PRESALE_LAUNCH_DATE - block.timestamp;
            totalTimeRemaining = roundTimeRemaining;
        } else if (currentRound == 1) {
            canPurchase = true;
            statusMessage = "Round 1 Active";
            roundTimeRemaining = block.timestamp >= round1EndTime ? 0 : round1EndTime - block.timestamp;
            totalTimeRemaining = block.timestamp >= presaleEndTime ? 0 : presaleEndTime - block.timestamp;
        } else if (currentRound == 2) {
            canPurchase = true;
            statusMessage = "Round 2 Active";
            roundTimeRemaining = block.timestamp >= presaleEndTime ? 0 : presaleEndTime - block.timestamp;
            totalTimeRemaining = roundTimeRemaining;
        }
        
        return (currentRoundNumber, roundTimeRemaining, totalTimeRemaining, tokensRemainingTotal, round1Sold, round2Sold, canPurchase, statusMessage);
    }
    
    // Get round allocation details
    function getRoundAllocation() external view returns (
        uint256 round1Sold,
        uint256 round2Sold,
        uint256 round1Remaining,
        uint256 round2Remaining,
        uint256 totalRemaining
    ) {
        round1Sold = round1TokensSold;
        round2Sold = round2TokensSold;
        totalRemaining = maxTokensToMint - totalTokensMinted;
        
        // For display purposes - no hard limits per round in iEscrow spec
        round1Remaining = totalRemaining;
        round2Remaining = totalRemaining;
        
        return (round1Sold, round2Sold, round1Remaining, round2Remaining, totalRemaining);
    }
    
    // Validate contract setup before launch
    function validateIEscrowSetup() external view returns (
        bool hasCorrectTokens,
        bool startDateConfigured,
        bool limitsConfigured,
        bool tokensDeposited,
        string memory issues
    ) {
        hasCorrectTokens = true; // All 7 tokens configured in constructor
        startDateConfigured = PRESALE_LAUNCH_DATE == 1762819200; // Nov 11, 2025
        limitsConfigured = maxTokensToMint == 5000000000 * 1e18; // 5B tokens
        
        uint256 contractBalance = presaleToken.balanceOf(address(this));
        tokensDeposited = contractBalance >= maxTokensToMint;
        
        if (!tokensDeposited) {
            issues = "Insufficient ESCROW tokens in contract";
        } else if (!startDateConfigured) {
            issues = "Incorrect start date";
        } else if (!limitsConfigured) {
            issues = "Incorrect token limits";
        } else {
            issues = "Setup validated - ready for launch";
        }
        
        return (hasCorrectTokens, startDateConfigured, limitsConfigured, tokensDeposited, issues);
    }
    
    // Anyone can call to trigger auto-end checks
    function checkAutoEndConditions() external {
        require(presaleStartTime > 0, "Presale not started");
        require(!presaleEnded, "Presale already ended");
        _checkAutoEndConditions();
    }
    
    // Helper functions for USD value calculations
    function _getUSDValue(address token, uint256 amount) internal view returns (uint256) {
        TokenPrice memory price = tokenPrices[token];
        return (amount * price.priceUSD) / (10 ** price.decimals * 10 ** USD_DECIMALS);
    }
    
    function _getUserTotalUSDValue(address user) internal view returns (uint256) {
        return totalUsdPurchased[user];
    }
    
    function getUserTotalUSDValue(address user) external view returns (uint256) {
        return totalUsdPurchased[user];
    }
    
    // Get all supported tokens information
    function getSupportedTokens() external view returns (
        address[] memory tokens,
        string[] memory symbols,
        uint256[] memory prices,
        uint256[] memory maxPurchases,
        bool[] memory active
    ) {
        tokens = new address[](7);
        symbols = new string[](7);
        prices = new uint256[](7);
        maxPurchases = new uint256[](7);
        active = new bool[](7);
        
        tokens[0] = NATIVE_ADDRESS;
        symbols[0] = "ETH";
        prices[0] = tokenPrices[NATIVE_ADDRESS].priceUSD;
        maxPurchases[0] = maxTotalPurchasePerUser;
        active[0] = tokenPrices[NATIVE_ADDRESS].isActive;
        
        tokens[1] = WETH_ADDRESS;
        symbols[1] = "WETH";
        prices[1] = tokenPrices[WETH_ADDRESS].priceUSD;
        maxPurchases[1] = maxTotalPurchasePerUser;
        active[1] = tokenPrices[WETH_ADDRESS].isActive;
        
        tokens[2] = WBNB_ADDRESS;
        symbols[2] = "WBNB";
        prices[2] = tokenPrices[WBNB_ADDRESS].priceUSD;
        maxPurchases[2] = maxTotalPurchasePerUser;
        active[2] = tokenPrices[WBNB_ADDRESS].isActive;
        
        tokens[3] = LINK_ADDRESS;
        symbols[3] = "LINK";
        prices[3] = tokenPrices[LINK_ADDRESS].priceUSD;
        maxPurchases[3] = maxTotalPurchasePerUser;
        active[3] = tokenPrices[LINK_ADDRESS].isActive;
        
        tokens[4] = WBTC_ADDRESS;
        symbols[4] = "WBTC";
        prices[4] = tokenPrices[WBTC_ADDRESS].priceUSD;
        maxPurchases[4] = maxTotalPurchasePerUser;
        active[4] = tokenPrices[WBTC_ADDRESS].isActive;
        
        tokens[5] = USDC_ADDRESS;
        symbols[5] = "USDC";
        prices[5] = tokenPrices[USDC_ADDRESS].priceUSD;
        maxPurchases[5] = maxTotalPurchasePerUser;
        active[5] = tokenPrices[USDC_ADDRESS].isActive;
        
        tokens[6] = USDT_ADDRESS;
        symbols[6] = "USDT";
        prices[6] = tokenPrices[USDT_ADDRESS].priceUSD;
        maxPurchases[6] = maxTotalPurchasePerUser;
        active[6] = tokenPrices[USDT_ADDRESS].isActive;
    }
    
    // Get user's purchases for all tokens
    function getUserAllPurchases(address user) external view returns (
        uint256[] memory amounts,
        uint256[] memory usdValues
    ) {
        amounts = new uint256[](7);
        usdValues = new uint256[](7);
        
        address[] memory tokens = new address[](7);
        tokens[0] = NATIVE_ADDRESS;
        tokens[1] = WETH_ADDRESS;
        tokens[2] = WBNB_ADDRESS;
        tokens[3] = LINK_ADDRESS;
        tokens[4] = WBTC_ADDRESS;
        tokens[5] = USDC_ADDRESS;
        tokens[6] = USDT_ADDRESS;
        
        for (uint256 i = 0; i < tokens.length; i++) {
            amounts[i] = purchasedAmounts[user][tokens[i]];
            if (amounts[i] > 0) {
                usdValues[i] = _getUSDValue(tokens[i], amounts[i]);
            }
        }
    }
    
    // Gas estimation function
    function _estimateGasCost() internal view returns (uint256) {
        // Get current gas price
        uint256 gasPrice = tx.gasprice;
        
        // Estimate gas usage based on operation complexity
        uint256 estimatedGasUsed = _getEstimatedGasUsage();
        
        // Add 20% buffer for safety
        uint256 gasWithBuffer = (estimatedGasUsed * 120) / 100;
        
        return gasPrice * gasWithBuffer;
    }
    
    // Estimate gas usage based on operation
    function _getEstimatedGasUsage() internal pure returns (uint256) {
        // Base gas for contract call
        uint256 baseGas = 21000;
        
        // Gas for storage operations
        uint256 storageGas = 20000; // For updating mappings
        
        // Gas for calculations
        uint256 calculationGas = 10000; // For price calculations
        
        // Gas for events
        uint256 eventGas = 5000; // For emitting events
        
        return baseGas + storageGas + calculationGas + eventGas;
    }
    
    function setGasBuffer(uint256 _gasBuffer) external onlyOwner {
        uint256 oldBuffer = gasBuffer;
        gasBuffer = _gasBuffer;
        emit GasBufferUpdated(oldBuffer, _gasBuffer);
    }
    
    
    // ============ AUTHORIZER MANAGEMENT FUNCTIONS ============
    
    /// @notice Update the Authorizer contract address
    /// @param _authorizer New Authorizer contract address
    function updateAuthorizer(address _authorizer) external onlyOwner {
        address oldAuthorizer = address(authorizer);
        authorizer = Authorizer(_authorizer);
        emit AuthorizerUpdated(oldAuthorizer, _authorizer);
    }
    
    /// @notice Toggle voucher system on/off
    /// @param _enabled Whether voucher system is enabled
    function setVoucherSystemEnabled(bool _enabled) external onlyOwner {
        voucherSystemEnabled = _enabled;
        emit VoucherSystemToggled(_enabled);
    }
    
    /// @notice Get Authorizer contract address and system status
    /// @return authorizerAddress Address of the Authorizer contract
    /// @return enabled Whether voucher system is enabled
    function getAuthorizerInfo() external view returns (address authorizerAddress, bool enabled) {
        authorizerAddress = address(authorizer);
        enabled = voucherSystemEnabled;
    }
    
    /// @notice Validate a voucher without consuming it (view function)
    /// @param voucher The purchase voucher to validate
    /// @param signature EIP-712 signature of the voucher
    /// @param paymentToken Token being used for payment
    /// @param usdAmount USD amount being purchased (8 decimals)
    /// @return valid True if voucher is valid
    /// @return reason Reason for invalidity (empty if valid)
    function validateVoucher(
        Authorizer.Voucher calldata voucher,
        bytes calldata signature,
        address paymentToken,
        uint256 usdAmount
    ) external view returns (bool valid, string memory reason) {
        if (!voucherSystemEnabled) {
            return (false, "Voucher system not enabled");
        }
        if (address(authorizer) == address(0)) {
            return (false, "Authorizer not set");
        }
        return authorizer.validateVoucher(voucher, signature, paymentToken, usdAmount);
    }
    
}
