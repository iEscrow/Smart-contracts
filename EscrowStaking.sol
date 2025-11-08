// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title EscrowStaking
 * @dev Implements the ESCROW token staking system with locked staking, bonuses, and deflationary C-Shares
 */
contract EscrowStaking is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // Constants
    uint256 constant QUANTITY_BONUS_CAP = 150_000_000 * 10**18;
    uint256 constant QUANTITY_BONUS_DIVISOR = 1_500_000_000;
    uint256 constant TIME_BONUS_DIVISOR = 1820;
    uint256 constant DAILY_REWARD_PERCENTAGE = 1; // 0.01% = 1 basis point
    uint256 constant DAILY_REWARD_DIVISOR = 10000;
    uint256 constant LATE_UNSTAKE_PENALTY_PERCENTAGE = 125; // 0.125%
    uint256 constant LATE_UNSTAKE_PENALTY_DIVISOR = 100000;
    uint256 constant MAX_LATE_UNSTAKE_DAYS = 800;
    uint256 constant GRACE_PERIOD_DAYS = 14;
    uint256 constant PENALTY_BURN_PERCENTAGE = 25;
    uint256 constant PENALTY_POOL_PERCENTAGE = 50;
    uint256 constant PENALTY_PROJECT_PERCENTAGE = 25;

    // Share denominations
    uint256 constant C_SHARE = 1_000_000_000_000_000; // Quadrillion
    uint256 constant T_SHARE = 1_000_000_000_000;    // Trillion
    uint256 constant B_SHARE = 1_000_000_000;        // Billion
    uint256 constant M_SHARE = 1_000_000;            // Million

    // Initial C-Share price: 10,000 tokens per C-Share
    uint256 constant INITIAL_C_SHARE_PRICE = 10_000 * 10**18;

    IERC20 public escrowToken;
    address public projectAddress;

    // Global C-Share price (updates only upwards)
    uint256 public globalCSharePrice;

    // Staking data structures
    struct Stake {
        uint256 amount; // Initial token amount
        uint256 duration; // Duration in days
        uint256 startTime; // Block timestamp of stake start
        uint256 cShares; // Number of C-Shares acquired
        uint256 earnedYield; // Accumulated yield
        bool active; // Whether stake is active
        uint256 endStakeExecutedTime; // Timestamp when end stake was executed
    }

    mapping(address => Stake) public stakes;
    mapping(address => uint256) public cSharesHeld;

    // Total C-Shares in the system
    uint256 public totalCShares;

    // Daily reward pool tracking
    uint256 public lastRewardDistributionTime;
    uint256 public accumulatedRewardPool;

    // Events
    event StakeStarted(
        address indexed staker,
        uint256 amount,
        uint256 duration,
        uint256 quantityBonus,
        uint256 timeBonus,
        uint256 effectiveTokens,
        uint256 cSharesReceived
    );

    event DailyRewardsDistributed(
        uint256 totalReward,
        uint256 timestamp
    );

    event EmergencyEndStakeExecuted(
        address indexed staker,
        uint256 principalReturned,
        uint256 yieldPaid,
        uint256 penaltyApplied,
        uint256 stakeAge
    );

    event EndStakeExecuted(
        address indexed staker,
        uint256 principalReturned,
        uint256 yieldPaid,
        uint256 cSharePrice
    );

    event LateEndStakePenaltyApplied(
        address indexed staker,
        uint256 penaltyAmount,
        uint256 daysLate
    );

    event CSharePriceUpdated(uint256 newPrice);

    /**
     * @dev Initialize the staking contract
     * @param _escrowToken Address of the ESCROW token
     * @param _projectAddress Address that receives project share of penalties
     */
    constructor(address _escrowToken, address _projectAddress) Ownable(msg.sender) {
        require(_escrowToken != address(0), "Invalid token address");
        require(_projectAddress != address(0), "Invalid project address");
        
        escrowToken = IERC20(_escrowToken);
        projectAddress = _projectAddress;
        globalCSharePrice = INITIAL_C_SHARE_PRICE;
        lastRewardDistributionTime = block.timestamp;
    }

    /**
     * @dev Calculate quantity bonus based on stake amount
     * Formula: (initial tokens up to 150,000,000) / 1,500,000,000
     */
    function calculateQuantityBonus(uint256 amount) public pure returns (uint256) {
        uint256 bonusBase = amount > QUANTITY_BONUS_CAP ? QUANTITY_BONUS_CAP : amount;
        return (bonusBase * 10) / QUANTITY_BONUS_DIVISOR;
    }

    /**
     * @dev Calculate time bonus based on stake duration
     * Formula: (initial tokens) × (days – 1) / 1820
     * Caps at 3x when staking 3641 days or longer
     */
    function calculateTimeBonus(uint256 amount, uint256 days_) public pure returns (uint256) {
        if (days_ <= 1) return 0;
        uint256 bonus = (amount * (days_ - 1)) / TIME_BONUS_DIVISOR;
        uint256 maxBonus = amount * 3;
        return bonus > maxBonus ? maxBonus : bonus;
    }

    /**
     * @dev Start a new stake
     * @param amount Number of tokens to stake
     * @param durationDays Number of days to lock tokens
     */
    function startStake(uint256 amount, uint256 durationDays) external nonReentrant {
        require(amount > 0, "Stake amount must be greater than 0");
        require(durationDays > 0, "Duration must be greater than 0");
        require(stakes[msg.sender].active == false, "User already has active stake");

        // Transfer tokens from staker to contract
        escrowToken.safeTransferFrom(msg.sender, address(this), amount);

        // Calculate bonuses
        uint256 quantityBonus = calculateQuantityBonus(amount);
        uint256 timeBonus = calculateTimeBonus(amount, durationDays);
        uint256 effectiveTokens = amount + quantityBonus + timeBonus;

        // Convert effective tokens to C-Shares
        uint256 cSharesToReceive = (effectiveTokens * 10**18) / globalCSharePrice;

        // Burn initial tokens (in production, this would transfer to burn address)
        // For now, we'll just account for it

        // Record stake
        stakes[msg.sender] = Stake({
            amount: amount,
            duration: durationDays,
            startTime: block.timestamp,
            cShares: cSharesToReceive,
            earnedYield: 0,
            active: true,
            endStakeExecutedTime: 0
        });

        cSharesHeld[msg.sender] = cSharesToReceive;
        totalCShares += cSharesToReceive;

        emit StakeStarted(
            msg.sender,
            amount,
            durationDays,
            quantityBonus,
            timeBonus,
            effectiveTokens,
            cSharesToReceive
        );
    }

    /**
     * @dev Distribute daily rewards to all stakers
     * 0.01% of total supply distributed daily based on C-Share percentage
     */
    function distributeDailyRewards(uint256 totalSupply) external onlyOwner nonReentrant {
        require(totalSupply > 0, "Total supply must be greater than 0");

        // Calculate 0.01% of total supply
        uint256 dailyReward = (totalSupply * DAILY_REWARD_PERCENTAGE) / DAILY_REWARD_DIVISOR;
        
        accumulatedRewardPool += dailyReward;
        lastRewardDistributionTime = block.timestamp;

        emit DailyRewardsDistributed(dailyReward, block.timestamp);
    }

    /**
     * @dev Calculate earned yield for a staker based on their share
     */
    function getStakerYield(address staker) external view returns (uint256) {
        if (totalCShares == 0) return 0;
        
        uint256 stakerShare = (cSharesHeld[staker] * 10**18) / totalCShares;
        return (accumulatedRewardPool * stakerShare) / 10**18;
    }

    /**
     * @dev Get days elapsed since stake started
     */
    function getDaysElapsed(address staker) public view returns (uint256) {
        require(stakes[staker].active, "No active stake");
        uint256 timeElapsed = block.timestamp - stakes[staker].startTime;
        return timeElapsed / 1 days;
    }

    /**
     * @dev Check if stake period is complete
     */
    function isStakePeriodComplete(address staker) public view returns (bool) {
        require(stakes[staker].active, "No active stake");
        uint256 daysElapsed = getDaysElapsed(staker);
        return daysElapsed >= stakes[staker].duration;
    }

    /**
     * @dev Calculate penalty for early unstake (< 180 days)
     * Whitepaper formula for stakes < 180 days:
     * - 0 days: penalty = 0
     * - < 90 days: penalty = (earned yield × 50) ÷ (days elapsed)
     * - = 90 days: forfeit all yield
     * - > 90 days: keep yield from day 91 onwards
     */
    function calculatePenaltyShortStake(address staker) internal view returns (uint256 penalty, uint256 yieldToReturn) {
        Stake memory stake = stakes[staker];
        uint256 daysElapsed = getDaysElapsed(staker);
        uint256 earnedYield = stake.earnedYield;

        if (daysElapsed == 0) {
            return (0, 0);
        } else if (daysElapsed < 90) {
            uint256 calculatedPenalty = (earnedYield * 50) / daysElapsed;
            return (calculatedPenalty, earnedYield > calculatedPenalty ? earnedYield - calculatedPenalty : 0);
        } else if (daysElapsed == 90) {
            return (earnedYield, 0);
        } else {
            // > 90 days: keep yield from day 91 onwards
            // Estimate: daily yield = earnedYield / daysElapsed
            uint256 dailyYield = earnedYield / daysElapsed;
            uint256 yieldAfterDay90 = dailyYield * (daysElapsed - 90);
            return (earnedYield - yieldAfterDay90, yieldAfterDay90);
        }
    }

    /**
     * @dev Calculate penalty for early unstake (>= 180 days)
     * Whitepaper formula for stakes >= 180 days:
     * - 0 days: penalty = 0
     * - < 50%: penalty = earned yield + 20% of principal
     * - = 50%: forfeit all yield
     * - > 50%: keep yield from day after 50% mark
     */
    function calculatePenaltyLongStake(address staker) internal view returns (uint256 penalty, uint256 principalReturn, uint256 yieldToReturn) {
        Stake memory stake = stakes[staker];
        uint256 daysElapsed = getDaysElapsed(staker);
        uint256 halfDuration = stake.duration / 2;
        uint256 earnedYield = stake.earnedYield;

        if (daysElapsed == 0) {
            return (0, stake.amount, 0);
        } else if (daysElapsed < halfDuration) {
            uint256 principalPenalty = (stake.amount * 20) / 100;
            uint256 totalPenalty = earnedYield + principalPenalty;
            return (totalPenalty, stake.amount - principalPenalty, 0);
        } else if (daysElapsed == halfDuration) {
            return (earnedYield, stake.amount, 0);
        } else {
            // > 50%: keep yield from day after 50% mark
            uint256 dailyYield = earnedYield / daysElapsed;
            uint256 daysAfterHalf = daysElapsed - halfDuration;
            uint256 yieldAfterHalf = dailyYield * daysAfterHalf;
            return (earnedYield - yieldAfterHalf, stake.amount, yieldAfterHalf);
        }
    }

    /**
     * @dev Execute emergency end stake with penalties
     */
    function emergencyEndStake() external nonReentrant {
        require(stakes[msg.sender].active, "No active stake");
        Stake storage stake = stakes[msg.sender];
        require(!isStakePeriodComplete(msg.sender), "Use endStake instead");

        uint256 daysElapsed = getDaysElapsed(msg.sender);
        uint256 penalty;
        uint256 principalReturn;
        uint256 yieldReturn;

        if (stake.duration < 180) {
            (penalty, yieldReturn) = calculatePenaltyShortStake(msg.sender);
            principalReturn = stake.amount;
        } else {
            (penalty, principalReturn, yieldReturn) = calculatePenaltyLongStake(msg.sender);
        }

        // Distribute penalties
        uint256 burnAmount = (penalty * PENALTY_BURN_PERCENTAGE) / 100;
        uint256 poolAmount = (penalty * PENALTY_POOL_PERCENTAGE) / 100;
        uint256 projectAmount = (penalty * PENALTY_PROJECT_PERCENTAGE) / 100;

        accumulatedRewardPool += poolAmount;

        // Return tokens to staker
        uint256 totalReturn = principalReturn + yieldReturn;
        escrowToken.safeTransfer(msg.sender, totalReturn);

        // Remove C-Shares
        totalCShares -= stake.cShares;
        cSharesHeld[msg.sender] = 0;

        stake.active = false;

        emit EmergencyEndStakeExecuted(
            msg.sender,
            principalReturn,
            yieldReturn,
            penalty,
            daysElapsed
        );
    }

    /**
     * @dev Execute normal end stake after lock period completes
     */
    function endStake() external nonReentrant {
        require(stakes[msg.sender].active, "No active stake");
        Stake storage stake = stakes[msg.sender];
        require(isStakePeriodComplete(msg.sender), "Stake period not complete");

        uint256 timeSinceCompletion = block.timestamp - (stake.startTime + (stake.duration * 1 days));
        uint256 daysLateUnstake = timeSinceCompletion / 1 days;

        uint256 principalReturn = stake.amount;
        uint256 yieldReturn = stake.earnedYield;

        // Apply late unstake penalties if after grace period
        if (daysLateUnstake > GRACE_PERIOD_DAYS) {
            uint256 daysIntoLate = daysLateUnstake - GRACE_PERIOD_DAYS;
            if (daysIntoLate > MAX_LATE_UNSTAKE_DAYS) {
                daysIntoLate = MAX_LATE_UNSTAKE_DAYS;
            }

            uint256 totalToDeduct = principalReturn + yieldReturn;
            uint256 dailyPenalty = (totalToDeduct * LATE_UNSTAKE_PENALTY_PERCENTAGE) / LATE_UNSTAKE_PENALTY_DIVISOR;
            uint256 totalLatePenalty = dailyPenalty * daysIntoLate;

            if (totalLatePenalty > totalToDeduct) {
                principalReturn = 0;
                yieldReturn = 0;
            } else {
                uint256 remaining = totalToDeduct - totalLatePenalty;
                // Deduct from yield first, then principal
                if (yieldReturn >= totalLatePenalty) {
                    yieldReturn -= totalLatePenalty;
                } else {
                    principalReturn -= (totalLatePenalty - yieldReturn);
                    yieldReturn = 0;
                }
            }

            emit LateEndStakePenaltyApplied(msg.sender, totalLatePenalty, daysIntoLate);
        }

        uint256 totalReturn = principalReturn + yieldReturn;
        escrowToken.safeTransfer(msg.sender, totalReturn);

        // Update C-Share price if needed
        uint256 newCSharePrice = calculateNewCSharePrice(
            stake.amount + yieldReturn,
            stake.cShares,
            stake.duration
        );
        if (newCSharePrice > globalCSharePrice) {
            globalCSharePrice = newCSharePrice;
            emit CSharePriceUpdated(newCSharePrice);
        }

        // Remove C-Shares
        totalCShares -= stake.cShares;
        cSharesHeld[msg.sender] = 0;

        stake.active = false;
        stake.endStakeExecutedTime = block.timestamp;

        emit EndStakeExecuted(msg.sender, principalReturn, yieldReturn, globalCSharePrice);
    }

    /**
     * @dev Calculate new C-Share price after stake completion
     * Formula: (1,500,000,000 + min(total_tokens_paid, 150,000,000)) × total_tokens_paid
     *          ÷ ((1820 × num_c_shares) ÷ (1820 + min(3640, days_staked - 1)) × 1,500,000,000)
     */
    function calculateNewCSharePrice(
        uint256 totalTokensPaid,
        uint256 numCShares,
        uint256 daysStaked
    ) internal pure returns (uint256) {
        require(numCShares > 0, "Invalid number of shares");

        uint256 minTokens = totalTokensPaid > QUANTITY_BONUS_CAP ? QUANTITY_BONUS_CAP : totalTokensPaid;
        uint256 numerator = (QUANTITY_BONUS_DIVISOR + minTokens) * totalTokensPaid;

        uint256 daysComponent = daysStaked > 1 ? daysStaked - 1 : 1;
        uint256 maxDaysComponent = daysComponent > 3640 ? 3640 : daysComponent;

        uint256 denominator = ((TIME_BONUS_DIVISOR * numCShares) / (TIME_BONUS_DIVISOR + maxDaysComponent)) * QUANTITY_BONUS_DIVISOR;

        uint256 newPrice = numerator / denominator;
        return newPrice;
    }

    /**
     * @dev Get stake information for an address
     */
    function getStakeInfo(address staker) external view returns (
        uint256 amount,
        uint256 duration,
        uint256 startTime,
        uint256 cShares,
        uint256 earnedYield,
        bool active,
        uint256 daysElapsed
    ) {
        Stake memory stake = stakes[staker];
        uint256 elapsed = stake.active ? getDaysElapsed(staker) : 0;
        return (
            stake.amount,
            stake.duration,
            stake.startTime,
            stake.cShares,
            stake.earnedYield,
            stake.active,
            elapsed
        );
    }

    /**
     * @dev Emergency withdrawal function (owner only)
     */
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = escrowToken.balanceOf(address(this));
        escrowToken.safeTransfer(msg.sender, balance);
    }
}
