// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title iEscrowPresale
 * @dev Enterprise-grade presale contract for $ESCROW token
 * @notice 2-round presale: Round 1 (23 days) + Round 2 (11 days)
 * @custom:security-contact security@iescrow.com
 */
contract iEscrowPresale is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    
    // ============ TYPE DECLARATIONS ============
    
    enum PresaleRound { NOT_STARTED, ROUND_1, ROUND_2, ENDED }
    
    struct TokenPrice {
        uint256 priceUSD;        // Price in USD (8 decimals precision)
        bool isActive;           // Whether this token is accepted for payment
        uint8 decimals;          // Token decimals for accurate calculations
    }
    
    struct RoundConfig {
        uint256 tokenPrice;      // Price per token in USD (8 decimals)
        uint256 maxTokens;       // Maximum tokens for this round
        uint256 tokensSold;      // Tokens sold in this round
        uint256 duration;        // Duration in seconds
        uint256 startTime;       // Start timestamp
        uint256 endTime;         // End timestamp
    }
    
    struct UserInfo {
        uint256 totalTokensPurchased;    // Total presale tokens allocated
        uint256 totalUSDSpent;           // Total USD value spent (8 decimals)
        uint256 round1Purchased;         // Tokens purchased in round 1
        uint256 round2Purchased;         // Tokens purchased in round 2
        bool hasClaimed;                 // Whether user has claimed tokens
    }
    
    // ============ STATE VARIABLES ============
    
    // Token configuration
    IERC20 public immutable escrowToken;
    uint256 public constant TOTAL_PRESALE_TOKENS = 5_000_000_000 * 1e18; // 5 billion tokens
    uint256 public totalTokensSold;
    uint256 public totalUSDRaised;
    
    // Round configurations
    mapping(uint256 => RoundConfig) public rounds;
    PresaleRound public currentRound;
    
    // Payment token management
    mapping(address => TokenPrice) public tokenPrices;
    address[] private acceptedTokensList;
    mapping(address => bool) private isTokenAccepted;
    
    // User tracking
    uint256 public maxPurchasePerUser;           // Maximum USD value per user (8 decimals)
    uint256 public minPurchaseAmount;            // Minimum purchase in USD (8 decimals)
    mapping(address => UserInfo) public userInfo;
    mapping(address => mapping(address => uint256)) public userTokenPurchases;
    address[] private participants;
    mapping(address => bool) private hasParticipated;
    
    // Presale state
    bool public presaleFinalized;
    bool public presaleCancelled;
    uint256 public presaleStartTime;
    
    // Claims configuration
    bool public claimsEnabled;
    uint256 public tgeTime;
    
    // Whitelist (optional)
    bool public whitelistEnabled;
    mapping(address => bool) public whitelist;
    mapping(address => uint256) public whitelistAllocation;
    
    // Referral system
    bool public referralEnabled;
    mapping(address => address) public referrer;
    mapping(address => uint256) public referralBonus;
    uint256 public referralBonusPercentage = 500; // 5%
    
    // Treasury
    address public treasury;
    uint256 public gasBuffer = 0.001 ether;
    mapping(address => uint256) public collectedFunds;
    
    // Token addresses (Ethereum Mainnet)
    address public constant NATIVE_TOKEN = address(0);
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant WBNB = 0x418D75f65a02b3D53B2418FB8E1fe493759c7605;
    address public constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    
    // Constants
    uint256 public constant USD_DECIMALS = 8;
    uint256 public constant PRICE_PRECISION = 1e8;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 private constant MAX_PARTICIPANTS = 50000;
    
    // ============ EVENTS ============
    
    event PresaleStarted(uint256 timestamp, PresaleRound round);
    event RoundTransitioned(PresaleRound fromRound, PresaleRound toRound, uint256 timestamp);
    event TokenPurchase(
        address indexed purchaser,
        address indexed beneficiary,
        address indexed paymentToken,
        uint256 paymentAmount,
        uint256 tokenAmount,
        uint256 usdValue,
        PresaleRound round
    );
    event TokensClaimed(address indexed user, uint256 amount, uint256 timestamp);
    event PresaleFinalized(uint256 timestamp, uint256 totalSold, uint256 totalRaised);
    event PresaleCancelled(uint256 timestamp);
    event ClaimsEnabled(uint256 timestamp);
    event TGEScheduled(uint256 tgeTime);
    event TokenPriceUpdated(address indexed token, uint256 newPrice, bool isActive);
    event WhitelistUpdated(address indexed user, bool status, uint256 allocation);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event RoundConfigUpdated(uint256 indexed roundId, uint256 price, uint256 maxTokens, uint256 duration);
    event ReferralRecorded(address indexed user, address indexed referrer, uint256 bonusTokens);
    event EmergencyRefund(address indexed user, uint256 amount);
    
    // ============ ERRORS ============
    
    error InvalidAddress();
    error InvalidAmount();
    error InvalidParameters();
    error PresaleNotStarted();
    error PresaleEnded();
    error PresaleNotEnded();
    error PresaleAlreadyFinalized();
    error PresaleNotFinalized();
    error PresaleCancelledError();
    error RoundNotActive();
    error RoundSoldOut();
    error TokenNotAccepted();
    error InsufficientPayment();
    error BelowMinimumPurchase();
    error ExceedsMaximumPurchase();
    error ExceedsRoundCap();
    error NotWhitelisted();
    error ExceedsAllocation();
    error ClaimsNotEnabled();
    error NothingToClaim();
    error AlreadyClaimed();
    error TransferFailed();
    error InsufficientTokenBalance();
    error MaxParticipantsReached();
    error InvalidReferrer();
    error WrongRound();
    
    // ============ MODIFIERS ============
    
    modifier onlyWhitelisted() {
        if (whitelistEnabled && !whitelist[msg.sender]) revert NotWhitelisted();
        _;
    }
    
    modifier presaleActive() {
        if (presaleCancelled) revert PresaleCancelledError();
        if (currentRound == PresaleRound.NOT_STARTED) revert PresaleNotStarted();
        if (currentRound == PresaleRound.ENDED) revert PresaleEnded();
        if (presaleFinalized) revert PresaleAlreadyFinalized();
        _;
    }
    
    modifier validAddress(address _address) {
        if (_address == address(0)) revert InvalidAddress();
        _;
    }
    
    // ============ CONSTRUCTOR ============
    
    constructor(
        address _escrowToken,
        address _treasury
    ) Ownable(msg.sender) validAddress(_escrowToken) validAddress(_treasury) {
        escrowToken = IERC20(_escrowToken);
        treasury = _treasury;
        
        // Set default limits
        maxPurchasePerUser = 10000 * PRICE_PRECISION; // $10,000 max per user
        minPurchaseAmount = 50 * PRICE_PRECISION;      // $50 minimum
        
        // Initialize Round 1: 23 days, price TBD by owner
        rounds[1] = RoundConfig({
            tokenPrice: 0,           // Will be set by owner before start
            maxTokens: 0,            // Will be set by owner before start
            tokensSold: 0,
            duration: 23 days,
            startTime: 0,
            endTime: 0
        });
        
        // Initialize Round 2: 11 days, price TBD by owner
        rounds[2] = RoundConfig({
            tokenPrice: 0,           // Will be set by owner before start
            maxTokens: 0,            // Will be set by owner before start
            tokensSold: 0,
            duration: 11 days,
            startTime: 0,
            endTime: 0
        });
        
        currentRound = PresaleRound.NOT_STARTED;
        
        // Initialize payment tokens
        _initializePaymentTokens();
    }
    
    // ============ INITIALIZATION ============
    
    function _initializePaymentTokens() private {
        // ETH/Native
        _addPaymentToken(NATIVE_TOKEN, 3500 * PRICE_PRECISION, 18, true);
        
        // WETH
        _addPaymentToken(WETH, 3500 * PRICE_PRECISION, 18, true);
        
        // WBNB
        _addPaymentToken(WBNB, 600 * PRICE_PRECISION, 18, true);
        
        // LINK
        _addPaymentToken(LINK, 15 * PRICE_PRECISION, 18, true);
        
        // WBTC
        _addPaymentToken(WBTC, 95000 * PRICE_PRECISION, 8, true);
        
        // USDC
        _addPaymentToken(USDC, 1 * PRICE_PRECISION, 6, true);
        
        // USDT
        _addPaymentToken(USDT, 1 * PRICE_PRECISION, 6, true);
    }
    
    function _addPaymentToken(address token, uint256 price, uint8 decimals, bool active) private {
        tokenPrices[token] = TokenPrice({
            priceUSD: price,
            isActive: active,
            decimals: decimals
        });
        
        if (!isTokenAccepted[token]) {
            acceptedTokensList.push(token);
            isTokenAccepted[token] = true;
        }
    }
    
    // ============ PRESALE MANAGEMENT ============
    
    /**
     * @dev Configure round settings before starting presale
     * @param roundId Round number (1 or 2)
     * @param tokenPriceUSD Price per token in USD (8 decimals)
     * @param maxTokens Maximum tokens for this round
     */
    function configureRound(
        uint256 roundId,
        uint256 tokenPriceUSD,
        uint256 maxTokens
    ) external onlyOwner {
        if (roundId < 1 || roundId > 2) revert InvalidParameters();
        if (tokenPriceUSD == 0 || maxTokens == 0) revert InvalidParameters();
        if (presaleStartTime != 0) revert InvalidParameters(); // Can't change after start
        
        RoundConfig storage round = rounds[roundId];
        round.tokenPrice = tokenPriceUSD;
        round.maxTokens = maxTokens;
        
        emit RoundConfigUpdated(roundId, tokenPriceUSD, maxTokens, round.duration);
    }
    
    /**
     * @dev Start the presale (begins with Round 1)
     */
    function startPresale() external onlyOwner {
        if (presaleStartTime != 0) revert InvalidParameters();
        if (rounds[1].tokenPrice == 0 || rounds[1].maxTokens == 0) revert InvalidParameters();
        if (rounds[2].tokenPrice == 0 || rounds[2].maxTokens == 0) revert InvalidParameters();
        
        uint256 contractBalance = escrowToken.balanceOf(address(this));
        if (contractBalance < TOTAL_PRESALE_TOKENS) revert InsufficientTokenBalance();
        
        presaleStartTime = block.timestamp;
        currentRound = PresaleRound.ROUND_1;
        
        // Set Round 1 times
        rounds[1].startTime = block.timestamp;
        rounds[1].endTime = block.timestamp + rounds[1].duration;
        
        emit PresaleStarted(block.timestamp, PresaleRound.ROUND_1);
    }
    
    /**
     * @dev Transition from Round 1 to Round 2 (automatic or manual)
     */
    function startRound2() external onlyOwner {
        if (currentRound != PresaleRound.ROUND_1) revert WrongRound();
        if (block.timestamp < rounds[1].endTime && rounds[1].tokensSold < rounds[1].maxTokens) {
            revert InvalidParameters(); // Round 1 not finished
        }
        
        currentRound = PresaleRound.ROUND_2;
        
        // Set Round 2 times
        rounds[2].startTime = block.timestamp;
        rounds[2].endTime = block.timestamp + rounds[2].duration;
        
        emit RoundTransitioned(PresaleRound.ROUND_1, PresaleRound.ROUND_2, block.timestamp);
    }
    
    /**
     * @dev Finalize presale after all rounds complete
     */
    function finalizePresale() external onlyOwner {
        if (presaleFinalized) revert PresaleAlreadyFinalized();
        if (presaleCancelled) revert PresaleCancelledError();
        
        // Check if presale is truly ended
        bool round2Ended = currentRound == PresaleRound.ROUND_2 && 
            (block.timestamp >= rounds[2].endTime || rounds[2].tokensSold >= rounds[2].maxTokens);
        
        bool allSoldOut = totalTokensSold >= TOTAL_PRESALE_TOKENS;
        
        if (!round2Ended && !allSoldOut) revert PresaleNotEnded();
        
        presaleFinalized = true;
        currentRound = PresaleRound.ENDED;
        
        // Return unsold tokens to owner
        uint256 unsoldTokens = TOTAL_PRESALE_TOKENS - totalTokensSold;
        if (unsoldTokens > 0) {
            escrowToken.safeTransfer(owner(), unsoldTokens);
        }
        
        emit PresaleFinalized(block.timestamp, totalTokensSold, totalUSDRaised);
    }
    
    /**
     * @dev Emergency cancel presale
     */
    function cancelPresale() external onlyOwner {
        if (presaleFinalized) revert PresaleAlreadyFinalized();
        
        presaleCancelled = true;
        currentRound = PresaleRound.ENDED;
        _pause();
        
        emit PresaleCancelled(block.timestamp);
    }
    
    /**
     * @dev Enable claims after presale
     */
    function enableClaims() external onlyOwner {
        if (!presaleFinalized) revert PresaleNotFinalized();
        claimsEnabled = true;
        tgeTime = block.timestamp;
        
        emit ClaimsEnabled(block.timestamp);
        emit TGEScheduled(block.timestamp);
    }
    
    // ============ PURCHASE FUNCTIONS ============
    
    /**
     * @dev Purchase with native currency (ETH)
     */
    function buyWithNative(address beneficiary) 
        external 
        payable 
        nonReentrant 
        whenNotPaused 
        presaleActive 
        onlyWhitelisted 
        validAddress(beneficiary)
    {
        if (msg.value <= gasBuffer) revert InsufficientPayment();
        
        TokenPrice memory price = tokenPrices[NATIVE_TOKEN];
        if (!price.isActive) revert TokenNotAccepted();
        
        uint256 paymentAmount = msg.value - gasBuffer;
        uint256 usdValue = _calculateUSDValue(NATIVE_TOKEN, paymentAmount);
        uint256 tokenAmount = _calculateTokenAmount(usdValue);
        
        _processPurchase(beneficiary, NATIVE_TOKEN, paymentAmount, tokenAmount, usdValue);
        
        // Transfer to treasury
        collectedFunds[NATIVE_TOKEN] += paymentAmount;
        (bool success, ) = treasury.call{value: paymentAmount}("");
        if (!success) revert TransferFailed();
    }
    
    /**
     * @dev Purchase with native currency and referral
     */
    function buyWithNativeReferral(address beneficiary, address _referrer) 
        external 
        payable 
        nonReentrant 
        whenNotPaused 
        presaleActive 
        onlyWhitelisted 
        validAddress(beneficiary)
    {
        if (msg.value <= gasBuffer) revert InsufficientPayment();
        
        TokenPrice memory price = tokenPrices[NATIVE_TOKEN];
        if (!price.isActive) revert TokenNotAccepted();
        
        uint256 paymentAmount = msg.value - gasBuffer;
        uint256 usdValue = _calculateUSDValue(NATIVE_TOKEN, paymentAmount);
        uint256 tokenAmount = _calculateTokenAmount(usdValue);
        
        // Process referral
        if (referralEnabled && _referrer != address(0) && _referrer != beneficiary) {
            _processReferral(beneficiary, _referrer, tokenAmount);
        }
        
        _processPurchase(beneficiary, NATIVE_TOKEN, paymentAmount, tokenAmount, usdValue);
        
        // Transfer to treasury
        collectedFunds[NATIVE_TOKEN] += paymentAmount;
        (bool success, ) = treasury.call{value: paymentAmount}("");
        if (!success) revert TransferFailed();
    }
    
    /**
     * @dev Purchase with ERC20 token
     */
    function buyWithToken(
        address token,
        uint256 amount,
        address beneficiary
    ) 
        external 
        nonReentrant 
        whenNotPaused 
        presaleActive 
        onlyWhitelisted 
        validAddress(beneficiary)
    {
        if (amount == 0) revert InvalidAmount();
        if (token == NATIVE_TOKEN) revert InvalidParameters();
        
        TokenPrice memory price = tokenPrices[token];
        if (!price.isActive) revert TokenNotAccepted();
        
        uint256 usdValue = _calculateUSDValue(token, amount);
        uint256 tokenAmount = _calculateTokenAmount(usdValue);
        
        // Transfer payment token
        IERC20(token).safeTransferFrom(msg.sender, treasury, amount);
        collectedFunds[token] += amount;
        
        _processPurchase(beneficiary, token, amount, tokenAmount, usdValue);
    }
    
    /**
     * @dev Purchase with ERC20 token and referral
     */
    function buyWithTokenReferral(
        address token,
        uint256 amount,
        address beneficiary,
        address _referrer
    ) 
        external 
        nonReentrant 
        whenNotPaused 
        presaleActive 
        onlyWhitelisted 
        validAddress(beneficiary)
    {
        if (amount == 0) revert InvalidAmount();
        if (token == NATIVE_TOKEN) revert InvalidParameters();
        
        TokenPrice memory price = tokenPrices[token];
        if (!price.isActive) revert TokenNotAccepted();
        
        uint256 usdValue = _calculateUSDValue(token, amount);
        uint256 tokenAmount = _calculateTokenAmount(usdValue);
        
        // Process referral
        if (referralEnabled && _referrer != address(0) && _referrer != beneficiary) {
            _processReferral(beneficiary, _referrer, tokenAmount);
        }
        
        // Transfer payment token
        IERC20(token).safeTransferFrom(msg.sender, treasury, amount);
        collectedFunds[token] += amount;
        
        _processPurchase(beneficiary, token, amount, tokenAmount, usdValue);
    }
    
    // ============ INTERNAL FUNCTIONS ============
    
    function _calculateUSDValue(address token, uint256 amount) private view returns (uint256) {
        TokenPrice memory price = tokenPrices[token];
        return (amount * price.priceUSD) / (10 ** price.decimals);
    }
    
    function _calculateTokenAmount(uint256 usdValue) private view returns (uint256) {
        uint256 roundId = currentRound == PresaleRound.ROUND_1 ? 1 : 2;
        RoundConfig memory round = rounds[roundId];
        
        // tokenAmount = usdValue / tokenPrice (both in 8 decimals)
        // Result in 18 decimals for token
        return (usdValue * 1e18) / round.tokenPrice;
    }
    
    function _processReferral(address user, address _referrer, uint256 tokenAmount) private {
        if (_referrer == user || referrer[_referrer] == user) revert InvalidReferrer();
        
        if (referrer[user] == address(0)) {
            referrer[user] = _referrer;
        }
        
        uint256 bonus = (tokenAmount * referralBonusPercentage) / BASIS_POINTS;
        referralBonus[_referrer] += bonus;
        
        emit ReferralRecorded(user, _referrer, bonus);
    }
    
    function _processPurchase(
        address beneficiary,
        address paymentToken,
        uint256 paymentAmount,
        uint256 tokenAmount,
        uint256 usdValue
    ) private {
        // Validate purchase amount
        if (usdValue < minPurchaseAmount) revert BelowMinimumPurchase();
        
        UserInfo storage user = userInfo[beneficiary];
        uint256 newTotalUSD = user.totalUSDSpent + usdValue;
        
        // Check user limits
        if (whitelistAllocation[beneficiary] > 0) {
            if (newTotalUSD > whitelistAllocation[beneficiary]) revert ExceedsAllocation();
        } else {
            if (newTotalUSD > maxPurchasePerUser) revert ExceedsMaximumPurchase();
        }
        
        // Check round capacity
        uint256 roundId = currentRound == PresaleRound.ROUND_1 ? 1 : 2;
        RoundConfig storage round = rounds[roundId];
        
        uint256 newRoundTotal = round.tokensSold + tokenAmount;
        if (newRoundTotal > round.maxTokens) revert ExceedsRoundCap();
        
        uint256 newTotalSold = totalTokensSold + tokenAmount;
        if (newTotalSold > TOTAL_PRESALE_TOKENS) revert ExceedsRoundCap();
        
        // Track participants
        if (!hasParticipated[beneficiary]) {
            if (participants.length >= MAX_PARTICIPANTS) revert MaxParticipantsReached();
            participants.push(beneficiary);
            hasParticipated[beneficiary] = true;
        }
        
        // Update state
        user.totalTokensPurchased += tokenAmount;
        user.totalUSDSpent = newTotalUSD;
        
        if (currentRound == PresaleRound.ROUND_1) {
            user.round1Purchased += tokenAmount;
        } else {
            user.round2Purchased += tokenAmount;
        }
        
        userTokenPurchases[beneficiary][paymentToken] += paymentAmount;
        round.tokensSold = newRoundTotal;
        totalTokensSold = newTotalSold;
        totalUSDRaised += usdValue;
        
        emit TokenPurchase(
            msg.sender,
            beneficiary,
            paymentToken,
            paymentAmount,
            tokenAmount,
            usdValue,
            currentRound
        );
        
        // Auto-transition to Round 2 if Round 1 is sold out
        if (currentRound == PresaleRound.ROUND_1 && round.tokensSold >= round.maxTokens) {
            currentRound = PresaleRound.ROUND_2;
            rounds[2].startTime = block.timestamp;
            rounds[2].endTime = block.timestamp + rounds[2].duration;
            emit RoundTransitioned(PresaleRound.ROUND_1, PresaleRound.ROUND_2, block.timestamp);
        }
    }
    
    // ============ CLAIM FUNCTIONS ============
    
    /**
     * @dev Claim purchased tokens after presale ends
     */
    function claimTokens() external nonReentrant {
        if (!claimsEnabled) revert ClaimsNotEnabled();
        
        UserInfo storage user = userInfo[msg.sender];
        if (user.totalTokensPurchased == 0) revert NothingToClaim();
        if (user.hasClaimed) revert AlreadyClaimed();
        
        uint256 claimAmount = user.totalTokensPurchased + referralBonus[msg.sender];
        user.hasClaimed = true;
        
        escrowToken.safeTransfer(msg.sender, claimAmount);
        
        emit TokensClaimed(msg.sender, claimAmount, block.timestamp);
    }
    
    /**
     * @dev Emergency refund (only if presale cancelled)
     */
    function emergencyRefund() external nonReentrant {
        if (!presaleCancelled) revert InvalidParameters();
        
        UserInfo storage user = userInfo[msg.sender];
        if (user.totalTokensPurchased == 0) revert NothingToClaim();
        if (user.hasClaimed) revert AlreadyClaimed();
        
        uint256 refundAmount = user.totalTokensPurchased;
        user.hasClaimed = true;
        
        escrowToken.safeTransfer(msg.sender, refundAmount);
        
        emit EmergencyRefund(msg.sender, refundAmount);
    }
    
    // ============ ADMIN FUNCTIONS ============
    
    function setTokenPrice(address token, uint256 priceUSD, uint8 decimals, bool isActive) 
        external 
        onlyOwner 
    {
        if (priceUSD == 0 && isActive) revert InvalidParameters();
        if (decimals > 18) revert InvalidParameters();
        
        bool wasActive = tokenPrices[token].isActive;
        
        tokenPrices[token] = TokenPrice({
            priceUSD: priceUSD,
            isActive: isActive,
            decimals: decimals
        });
        
        if (isActive && !wasActive && !isTokenAccepted[token]) {
            acceptedTokensList.push(token);
            isTokenAccepted[token] = true;
        }
        
        emit TokenPriceUpdated(token, priceUSD, isActive);
    }
    
    function setLimits(uint256 _maxPurchase, uint256 _minPurchase) external onlyOwner {
        if (_minPurchase >= _maxPurchase) revert InvalidParameters();
        maxPurchasePerUser = _maxPurchase;
        minPurchaseAmount = _minPurchase;
    }
    
    function setTreasury(address _treasury) external onlyOwner validAddress(_treasury) {
        address oldTreasury = treasury;
        treasury = _treasury;
        emit TreasuryUpdated(oldTreasury, _treasury);
    }
    
    function setGasBuffer(uint256 _gasBuffer) external onlyOwner {
        gasBuffer = _gasBuffer;
    }
    
    function setWhitelistEnabled(bool _enabled) external onlyOwner {
        whitelistEnabled = _enabled;
    }
    
    function updateWhitelist(address[] calldata users, bool status) external onlyOwner {
        for (uint256 i = 0; i < users.length; i++) {
            if (users[i] != address(0)) {
                whitelist[users[i]] = status;
                emit WhitelistUpdated(users[i], status, 0);
            }
        }
    }
    
    function setWhitelistAllocations(address[] calldata users, uint256[] calldata allocations) 
        external 
        onlyOwner 
    {
        if (users.length != allocations.length) revert InvalidParameters();
        
        for (uint256 i = 0; i < users.length; i++) {
            if (users[i] != address(0)) {
                whitelist[users[i]] = true;
                whitelistAllocation[users[i]] = allocations[i];
                emit WhitelistUpdated(users[i], true, allocations[i]);
            }
        }
    }
    
    function setReferralEnabled(bool _enabled) external onlyOwner {
        referralEnabled = _enabled;
    }
    
    function setReferralBonus(uint256 _percentage) external onlyOwner {
        if (_percentage > 2000) revert InvalidParameters();
        referralBonusPercentage = _percentage;
    }
    
    function withdrawFunds(address token) external onlyOwner {
        if (!presaleFinalized && !presaleCancelled) revert PresaleNotFinalized();
        
        uint256 amount;
        if (token == NATIVE_TOKEN) {
            amount = address(this).balance;
            if (amount > 0) {
                (bool success, ) = treasury.call{value: amount}("");
                if (!success) revert TransferFailed();
            }
        } else {
            amount = IERC20(token).balanceOf(address(this));
            if (amount > 0) {
                IERC20(token).safeTransfer(treasury, amount);
            }
        }
    }
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    function emergencyWithdrawToken(address token) external onlyOwner validAddress(token) {
        if (token == address(escrowToken)) {
            if (!presaleFinalized && !presaleCancelled) revert PresaleNotFinalized();
        }
        
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance == 0) revert InvalidAmount();
        
        IERC20(token).safeTransfer(owner(), balance);
    }
    
    // ============ VIEW FUNCTIONS ============
    
    function getUserInfo(address user) external view returns (
        uint256 totalTokensPurchased,
        uint256 totalUSDSpent,
        uint256 round1Purchased,
        uint256 round2Purchased,
        uint256 referralBonusAmount,
        bool hasClaimed,
        bool userIsWhitelisted
    ) {
        UserInfo memory info = userInfo[user];
        return (
            info.totalTokensPurchased,
            info.totalUSDSpent,
            info.round1Purchased,
            info.round2Purchased,
            referralBonus[user],
            info.hasClaimed,
            whitelist[user]
        );
    }
    
    function getPresaleInfo() external view returns (
        PresaleRound round,
        uint256 totalSold,
        uint256 totalRemaining,
        uint256 usdRaised,
        bool isActive,
        bool isFinalized,
        bool isCancelled
    ) {
        return (
            currentRound,
            totalTokensSold,
            TOTAL_PRESALE_TOKENS - totalTokensSold,
            totalUSDRaised,
            currentRound != PresaleRound.NOT_STARTED && 
                currentRound != PresaleRound.ENDED && 
                !presaleFinalized && 
                !presaleCancelled,
            presaleFinalized,
            presaleCancelled
        );
    }
    
    function getRoundInfo(uint256 roundId) external view returns (
        uint256 tokenPrice,
        uint256 maxTokens,
        uint256 tokensSold,
        uint256 tokensRemaining,
        uint256 duration,
        uint256 startTime,
        uint256 endTime,
        bool isActive
    ) {
        if (roundId < 1 || roundId > 2) revert InvalidParameters();
        
        RoundConfig memory round = rounds[roundId];
        bool active = (roundId == 1 && currentRound == PresaleRound.ROUND_1) ||
                      (roundId == 2 && currentRound == PresaleRound.ROUND_2);
        
        return (
            round.tokenPrice,
            round.maxTokens,
            round.tokensSold,
            round.maxTokens - round.tokensSold,
            round.duration,
            round.startTime,
            round.endTime,
            active
        );
    }
    
    function getCurrentRound() external view returns (PresaleRound) {
        return currentRound;
    }
    
    function getAcceptedTokens() external view returns (address[] memory) {
        return acceptedTokensList;
    }
    
    function getTokenPrice(address token) external view returns (
        uint256 priceUSD,
        bool isActive,
        uint8 decimals
    ) {
        TokenPrice memory price = tokenPrices[token];
        return (price.priceUSD, price.isActive, price.decimals);
    }
    
    function getUserPurchasesByToken(address user, address token) external view returns (uint256) {
        return userTokenPurchases[user][token];
    }
    
    function getParticipantsCount() external view returns (uint256) {
        return participants.length;
    }
    
    function getParticipant(uint256 index) external view returns (address) {
        if (index >= participants.length) revert InvalidParameters();
        return participants[index];
    }
    
    function getParticipants(uint256 startIndex, uint256 count) 
        external 
        view 
        returns (address[] memory) 
    {
        if (startIndex >= participants.length) revert InvalidParameters();
        
        uint256 endIndex = startIndex + count;
        if (endIndex > participants.length) {
            endIndex = participants.length;
        }
        
        uint256 resultCount = endIndex - startIndex;
        address[] memory result = new address[](resultCount);
        
        for (uint256 i = 0; i < resultCount; i++) {
            result[i] = participants[startIndex + i];
        }
        
        return result;
    }
    
    function calculateTokensForUSD(uint256 usdValue) external view returns (uint256) {
        return _calculateTokenAmount(usdValue);
    }
    
    function calculateUSDValue(address token, uint256 amount) external view returns (uint256) {
        return _calculateUSDValue(token, amount);
    }
    
    function calculateTokensForPayment(address token, uint256 amount) 
        external 
        view 
        returns (uint256 tokenAmount, uint256 usdValue) 
    {
        usdValue = _calculateUSDValue(token, amount);
        tokenAmount = _calculateTokenAmount(usdValue);
    }
    
    function getCollectedFunds(address token) external view returns (uint256) {
        return collectedFunds[token];
    }
    
    function canPurchase(address user, uint256 usdAmount) external view returns (bool) {
        UserInfo memory info = userInfo[user];
        uint256 newTotal = info.totalUSDSpent + usdAmount;
        
        if (whitelistAllocation[user] > 0) {
            return newTotal <= whitelistAllocation[user];
        }
        
        return newTotal <= maxPurchasePerUser;
    }
    
    function getRemainingAllocation(address user) external view returns (uint256) {
        UserInfo memory info = userInfo[user];
        uint256 limit = whitelistAllocation[user] > 0 ? 
            whitelistAllocation[user] : maxPurchasePerUser;
        
        if (info.totalUSDSpent >= limit) {
            return 0;
        }
        
        return limit - info.totalUSDSpent;
    }
    
    function getReferralInfo(address user) external view returns (
        address referrerAddress,
        uint256 bonusTokens,
        uint256 bonusPercentage
    ) {
        return (
            referrer[user],
            referralBonus[user],
            referralBonusPercentage
        );
    }
    
    function isSoldOut() external view returns (bool) {
        return totalTokensSold >= TOTAL_PRESALE_TOKENS;
    }
    
    function getPresaleProgress() external view returns (uint256) {
        if (TOTAL_PRESALE_TOKENS == 0) return 0;
        return (totalTokensSold * BASIS_POINTS) / TOTAL_PRESALE_TOKENS;
    }
    
    function getTimeRemaining() external view returns (uint256) {
        if (currentRound == PresaleRound.NOT_STARTED || currentRound == PresaleRound.ENDED) {
            return 0;
        }
        
        uint256 roundId = currentRound == PresaleRound.ROUND_1 ? 1 : 2;
        RoundConfig memory round = rounds[roundId];
        
        if (round.endTime <= block.timestamp) return 0;
        return round.endTime - block.timestamp;
    }
    
    function getRoundTimeRemaining(uint256 roundId) external view returns (uint256) {
        if (roundId < 1 || roundId > 2) revert InvalidParameters();
        
        RoundConfig memory round = rounds[roundId];
        if (round.endTime == 0 || round.endTime <= block.timestamp) return 0;
        return round.endTime - block.timestamp;
    }
    
    function isWhitelisted(address user) external view returns (bool) {
        return whitelist[user];
    }
    
    function getWhitelistAllocation(address user) external view returns (uint256) {
        return whitelistAllocation[user];
    }
    
    function getRoundProgress(uint256 roundId) external view returns (uint256) {
        if (roundId < 1 || roundId > 2) revert InvalidParameters();
        
        RoundConfig memory round = rounds[roundId];
        if (round.maxTokens == 0) return 0;
        
        return (round.tokensSold * BASIS_POINTS) / round.maxTokens;
    }
    
    function getTotalClaimable(address user) external view returns (uint256) {
        UserInfo memory info = userInfo[user];
        if (info.hasClaimed) return 0;
        return info.totalTokensPurchased + referralBonus[user];
    }
    
    function getPresaleStats() external view returns (
        uint256 totalParticipants,
        uint256 totalTokensSold_,
        uint256 totalUSDRaised_,
        uint256 round1Sold,
        uint256 round2Sold,
        uint256 percentComplete
    ) {
        return (
            participants.length,
            totalTokensSold,
            totalUSDRaised,
            rounds[1].tokensSold,
            rounds[2].tokensSold,
            (totalTokensSold * BASIS_POINTS) / TOTAL_PRESALE_TOKENS
        );
    }
    
    // ============ RECEIVE & FALLBACK ============
    
    receive() external payable {
        revert("Use buyWithNative function");
    }
    
    fallback() external payable {
        revert("Invalid function call");
    }
}