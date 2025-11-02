// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TokenVesting
 * @notice Vesting contract for 1% of ESCROW token supply (1 billion tokens)
 * @dev Tokens are locked for 3 years (cliff), then released 20% every 6 months for 2 years
 * 
 * Vesting Schedule:
 * - Year 0-3: 100% locked (cliff period)
 * - Year 3: 20% unlocked
 * - Year 3.5: 40% unlocked (cumulative)
 * - Year 4: 60% unlocked (cumulative)
 * - Year 4.5: 80% unlocked (cumulative)
 * - Year 5: 100% unlocked (cumulative)
 * 
 * Distribution:
 * - Founders, Team, and Advisors who contributed to the project
 */
contract TokenVesting is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    
    // ============ IMMUTABLE STATE ============
    
    /// @notice ESCROW token contract
    IERC20 public immutable escrowToken;
    
    /// @notice Vesting start timestamp
    uint256 public immutable startTime;
    
    // ============ CONSTANTS ============
    
    /// @notice Total tokens allocated for vesting (1% of 100B = 1B tokens)
    uint256 public constant TOTAL_ALLOCATION = 1_000_000_000 * 1e18;
    
    /// @notice Cliff period - tokens locked for 3 years
    uint256 public constant CLIFF_PERIOD = 3 * 365 days;
    
    /// @notice Vesting interval - 6 months between releases
    uint256 public constant VESTING_INTERVAL = 180 days;
    
    /// @notice Number of vesting intervals (5 releases of 20% each)
    uint256 public constant VESTING_INTERVALS = 5;
    
    /// @notice Percentage released per interval (in basis points: 2000 = 20%)
    uint256 public constant RELEASE_PERCENTAGE = 2000;
    
    /// @notice Basis points denominator (10000 = 100%)
    uint256 public constant BASIS_POINTS = 10000;
    
    // ============ BENEFICIARY ADDRESSES ============
    
    // 10M allocations (1% each)
    address public constant BENEFICIARY1 = 0x04435410a78192baAfa00c72C659aD3187a2C2cF;
    address public constant BENEFICIARY2 = 0x9005132849bC9585A948269D96F23f56e5981A61;
    address public constant BENEFICIARY3 = 0x1C5cf9Cb69effeeb31E261BB6519AF7247A97A74;
    address public constant BENEFICIARY4 = 0x04D83B2BdF89fe4C781Ec8aE3D672c610080B319;
    address public constant BENEFICIARY5 = 0xA5F415dA5b5E63aFc8f0c378F047671592A842Fe;
    address public constant BENEFICIARY6 = 0x77aB60050DFA1E2764366BC52A83EEab1E1a35ad;
    address public constant BENEFICIARY7 = 0x543ed850e2df486e2B37A602926C12b97b910405;
    address public constant BENEFICIARY8 = 0xC259811079610E1a60Bf5ebCb7d0F8Ac3857b1d6;
    address public constant BENEFICIARY9 = 0x68f5d8e68abDf9c6C0233DE2bdAda5e18CC6634d;
    address public constant BENEFICIARY10 = 0xCACEeBfD2E88ce3741dd45622cDf5D2f3166e8f5;
    address public constant BENEFICIARY11 = 0x507541B0Caf529a063E97c6C145E521d3F394264;
    
    // 40M allocation (4%)
    address public constant BENEFICIARY12 = 0x2C9760E45abB8879A6ac86d3CA19012Cf513738d;
    
    // 50M allocations (5% each)
    address public constant BENEFICIARY13 = 0x30D3d7C9A4276a5A63EE9c36d6C69CEA3e6B08da;
    address public constant BENEFICIARY14 = 0x69873ef24F48205036177b03628f8727b8445999;
    address public constant BENEFICIARY15 = 0x790823b7bd58f1b84D99Cd7d474C24Af894deE2c;
    address public constant BENEFICIARY16 = 0x9f1Ec9342a567E16703076385763f49aABFFA15e;
    address public constant BENEFICIARY17 = 0x687B309a341B453084539f83081B292462a92c4D;
    address public constant BENEFICIARY18 = 0x01553Bc974Ed86f892813E535B1Ed03a384212F5;
    address public constant BENEFICIARY19 = 0xE0C7f8329F0d401bE419A2F15371aB2DAfe3f7c4;
    address public constant BENEFICIARY20 = 0x6fBa9db2Ca25cC280ec559aD44540bD7B061a66B;
    address public constant BENEFICIARY21 = 0xfa44D3E91aBf1327566a2c34E9f46C332B412634;
    address public constant BENEFICIARY22 = 0x5d8d1EA81af164051F341fB6224F243775Dea07a;
    address public constant BENEFICIARY23 = 0x37006C70d09fc59abF3EeE7a1B244d6c831cb281;
    address public constant BENEFICIARY24 = 0xC6808526ed02162668Ec35D7C0b16f1C99802534;
    address public constant BENEFICIARY25 = 0x91C665974574a51bd9Eb23aE79B26C58415eF6b2;
    address public constant BENEFICIARY26 = 0x658ba47F95541d8919C46b3488dE12be7587167D;
    address public constant BENEFICIARY27 = 0x54920dEb99489F36AB7204F727E20B72fB391e7b;
    address public constant BENEFICIARY28 = 0x4C11b6D0d1aD06F95966372014097AE3411cE7b9;
    address public constant BENEFICIARY29 = 0x277cAebe8E2d2284752d75853Fe70aF00dE893ac;
    
    // ============ ALLOCATIONS ============
    
    /// @notice Allocation percentages in basis points (must sum to 10000 = 100%)
    // 10M each = 1% each (100 basis points)
    uint256 public constant ALLOCATION1 = 100;   // 1%
    uint256 public constant ALLOCATION2 = 100;   // 1%
    uint256 public constant ALLOCATION3 = 100;   // 1%
    uint256 public constant ALLOCATION4 = 100;   // 1%
    uint256 public constant ALLOCATION5 = 100;   // 1%
    uint256 public constant ALLOCATION6 = 100;   // 1%
    uint256 public constant ALLOCATION7 = 100;   // 1%
    uint256 public constant ALLOCATION8 = 100;   // 1%
    uint256 public constant ALLOCATION9 = 100;   // 1%
    uint256 public constant ALLOCATION10 = 100;  // 1%
    uint256 public constant ALLOCATION11 = 100;  // 1%
    
    // 40M = 4% (400 basis points)
    uint256 public constant ALLOCATION12 = 400;  // 4%
    
    // 50M each = 5% each (500 basis points)
    uint256 public constant ALLOCATION13 = 500;  // 5%
    uint256 public constant ALLOCATION14 = 500;  // 5%
    uint256 public constant ALLOCATION15 = 500;  // 5%
    uint256 public constant ALLOCATION16 = 500;  // 5%
    uint256 public constant ALLOCATION17 = 500;  // 5%
    uint256 public constant ALLOCATION18 = 500;  // 5%
    uint256 public constant ALLOCATION19 = 500;  // 5%
    uint256 public constant ALLOCATION20 = 500;  // 5%
    uint256 public constant ALLOCATION21 = 500;  // 5%
    uint256 public constant ALLOCATION22 = 500;  // 5%
    uint256 public constant ALLOCATION23 = 500;  // 5%
    uint256 public constant ALLOCATION24 = 500;  // 5%
    uint256 public constant ALLOCATION25 = 500;  // 5%
    uint256 public constant ALLOCATION26 = 500;  // 5%
    uint256 public constant ALLOCATION27 = 500;  // 5%
    uint256 public constant ALLOCATION28 = 500;  // 5%
    uint256 public constant ALLOCATION29 = 500;  // 5%
    
    // ============ STATE ============
    
    /// @notice Track how much each beneficiary has released
    mapping(address => uint256) public released;
    
    // ============ EVENTS ============
    
    event TokensReleased(address indexed beneficiary, uint256 amount);
    event VestingStarted(uint256 startTime);
    
    // ============ CONSTRUCTOR ============
    
    constructor(address _escrowToken, address _owner) Ownable(_owner) {
        require(_escrowToken != address(0), "Invalid token address");
        
        // Validate allocations sum to 100%
        require(
            ALLOCATION1 + ALLOCATION2 + ALLOCATION3 + ALLOCATION4 + ALLOCATION5 +
            ALLOCATION6 + ALLOCATION7 + ALLOCATION8 + ALLOCATION9 + ALLOCATION10 +
            ALLOCATION11 + ALLOCATION12 + ALLOCATION13 + ALLOCATION14 + ALLOCATION15 +
            ALLOCATION16 + ALLOCATION17 + ALLOCATION18 + ALLOCATION19 + ALLOCATION20 +
            ALLOCATION21 + ALLOCATION22 + ALLOCATION23 + ALLOCATION24 + ALLOCATION25 +
            ALLOCATION26 + ALLOCATION27 + ALLOCATION28 + ALLOCATION29 == BASIS_POINTS,
            "Allocations must sum to 100%"
        );
        
        escrowToken = IERC20(_escrowToken);
        startTime = block.timestamp;
        
        emit VestingStarted(startTime);
    }
    
    // ============ CLAIM FUNCTIONS ============
    
    /// @notice Claim vested tokens
    /// @dev Can be called by any beneficiary to claim their vested tokens
    function claim() external nonReentrant {
        uint256 vested = getVestedAmount(msg.sender);
        uint256 claimable = vested - released[msg.sender];
        
        require(claimable > 0, "Nothing to claim");
        
        released[msg.sender] += claimable;
        
        escrowToken.safeTransfer(msg.sender, claimable);
        
        emit TokensReleased(msg.sender, claimable);
    }
    
    // ============ VIEW FUNCTIONS ============
    
    /// @notice Get total vested amount for a beneficiary
    /// @param beneficiary Address to check
    /// @return Total amount that has vested (not necessarily claimed)
    function getVestedAmount(address beneficiary) public view returns (uint256) {
        uint256 totalAllocation = getTotalAllocation(beneficiary);
        
        if (totalAllocation == 0) {
            return 0;
        }
        
        // Still in cliff period
        if (block.timestamp < startTime + CLIFF_PERIOD) {
            return 0;
        }
        
        // Calculate time since cliff ended
        uint256 timeSinceCliff = block.timestamp - (startTime + CLIFF_PERIOD);
        
        // Calculate how many intervals have passed
        uint256 intervalsPassed = timeSinceCliff / VESTING_INTERVAL;
        
        // If all intervals passed, return full allocation
        if (intervalsPassed >= VESTING_INTERVALS) {
            return totalAllocation;
        }
        
        // Calculate vested percentage: (intervals + 1) * 20%
        // +1 because first unlock happens immediately after cliff
        uint256 vestedPercentage = (intervalsPassed + 1) * RELEASE_PERCENTAGE;
        
        return (totalAllocation * vestedPercentage) / BASIS_POINTS;
    }
    
    /// @notice Get claimable amount for a beneficiary
    /// @param beneficiary Address to check
    /// @return Amount that can be claimed right now
    function getClaimableAmount(address beneficiary) external view returns (uint256) {
        uint256 vested = getVestedAmount(beneficiary);
        return vested - released[beneficiary];
    }
    
    /// @notice Get total allocation for a beneficiary
    /// @param beneficiary Address to check
    /// @return Total tokens allocated to beneficiary
    function getTotalAllocation(address beneficiary) public pure returns (uint256) {
        if (beneficiary == BENEFICIARY1) {
            return (TOTAL_ALLOCATION * ALLOCATION1) / BASIS_POINTS;
        } else if (beneficiary == BENEFICIARY2) {
            return (TOTAL_ALLOCATION * ALLOCATION2) / BASIS_POINTS;
        } else if (beneficiary == BENEFICIARY3) {
            return (TOTAL_ALLOCATION * ALLOCATION3) / BASIS_POINTS;
        } else if (beneficiary == BENEFICIARY4) {
            return (TOTAL_ALLOCATION * ALLOCATION4) / BASIS_POINTS;
        } else if (beneficiary == BENEFICIARY5) {
            return (TOTAL_ALLOCATION * ALLOCATION5) / BASIS_POINTS;
        } else if (beneficiary == BENEFICIARY6) {
            return (TOTAL_ALLOCATION * ALLOCATION6) / BASIS_POINTS;
        } else if (beneficiary == BENEFICIARY7) {
            return (TOTAL_ALLOCATION * ALLOCATION7) / BASIS_POINTS;
        } else if (beneficiary == BENEFICIARY8) {
            return (TOTAL_ALLOCATION * ALLOCATION8) / BASIS_POINTS;
        } else if (beneficiary == BENEFICIARY9) {
            return (TOTAL_ALLOCATION * ALLOCATION9) / BASIS_POINTS;
        } else if (beneficiary == BENEFICIARY10) {
            return (TOTAL_ALLOCATION * ALLOCATION10) / BASIS_POINTS;
        } else if (beneficiary == BENEFICIARY11) {
            return (TOTAL_ALLOCATION * ALLOCATION11) / BASIS_POINTS;
        } else if (beneficiary == BENEFICIARY12) {
            return (TOTAL_ALLOCATION * ALLOCATION12) / BASIS_POINTS;
        } else if (beneficiary == BENEFICIARY13) {
            return (TOTAL_ALLOCATION * ALLOCATION13) / BASIS_POINTS;
        } else if (beneficiary == BENEFICIARY14) {
            return (TOTAL_ALLOCATION * ALLOCATION14) / BASIS_POINTS;
        } else if (beneficiary == BENEFICIARY15) {
            return (TOTAL_ALLOCATION * ALLOCATION15) / BASIS_POINTS;
        } else if (beneficiary == BENEFICIARY16) {
            return (TOTAL_ALLOCATION * ALLOCATION16) / BASIS_POINTS;
        } else if (beneficiary == BENEFICIARY17) {
            return (TOTAL_ALLOCATION * ALLOCATION17) / BASIS_POINTS;
        } else if (beneficiary == BENEFICIARY18) {
            return (TOTAL_ALLOCATION * ALLOCATION18) / BASIS_POINTS;
        } else if (beneficiary == BENEFICIARY19) {
            return (TOTAL_ALLOCATION * ALLOCATION19) / BASIS_POINTS;
        } else if (beneficiary == BENEFICIARY20) {
            return (TOTAL_ALLOCATION * ALLOCATION20) / BASIS_POINTS;
        } else if (beneficiary == BENEFICIARY21) {
            return (TOTAL_ALLOCATION * ALLOCATION21) / BASIS_POINTS;
        } else if (beneficiary == BENEFICIARY22) {
            return (TOTAL_ALLOCATION * ALLOCATION22) / BASIS_POINTS;
        } else if (beneficiary == BENEFICIARY23) {
            return (TOTAL_ALLOCATION * ALLOCATION23) / BASIS_POINTS;
        } else if (beneficiary == BENEFICIARY24) {
            return (TOTAL_ALLOCATION * ALLOCATION24) / BASIS_POINTS;
        } else if (beneficiary == BENEFICIARY25) {
            return (TOTAL_ALLOCATION * ALLOCATION25) / BASIS_POINTS;
        } else if (beneficiary == BENEFICIARY26) {
            return (TOTAL_ALLOCATION * ALLOCATION26) / BASIS_POINTS;
        } else if (beneficiary == BENEFICIARY27) {
            return (TOTAL_ALLOCATION * ALLOCATION27) / BASIS_POINTS;
        } else if (beneficiary == BENEFICIARY28) {
            return (TOTAL_ALLOCATION * ALLOCATION28) / BASIS_POINTS;
        } else if (beneficiary == BENEFICIARY29) {
            return (TOTAL_ALLOCATION * ALLOCATION29) / BASIS_POINTS;
        }
        return 0;
    }
    
    /// @notice Get vesting schedule information
    /// @return cliffEnd Timestamp when cliff period ends
    /// @return vestingEnd Timestamp when vesting fully completes
    /// @return currentTime Current block timestamp
    function getVestingSchedule() external view returns (
        uint256 cliffEnd,
        uint256 vestingEnd,
        uint256 currentTime
    ) {
        cliffEnd = startTime + CLIFF_PERIOD;
        vestingEnd = cliffEnd + (VESTING_INTERVAL * (VESTING_INTERVALS - 1));
        currentTime = block.timestamp;
    }
    
    /// @notice Get beneficiary information
    /// @param beneficiary Address to check
    /// @return totalAllocation Total tokens allocated
    /// @return vested Total tokens vested so far
    /// @return releasedAmount Total tokens already claimed
    /// @return claimable Tokens available to claim now
    function getBeneficiaryInfo(address beneficiary) external view returns (
        uint256 totalAllocation,
        uint256 vested,
        uint256 releasedAmount,
        uint256 claimable
    ) {
        totalAllocation = getTotalAllocation(beneficiary);
        vested = getVestedAmount(beneficiary);
        releasedAmount = released[beneficiary];
        claimable = vested - releasedAmount;
    }
    
    /// @notice Check if vesting has started
    function hasStarted() external view returns (bool) {
        return block.timestamp >= startTime;
    }
    
    /// @notice Check if cliff period has ended
    function hasCliffEnded() external view returns (bool) {
        return block.timestamp >= startTime + CLIFF_PERIOD;
    }
    
    /// @notice Check if vesting is fully completed
    function isFullyVested() external view returns (bool) {
        return block.timestamp >= startTime + CLIFF_PERIOD + (VESTING_INTERVAL * (VESTING_INTERVALS - 1));
    }
    
    // ============ EMERGENCY FUNCTIONS ============
    
    /// @notice Emergency withdrawal (only owner, only for tokens OTHER than ESCROW)
    /// @param token Token to withdraw
    /// @param amount Amount to withdraw
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        require(token != address(escrowToken), "Cannot withdraw vesting tokens");
        IERC20(token).safeTransfer(owner(), amount);
    }
}
