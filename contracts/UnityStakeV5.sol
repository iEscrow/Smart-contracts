// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @dev Extended ERC20 interface to support minting
interface IMintableERC20 is IERC20 {
    function mint(address to, uint256 amount) external;
}

contract TokenStaking is Ownable, ReentrancyGuard {
    struct StakeInfo {
        uint256 amount;
        uint256 start;
        uint256 end;
        uint256 daysStaked;
        uint256 rewardsClaimed;
        uint256 lastRewardCalculation;
        uint256 rewardAmount;
    }

    mapping(address => StakeInfo[]) private _stakes;

    uint256 private _minimumStakingAmount;
    uint256 private _maxStakeTokenLimit;
    uint256 private _totalStakedTokens;
    uint256 private _totalUsers;
    uint256 private _totalPaidTokens;

    uint256 public constant REWARD_RATE = 0.01 ether; // 0.01 tokens per second prorated
    uint256 private _earlyUnstakeFeePercentage;
    bool private _isStakingPaused;
    address private _tokenAddress;
    uint256 private _apyRate;

    uint256 public constant PERCENTAGE_DENOMINATOR = 10000;

    event Stake(address indexed user, uint256 amount);
    event UnStake(address indexed user, uint256 amount);
    event EarlyUnStakeFee(address indexed user, uint256 amount);
    event ClaimReward(address indexed user, uint256 amount);

    modifier whenTreasuryHasBalance(uint256 amount) {
        require(
            IERC20(_tokenAddress).balanceOf(address(this)) >= amount,
            "TokenStaking: insufficient funds in the treasury"
        );
        _;
    }

    constructor(
        address tokenAddress,
        uint256 apyRate,
        uint256 minimumStakingAmount,
        uint256 maxStakeTokenLimit,
        uint256 earlyUnstakeFeePercentage
    ) {
        require(tokenAddress != address(0), "TokenStaking: token address cannot be zero");
        _tokenAddress = tokenAddress;
        _apyRate = apyRate;
        _minimumStakingAmount = minimumStakingAmount;
        _maxStakeTokenLimit = maxStakeTokenLimit;
        _earlyUnstakeFeePercentage = earlyUnstakeFeePercentage;
    }

    /* View Methods */

    function getMinimumStakingAmount() external view returns (uint256) {
        return _minimumStakingAmount;
    }

    function getMaxStakingTokenLimit() external view returns (uint256) {
        return _maxStakeTokenLimit;
    }

    function getTotalStakedTokens() external view returns (uint256) {
        return _totalStakedTokens;
    }

    function getTotalUsers() external view returns (uint256) {
        return _totalUsers;
    }

    function getEarlyUnstakeFeePercentage() external view returns (uint256) {
        return _earlyUnstakeFeePercentage;
    }

    function getStakingStatus() external view returns (bool) {
        return _isStakingPaused;
    }

    function getAPY() external view returns (uint256) {
        return _apyRate;
    }

    function getWithdrawableAmount() external view returns (uint256) {
        return IERC20(_tokenAddress).balanceOf(address(this)) - (_totalStakedTokens * 1e18);
    }

    function getTreasuryAmount() external view returns (uint256) {
        return IERC20(_tokenAddress).balanceOf(address(this));
    }

    function getActiveStakes(address user) external view returns (StakeInfo[] memory) {
        return _stakes[user];
    }

    /* Owner Methods */

    function updateMinimumStakingAmount(uint256 newAmount) external onlyOwner {
        _minimumStakingAmount = newAmount;
    }

    function updateMaximumStakingTokenLimit(uint256 newAmount) external onlyOwner {
        _maxStakeTokenLimit = newAmount;
    }

    function updateEarlyUnstakeFeePercentage(uint256 newPercentage) external onlyOwner {
        _earlyUnstakeFeePercentage = newPercentage;
    }

    function toggleStakingStatus() external onlyOwner {
        _isStakingPaused = !_isStakingPaused;
    }

    function withdraw(uint256 amount) external onlyOwner nonReentrant whenTreasuryHasBalance(amount) {
        IERC20(_tokenAddress).transfer(msg.sender, amount);
    }

    /* User Methods */

    function stake(uint256 amount, uint256 daysStaked) external nonReentrant {
        require(!_isStakingPaused, "TokenStaking: staking is paused");
        require(amount >= _minimumStakingAmount, "TokenStaking: amount below minimum");
        require(amount <= _maxStakeTokenLimit, "TokenStaking: exceeds max staking limit");

        uint256 currentTime = block.timestamp;
        uint256 endTime = currentTime + daysStaked * 1 days;

        // Transfer and burn initial tokens
        IERC20(_tokenAddress).transferFrom(msg.sender, address(this), amount * 1e18);
        IERC20(_tokenAddress).transfer(address(0), amount * 1e18);

        // Record stake
        StakeInfo memory newStake = StakeInfo({
            amount: amount,
            start: currentTime,
            end: endTime,
            daysStaked: daysStaked,
            rewardsClaimed: 0,
            lastRewardCalculation: currentTime,
            rewardAmount: 0
        });

        _stakes[msg.sender].push(newStake);

        // Update counters
        if (_stakes[msg.sender].length == 1) {
            _totalUsers += 1;
        }
        _totalStakedTokens += amount;

        emit Stake(msg.sender, amount);
    }

    function unstakeSpecific(uint256 index) external nonReentrant {
        StakeInfo[] storage stakes = _stakes[msg.sender];
        require(index < stakes.length, "TokenStaking: invalid stake index");

        StakeInfo storage s = stakes[index];
        uint256 principal = s.amount;

        // Calculate pending rewards
        uint256 elapsed = block.timestamp > s.end
            ? s.end - s.lastRewardCalculation
            : block.timestamp - s.lastRewardCalculation;
        uint256 rewardPerSec = (REWARD_RATE * principal * 1e18) / _totalStakedTokens;
        uint256 pendingReward = (elapsed * rewardPerSec) / 1e18 + s.rewardAmount;

        // Early unstake penalty on rewards if before end
        uint256 fee = 0;
        if (block.timestamp < s.end) {
            fee = (pendingReward * _earlyUnstakeFeePercentage) / PERCENTAGE_DENOMINATOR;
            IERC20(_tokenAddress).transfer(address(0), fee);
            emit EarlyUnStakeFee(msg.sender, fee);
        }

        uint256 rewardToSend = pendingReward - fee;

        // Update totals and remove stake
        _totalStakedTokens -= principal;
        _totalPaidTokens += rewardToSend;
        stakes[index] = stakes[stakes.length - 1];
        stakes.pop();
        if (stakes.length == 0) {
            _totalUsers -= 1;
        }

        // Re-mint principal and send rewards
        IMintableERC20(_tokenAddress).mint(msg.sender, principal * 1e18);
        IERC20(_tokenAddress).transfer(msg.sender, rewardToSend);

        emit UnStake(msg.sender, principal);
        emit ClaimReward(msg.sender, rewardToSend);
    }

    function getCurrentTime() internal view virtual returns (uint256) {
        return block.timestamp;
    }
}
