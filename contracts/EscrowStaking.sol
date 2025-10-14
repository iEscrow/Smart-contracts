// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title EscrowStaking
 * @dev Time-locked staking with C-Share deflationary model and bonus system
 * @notice Implements whitepaper specifications for quantity/time bonuses and penalties
 * @custom:security-contact security@iescrow.com
 */
contract EscrowStaking is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    
    // ============ STRUCTS ============
    
    struct StakeInfo {
        uint256 stakedAmount;        // Initial tokens staked
        uint256 shares;              // C-Shares received
        uint256 startTime;           // Stake start timestamp
        uint256 endTime;             // Stake end timestamp (lock period)
        uint256 stakeDays;           // Staking duration in days
        uint256 lastClaimTime;       // Last reward claim time
        uint256 rewardsClaimed;      // Total rewards claimed
        bool active;                 // Whether stake is active
    }
    
    // ============ STATE VARIABLES ============
    
    IERC20 public immutable escrowToken;
    
    // Staking parameters
    uint256 public constant DAILY_DISTRIBUTION_RATE = 10; // 0.01% = 10/10000
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MAX_QUANTITY_BONUS_TOKENS = 150_000_000 * 1e18; // 150M tokens
    uint256 public constant QUANTITY_BONUS_DIVISOR = 1_500_000_000 * 1e18; // 1.5B tokens
    uint256 public constant TIME_BONUS_DIVISOR = 1820; // Days divisor
    uint256 public constant MAX_TIME_BONUS_DAYS = 3641; // ~10 years
    
    // C-Share pricing
    uint256 public cSharePrice = 10_000 * 1e18; // Starts at 10,000 tokens per C-Share
    uint256 public totalShares; // Total C-Shares in existence
    uint256 public totalStakedTokens; // Total tokens currently staked
    
    // Penalty parameters
    uint256 public constant PENALTY_BURN_PERCENT = 25; // 25% burned
    uint256 public constant PENALTY_POOL_PERCENT = 50; // 50% to pool
    uint256 public constant PENALTY_TREASURY_PERCENT = 25; // 25% to treasury
    uint256 public constant LATE_PENALTY_RATE = 125; // 0.125% per day = 125/100000
    uint256 public constant LATE_PENALTY_GRACE_DAYS = 14; // 14 days grace period
    
    // Tracking
    mapping(address => StakeInfo[]) public userStakes;
    mapping(address => uint256) public userTotalShares;
    uint256 public totalUsers;
    uint256 public totalRewardsDistributed;
    address public treasuryAddress;
    
    // Limits
    uint256 public minStakeAmount = 1000 * 1e18; // 1,000 tokens minimum
    uint256 public maxStakeAmount = 1_000_000_000 * 1e18; // 1B tokens maximum
    uint256 public minStakeDays = 1;
    uint256 public maxStakeDays = 3641;
    
    // ============ EVENTS ============
    
    event Staked(
        address indexed user,
        uint256 indexed stakeId,
        uint256 amount,
        uint256 shares,
        uint256 stakeDays,
        uint256 endTime
    );
    
    event Unstaked(
        address indexed user,
        uint256 indexed stakeId,
        uint256 amount,
        uint256 reward,
        uint256 penalty
    );
    
    event RewardsClaimed(
        address indexed user,
        uint256 indexed stakeId,
        uint256 amount
    );
    
    event CSharePriceUpdated(uint256 oldPrice, uint256 newPrice);
    event PenaltyDistributed(uint256 burned, uint256 toPool, uint256 toTreasury);
    
    // ============ ERRORS ============
    
    error InvalidAmount();
    error InvalidDuration();
    error StakeNotFound();
    error StakeLocked();
    error NoRewardsToClaim();
    error InsufficientBalance();
    error InvalidAddress();
    
    // ============ CONSTRUCTOR ============
    
    constructor(address _escrowToken, address _treasury) Ownable(msg.sender) {
        if (_escrowToken == address(0) || _treasury == address(0)) revert InvalidAddress();
        escrowToken = IERC20(_escrowToken);
        treasuryAddress = _treasury;
    }
    
    // ============ STAKING FUNCTIONS ============
    
    /**
     * @dev Stake tokens for a specified duration
     * @param amount Amount of tokens to stake
     * @param days_ Duration in days (1-3641)
     */
    function stake(uint256 amount, uint256 days_) external nonReentrant whenNotPaused {
        if (amount < minStakeAmount || amount > maxStakeAmount) revert InvalidAmount();
        if (days_ < minStakeDays || days_ > maxStakeDays) revert InvalidDuration();
        
        // Calculate bonuses
        uint256 quantityBonus = _calculateQuantityBonus(amount);
        uint256 timeBonus = _calculateTimeBonus(amount, days_);
        uint256 effectiveTokens = amount + quantityBonus + timeBonus;
        
        // Calculate C-Shares
        uint256 shares = (effectiveTokens * 1e18) / cSharePrice;
        
        // Transfer tokens from user to contract
        escrowToken.safeTransferFrom(msg.sender, address(this), amount);
        
        // Create stake
        StakeInfo memory newStake = StakeInfo({
            stakedAmount: amount,
            shares: shares,
            startTime: block.timestamp,
            endTime: block.timestamp + (days_ * 1 days),
            stakeDays: days_,
            lastClaimTime: block.timestamp,
            rewardsClaimed: 0,
            active: true
        });
        
        userStakes[msg.sender].push(newStake);
        
        if (userTotalShares[msg.sender] == 0) {
            totalUsers++;
        }
        
        userTotalShares[msg.sender] += shares;
        totalShares += shares;
        totalStakedTokens += amount;
        
        emit Staked(
            msg.sender,
            userStakes[msg.sender].length - 1,
            amount,
            shares,
            days_,
            newStake.endTime
        );
    }
    
    /**
     * @dev Unstake tokens after lock period
     * @param stakeId Index of the stake to unstake
     */
    function unstake(uint256 stakeId) external nonReentrant {
        if (stakeId >= userStakes[msg.sender].length) revert StakeNotFound();
        
        StakeInfo storage stakeInfo = userStakes[msg.sender][stakeId];
        if (!stakeInfo.active) revert StakeNotFound();
        
        uint256 reward = _calculateRewards(msg.sender, stakeId);
        uint256 penalty = 0;
        uint256 totalPayout = stakeInfo.stakedAmount + reward;
        
        // Check if unstaking early
        if (block.timestamp < stakeInfo.endTime) {
            penalty = _calculateEarlyUnstakePenalty(stakeInfo, reward);
            // Cap penalty at reward amount (penalties should only apply to rewards, not principal)
            if (penalty > reward) {
                penalty = reward;
            }
            // Further cap at total payout to be safe
            if (penalty > totalPayout) {
                penalty = totalPayout;
            }
            totalPayout -= penalty;
            if (penalty > 0) {
                _distributePenalty(penalty);
            }
        }
        
        // Check for late unstake penalty
        if (block.timestamp > stakeInfo.endTime + (LATE_PENALTY_GRACE_DAYS * 1 days)) {
            uint256 latePenalty = _calculateLateUnstakePenalty(stakeInfo, totalPayout);
            // Cap late penalty at remaining payout
            if (latePenalty > totalPayout) {
                latePenalty = totalPayout;
            }
            totalPayout -= latePenalty;
            penalty += latePenalty;
            if (latePenalty > 0) {
                _distributePenalty(latePenalty);
            }
        }
        
        // Update state
        stakeInfo.active = false;
        userTotalShares[msg.sender] -= stakeInfo.shares;
        totalShares -= stakeInfo.shares;
        totalStakedTokens -= stakeInfo.stakedAmount;
        totalRewardsDistributed += reward;
        
        // Update C-Share price
        _updateCSharePrice(stakeInfo.stakedAmount + reward, stakeInfo.shares, stakeInfo.stakeDays);
        
        // Transfer tokens
        if (totalPayout > 0) {
            escrowToken.safeTransfer(msg.sender, totalPayout);
        }
        
        if (userTotalShares[msg.sender] == 0) {
            totalUsers--;
        }
        
        emit Unstaked(msg.sender, stakeId, stakeInfo.stakedAmount, reward, penalty);
    }
    
    /**
     * @dev Claim rewards without unstaking
     * @param stakeId Index of the stake
     */
    function claimRewards(uint256 stakeId) external nonReentrant {
        if (stakeId >= userStakes[msg.sender].length) revert StakeNotFound();
        
        StakeInfo storage stakeInfo = userStakes[msg.sender][stakeId];
        if (!stakeInfo.active) revert StakeNotFound();
        
        uint256 reward = _calculateRewards(msg.sender, stakeId);
        if (reward == 0) revert NoRewardsToClaim();
        
        stakeInfo.lastClaimTime = block.timestamp;
        stakeInfo.rewardsClaimed += reward;
        totalRewardsDistributed += reward;
        
        escrowToken.safeTransfer(msg.sender, reward);
        
        emit RewardsClaimed(msg.sender, stakeId, reward);
    }
    
    // ============ INTERNAL FUNCTIONS ============
    
    function _calculateQuantityBonus(uint256 amount) internal pure returns (uint256) {
        uint256 eligibleAmount = amount > MAX_QUANTITY_BONUS_TOKENS 
            ? MAX_QUANTITY_BONUS_TOKENS 
            : amount;
        return (eligibleAmount * 1e18) / QUANTITY_BONUS_DIVISOR;
    }
    
    function _calculateTimeBonus(uint256 amount, uint256 days_) internal pure returns (uint256) {
        if (days_ <= 1) return 0;
        uint256 eligibleDays = days_ > MAX_TIME_BONUS_DAYS ? MAX_TIME_BONUS_DAYS : days_;
        return (amount * (eligibleDays - 1)) / TIME_BONUS_DIVISOR;
    }
    
    function _calculateRewards(address user, uint256 stakeId) internal view returns (uint256) {
        StakeInfo memory stakeInfo = userStakes[user][stakeId];
        if (!stakeInfo.active) return 0;
        if (totalShares == 0) return 0; // Prevent division by zero
        
        uint256 timeElapsed = block.timestamp - stakeInfo.lastClaimTime;
        if (timeElapsed == 0) return 0;
        
        // Calculate user's share of daily distribution
        uint256 userShare = (stakeInfo.shares * BASIS_POINTS) / totalShares;
        uint256 totalSupply = escrowToken.totalSupply();
        uint256 dailyPool = (totalSupply * DAILY_DISTRIBUTION_RATE) / BASIS_POINTS;
        
        uint256 daysElapsed = timeElapsed / 1 days;
        uint256 reward = (dailyPool * userShare * daysElapsed) / BASIS_POINTS;
        
        return reward;
    }
    
    function _calculateEarlyUnstakePenalty(
        StakeInfo memory stakeInfo,
        uint256 reward
    ) internal view returns (uint256) {
        uint256 timeElapsed = block.timestamp - stakeInfo.startTime;
        uint256 daysElapsed = timeElapsed / 1 days;
        
        if (stakeInfo.stakeDays < 180) {
            // Stakes < 180 days
            if (daysElapsed == 0) return 0;
            if (daysElapsed < 90) {
                return (reward * 90) / daysElapsed;
            } else if (daysElapsed == 90) {
                return reward; // Forfeit all rewards
            } else {
                // After 90 days, penalty decreases
                uint256 rewardPerDay = reward / daysElapsed;
                uint256 penaltyDays = 90;
                return rewardPerDay * penaltyDays;
            }
        } else {
            // Stakes >= 180 days
            uint256 halfDuration = stakeInfo.stakeDays / 2;
            if (daysElapsed == 0) return 0;
            if (daysElapsed < halfDuration) {
                return (reward * halfDuration) / daysElapsed;
            } else if (daysElapsed == halfDuration) {
                return reward;
            } else {
                uint256 rewardPerDay = reward / daysElapsed;
                uint256 penaltyDays = halfDuration;
                return rewardPerDay * penaltyDays;
            }
        }
    }
    
    function _calculateLateUnstakePenalty(
        StakeInfo memory stakeInfo,
        uint256 amount
    ) internal view returns (uint256) {
        uint256 daysLate = (block.timestamp - stakeInfo.endTime - (LATE_PENALTY_GRACE_DAYS * 1 days)) / 1 days;
        if (daysLate == 0) return 0;
        
        uint256 dailyPenalty = (amount * LATE_PENALTY_RATE) / 100000;
        uint256 totalPenalty = dailyPenalty * daysLate;
        
        // Cap at total amount
        return totalPenalty > amount ? amount : totalPenalty;
    }
    
    function _distributePenalty(uint256 penalty) internal {
        uint256 burnAmount = (penalty * PENALTY_BURN_PERCENT) / 100;
        uint256 poolAmount = (penalty * PENALTY_POOL_PERCENT) / 100;
        uint256 treasuryAmount = penalty - burnAmount - poolAmount;
        
        // Burn tokens by transferring to dead address (0x000...dead)
        if (burnAmount > 0) {
            escrowToken.safeTransfer(address(0x000000000000000000000000000000000000dEaD), burnAmount);
        }
        
        // To treasury
        if (treasuryAmount > 0) {
            escrowToken.safeTransfer(treasuryAddress, treasuryAmount);
        }
        
        // Pool amount stays in contract for future rewards
        
        emit PenaltyDistributed(burnAmount, poolAmount, treasuryAmount);
    }
    
    function _updateCSharePrice(
        uint256 totalPaid,
        uint256 shares,
        uint256 stakeDays
    ) internal {
        uint256 minTokens = totalPaid > MAX_QUANTITY_BONUS_TOKENS 
            ? MAX_QUANTITY_BONUS_TOKENS 
            : totalPaid;
        
        uint256 minDays = stakeDays > MAX_TIME_BONUS_DAYS 
            ? MAX_TIME_BONUS_DAYS - 1 
            : stakeDays - 1;
        
        uint256 numerator = (QUANTITY_BONUS_DIVISOR + minTokens) * totalPaid;
        uint256 denominator = ((TIME_BONUS_DIVISOR * shares) / (TIME_BONUS_DIVISOR + minDays)) * 
                              (QUANTITY_BONUS_DIVISOR / 1e18);
        
        uint256 newPrice = numerator / denominator;
        
        if (newPrice > cSharePrice) {
            uint256 oldPrice = cSharePrice;
            cSharePrice = newPrice;
            emit CSharePriceUpdated(oldPrice, newPrice);
        }
    }
    
    // ============ ADMIN FUNCTIONS ============
    
    function setLimits(
        uint256 _minStake,
        uint256 _maxStake,
        uint256 _minDays,
        uint256 _maxDays
    ) external onlyOwner {
        minStakeAmount = _minStake;
        maxStakeAmount = _maxStake;
        minStakeDays = _minDays;
        maxStakeDays = _maxDays;
    }
    
    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert InvalidAddress();
        treasuryAddress = _treasury;
    }
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }
    
    // ============ VIEW FUNCTIONS ============
    
    function getUserStakesCount(address user) external view returns (uint256) {
        return userStakes[user].length;
    }
    
    function getUserStake(address user, uint256 stakeId) 
        external 
        view 
        returns (StakeInfo memory) 
    {
        return userStakes[user][stakeId];
    }
    
    function getPendingRewards(address user, uint256 stakeId) 
        external 
        view 
        returns (uint256) 
    {
        return _calculateRewards(user, stakeId);
    }
    
    function getStakingStats() external view returns (
        uint256 totalShares_,
        uint256 totalStaked_,
        uint256 totalUsers_,
        uint256 cSharePrice_,
        uint256 totalRewards_
    ) {
        return (
            totalShares,
            totalStakedTokens,
            totalUsers,
            cSharePrice,
            totalRewardsDistributed
        );
    }
}
