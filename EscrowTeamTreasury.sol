// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title EscrowTeamTreasury
 * @author iEscrow Team
 * @notice Treasury contract for Founders, Team & Advisors (1% allocation)
 * @dev Flexible vesting with 3-year lock + 2-year release (20% every 6 months)
 * @custom:security-contact security@iescrow.com
 * @custom:whitepaper-ref Implements vesting schedule as specified in project tokenomics
 */

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract EscrowTeamTreasury is Ownable {
    using SafeERC20 for IERC20;
    
    // ============ CONSTANTS ============
    
    /// @notice Total allocation: 1% of 100B = 1 billion tokens
    uint256 public constant TOTAL_ALLOCATION = 1_000_000_000 * 1e18;
    
    /// @notice Initial lock period: 3 years
    uint256 public constant LOCK_DURATION = 3 * 365 days; // 3 years exactly
    
    /// @notice Vesting interval: 6 months
    uint256 public constant VESTING_INTERVAL = 180 days;
    
    /// @notice Number of vesting milestones
    uint256 public constant VESTING_MILESTONES = 5;
    
    /// @notice Percentage per milestone (20%)
    uint256 public constant PERCENTAGE_PER_MILESTONE = 2000; // 20% in basis points
    uint256 public constant BASIS_POINTS = 10000;
    
    // ============ STRUCTS ============
    
    /// @notice Structure containing beneficiary information and vesting state
    /// @dev Tracks allocation, claims, and status for each beneficiary
    /// @param totalAllocation Total tokens allocated to this beneficiary
    /// @param claimedAmount Amount of tokens already claimed
    /// @param isActive Whether beneficiary is currently active
    /// @param revoked Whether allocation has been revoked by admin
    struct Beneficiary {
        uint256 totalAllocation;      // Total tokens allocated
        uint256 claimedAmount;        // Amount already claimed
        bool isActive;                // Whether beneficiary is active
        bool revoked;                 // Whether allocation was revoked
    }
    
    // ============ STATE VARIABLES ============
    
    /// @notice ESCROW token
    IERC20 public immutable escrowToken;
    
    /// @notice Treasury start time (3-year lock starts from here)
    uint256 public immutable treasuryStartTime;
    
    /// @notice First vesting unlock time (after 3 years)
    uint256 public immutable firstUnlockTime;
    
    /// @notice Beneficiaries mapping
    mapping(address => Beneficiary) public beneficiaries;
    
    /// @notice List of all beneficiary addresses
    address[] public beneficiaryList;
    
    /// @notice Total allocated to all beneficiaries
    uint256 public totalAllocated;
    
    /// @notice Total claimed by all beneficiaries
    uint256 public totalClaimed;
    
    /// @notice Whether allocations are locked (no more changes)
    bool public allocationsLocked;
    
    /// @notice Treasury funded status
    bool public treasuryFunded;
    
    /// @notice List of initial beneficiary addresses
    address[] private initialBeneficiaries = [
        0x04435410a78192baAfa00c72C659aD3187a2C2cF,
        0x9005132849bC9585A948269D96F23f56e5981A61,
        0x1C5cf9Cb69effeeb31E261BB6519AF7247A97A74,
        0x03a54ADc7101393776C200529A454b4cDc3545C5,
        0x04D83B2BdF89fe4C781Ec8aE3D672c610080B319,
        0xA5F415dA5b5E63aFc8f0c378F047671592A842Fe,
        0x77aB60050DFA1E2764366BC52A83EEab1E1a35ad,
        0x543ed850e2df486e2B37A602926C12b97b910405,
        0xC259811079610E1a60Bf5ebCb7d0F8Ac3857b1d6,
        0x68f5d8e68abDf9c6C0233DE2bdAda5e18CC6634d,
        0x30D3d7C9A4276a5A63EE9c36d6C69CEA3e6B08da,
        0x69873ef24F48205036177b03628f8727b8445999,
        0x790823b7bd58f1b84D99Cd7d474C24Af894deE2c,
        0x9f1Ec9342a567E16703076385763f49aABFFA15e,
        0x687B309a341B453084539f83081B292462a92c4D,
        0x01553Bc974Ed86f892813E535B1Ed03a384212F5,
        0xE0C7f8329F0d401bE419A2F15371aB2DAfe3f7c4,
        0x6fBa9db2Ca25cC280ec559aD44540bD7B061a66B,
        0xfa44D3E91aBf1327566a2c34E9f46C332B412634,
        0x5d8d1EA81af164051F341fB6224F243775Dea07a,
        0x37006C70d09fc59abF3EeE7a1B244d6c831cb281,
        0xC6808526ed02162668Ec35D7C0b16f1C99802534,
        0x91C665974574a51bd9Eb23aE79B26C58415eF6b2,
        0x658ba47F95541d8919C46b3488dE12be7587167D,
        0x54920dEb99489F36AB7204F727E20B72fB391e7b,
        0x4C11b6D0d1aD06F95966372014097AE3411cE7b9,
        0x277cAebe8E2d2284752d75853Fe70aF00dE893ac,
        0x2C9760E45abB8879A6ac86d3CA19012Cf513738d
    ];

    /// @notice Corresponding allocations (10M or 50M tokens each)
    uint256[] private initialAllocations = [
        10_000_000 * 1e18, 10_000_000 * 1e18, 10_000_000 * 1e18, 10_000_000 * 1e18,
        10_000_000 * 1e18, 10_000_000 * 1e18, 10_000_000 * 1e18, 10_000_000 * 1e18,
        10_000_000 * 1e18, 10_000_000 * 1e18, 50_000_000 * 1e18, 50_000_000 * 1e18,
        50_000_000 * 1e18, 50_000_000 * 1e18, 50_000_000 * 1e18, 50_000_000 * 1e18,
        50_000_000 * 1e18, 50_000_000 * 1e18, 50_000_000 * 1e18, 50_000_000 * 1e18,
        50_000_000 * 1e18, 50_000_000 * 1e18, 50_000_000 * 1e18, 50_000_000 * 1e18,
        50_000_000 * 1e18, 50_000_000 * 1e18, 50_000_000 * 1e18, 50_000_000 * 1e18
    ];
    
    // ============ EVENTS ============
    
    /// @notice Emitted when treasury is funded with tokens
    /// @param amount Amount of tokens funded
    /// @param timestamp Time when funding occurred
    event TreasuryFunded(uint256 amount, uint256 timestamp);
    
    /// @notice Emitted when a new beneficiary is added
    /// @param beneficiary Address of the new beneficiary
    /// @param allocation Token allocation for the beneficiary
    event BeneficiaryAdded(address indexed beneficiary, uint256 allocation);
    
    /// @notice Emitted when beneficiary allocation is updated
    /// @param beneficiary Address of the beneficiary
    /// @param newAllocation New token allocation amount
    event BeneficiaryUpdated(address indexed beneficiary, uint256 newAllocation);
    
    /// @notice Emitted when beneficiary is removed
    /// @param beneficiary Address of the removed beneficiary
    /// @param allocation Allocation that was removed
    event BeneficiaryRemoved(address indexed beneficiary, uint256 allocation);
    
    /// @notice Emitted when tokens are claimed by a beneficiary
    /// @param beneficiary Address that claimed tokens
    /// @param amount Amount of tokens claimed
    /// @param milestone Vesting milestone when claimed
    event TokensClaimed(address indexed beneficiary, uint256 amount, uint256 milestone);
    
    /// @notice Emitted when beneficiary allocation is revoked
    /// @param beneficiary Address whose allocation was revoked
    /// @param unvestedAmount Amount of unvested tokens recovered
    event AllocationRevoked(address indexed beneficiary, uint256 unvestedAmount);
    
    /// @notice Emitted when allocations are locked (no more changes allowed)
    /// @param timestamp Time when allocations were locked
    event AllocationsLocked(uint256 timestamp);
    
    // ============ ERRORS ============
    
    /// @notice Error thrown when address is invalid (zero address)
    error InvalidAddress();
    
    /// @notice Error thrown when amount is invalid (zero amount)
    error InvalidAmount();
    
    /// @notice Error thrown when allocation would exceed total allocation limit
    error ExceedsTotalAllocation();
    
    /// @notice Error thrown when beneficiary is already allocated
    error AlreadyAllocated();
    
    /// @notice Error thrown when address is not a beneficiary
    error NotBeneficiary();
    
    /// @notice Error thrown when trying to modify allocations after they are locked
    error AllocationsAlreadyLocked();
    
    /// @notice Error thrown when allocations are not locked but should be
    error AllocationsNotLocked();
    
    /// @notice Error thrown when treasury is not funded but operation requires it
    error TreasuryNotFunded();
    
    /// @notice Error thrown when treasury is already funded
    error TreasuryAlreadyFunded();
    
    /// @notice Error thrown when lock period has not ended
    error LockPeriodNotEnded();
    
    /// @notice Error thrown when no tokens are available to claim
    error NoTokensAvailable();
    
    /// @notice Error thrown when allocation has already been revoked
    error AllocationAlreadyRevoked();
    
    /// @notice Error thrown when milestone value is invalid
    error InvalidMilestone();
    
    /// @notice Error thrown when balance is insufficient for operation
    error InsufficientBalance();
    
    // ============ CONSTRUCTOR ============
    
    /**
     * @notice Initialize treasury contract
     * @param _escrowToken Address of ESCROW token
     */
    constructor(address _escrowToken) Ownable(msg.sender) {
        if (_escrowToken == address(0)) revert InvalidAddress();
        
        escrowToken = IERC20(_escrowToken);
        treasuryStartTime = block.timestamp;
        firstUnlockTime = block.timestamp + LOCK_DURATION;
        
        // Initialize beneficiaries from hardcoded lists
        for (uint256 i = 0; i < initialBeneficiaries.length; i++) {
            beneficiaries[initialBeneficiaries[i]] = Beneficiary({
                totalAllocation: initialAllocations[i],
                claimedAmount: 0,
                isActive: true,
                revoked: false
            });
            beneficiaryList.push(initialBeneficiaries[i]);
            totalAllocated += initialAllocations[i];
        }
    }
    
    // ============ ADMIN FUNCTIONS ============
    
    /**
     * @notice Fund treasury with 1 billion ESCROW tokens (one-time only)
     */
    function fundTreasury() external onlyOwner {
        if (treasuryFunded) revert TreasuryAlreadyFunded();
        
        uint256 balance = escrowToken.balanceOf(msg.sender);
        if (balance < TOTAL_ALLOCATION) revert InsufficientBalance();
        
        escrowToken.safeTransferFrom(msg.sender, address(this), TOTAL_ALLOCATION);
        treasuryFunded = true;
        
        emit TreasuryFunded(TOTAL_ALLOCATION, block.timestamp);
    }
    
    /**
     * @notice Add new beneficiary (only before locking)
     * @param beneficiary Beneficiary address
     * @param allocation Amount of tokens to allocate
     */
    function addBeneficiary(address beneficiary, uint256 allocation) 
        external 
        onlyOwner 
    {
        if (allocationsLocked) revert AllocationsAlreadyLocked();
        if (!treasuryFunded) revert TreasuryNotFunded();
        if (beneficiary == address(0)) revert InvalidAddress();
        if (allocation == 0) revert InvalidAmount();
        if (beneficiaries[beneficiary].isActive) revert AlreadyAllocated();
        
        // Check total allocation doesn't exceed limit
        if (totalAllocated + allocation > TOTAL_ALLOCATION) {
            revert ExceedsTotalAllocation();
        }
        
        beneficiaries[beneficiary] = Beneficiary({
            totalAllocation: allocation,
            claimedAmount: 0,
            isActive: true,
            revoked: false
        });
        
        beneficiaryList.push(beneficiary);
        totalAllocated += allocation;
        
        emit BeneficiaryAdded(beneficiary, allocation);
    }
    
    /**
     * @notice Update beneficiary allocation (only before locking)
     * @param beneficiary Beneficiary address
     * @param newAllocation New allocation amount
     */
    function updateBeneficiary(address beneficiary, uint256 newAllocation) 
        external 
        onlyOwner 
    {
        if (allocationsLocked) revert AllocationsAlreadyLocked();
        if (!beneficiaries[beneficiary].isActive) revert NotBeneficiary();
        if (newAllocation == 0) revert InvalidAmount();
        
        Beneficiary storage b = beneficiaries[beneficiary];
        uint256 oldAllocation = b.totalAllocation;
        
        // Update total allocated
        totalAllocated = totalAllocated - oldAllocation + newAllocation;
        
        if (totalAllocated > TOTAL_ALLOCATION) revert ExceedsTotalAllocation();
        
        b.totalAllocation = newAllocation;
        
        emit BeneficiaryUpdated(beneficiary, newAllocation);
    }
    
    /**
     * @notice Remove beneficiary (only before locking)
     * @param beneficiary Beneficiary address
     * @dev Optimized for gas: uses unchecked operations and efficient array swap
     */
    function removeBeneficiary(address beneficiary) external onlyOwner {
        if (allocationsLocked) revert AllocationsAlreadyLocked();
        if (!beneficiaries[beneficiary].isActive) revert NotBeneficiary();
        
        Beneficiary storage b = beneficiaries[beneficiary];
        uint256 allocation = b.totalAllocation;
        
        b.isActive = false;
        totalAllocated -= allocation;
        
        // Remove from list - optimized gas: use unchecked for known safe operations
        uint256 length = beneficiaryList.length;
        for (uint256 i = 0; i < length; ) {
            if (beneficiaryList[i] == beneficiary) {
                // Swap with last element and pop (more gas efficient than shifting)
                beneficiaryList[i] = beneficiaryList[length - 1];
                beneficiaryList.pop();
                break;
            }
            unchecked { i++; } // Gas optimization: unchecked increment
        }
        
        emit BeneficiaryRemoved(beneficiary, allocation);
    }
    
    /**
     * @notice Lock allocations (no more changes allowed)
     */
    function lockAllocations() external onlyOwner {
        if (allocationsLocked) revert AllocationsAlreadyLocked();
        if (!treasuryFunded) revert TreasuryNotFunded();
        if (totalAllocated == 0) revert InvalidAmount();
        
        allocationsLocked = true;
        
        emit AllocationsLocked(block.timestamp);
    }
    
    /**
     * @notice Revoke beneficiary allocation (emergency only)
     * @param beneficiary Beneficiary to revoke
     */
    function revokeAllocation(address beneficiary) external onlyOwner {
        if (!beneficiaries[beneficiary].isActive) revert NotBeneficiary();
        
        Beneficiary storage b = beneficiaries[beneficiary];
        if (b.revoked) revert AllocationAlreadyRevoked();
        
        // Calculate unvested amount
        uint256 vestedAmount = _calculateVestedAmount(beneficiary);
        uint256 claimableNow = vestedAmount - b.claimedAmount;
        
        // If there's claimable amount, allow claim first
        if (claimableNow > 0) {
            b.claimedAmount += claimableNow;
            totalClaimed += claimableNow;
            escrowToken.safeTransfer(beneficiary, claimableNow);
            emit TokensClaimed(beneficiary, claimableNow, _getCurrentMilestone());
        }
        
        uint256 unvestedAmount = b.totalAllocation - b.claimedAmount;
        b.revoked = true;
        
        emit AllocationRevoked(beneficiary, unvestedAmount);
    }
    
    /**
     * @notice Claim tokens for specific beneficiary (anyone can trigger)
     * @param beneficiary Address to claim for
     */
    function claimFor(address beneficiary) external {
        if (!allocationsLocked) revert AllocationsNotLocked();
        if (!beneficiaries[beneficiary].isActive) revert NotBeneficiary();

        Beneficiary storage b = beneficiaries[beneficiary];
        if (b.revoked) revert AllocationAlreadyRevoked();

        uint256 claimable = getClaimableAmount(beneficiary);
        if (claimable == 0) revert NoTokensAvailable();

        uint256 currentMilestone = _getCurrentMilestone();
        b.claimedAmount += claimable;
        totalClaimed += claimable;

        escrowToken.safeTransfer(beneficiary, claimable);

        emit TokensClaimed(beneficiary, claimable, currentMilestone);
    }
    
    // ============ INTERNAL FUNCTIONS ============
    
    /**
     * @notice Calculate vested amount for beneficiary
     */
    function _calculateVestedAmount(address beneficiary) 
        internal 
        view 
        returns (uint256) 
    {
        Beneficiary memory b = beneficiaries[beneficiary];
        
        if (!b.isActive || b.revoked) return 0;
        
        uint256 currentMilestone = _getCurrentMilestone();
        if (currentMilestone == 0) return 0;
        
        // Each milestone unlocks 20% (milestone 1 = 20%, 2 = 40%, etc.)
        uint256 vestedPercentage = currentMilestone * PERCENTAGE_PER_MILESTONE;
        return (b.totalAllocation * vestedPercentage) / BASIS_POINTS;
    }
    
    /**
     * @notice Get current vesting milestone (0-5)
     * @dev Milestone 0 = no vesting, 1 = 20% unlocked, 2 = 40%, etc.
     */
    function _getCurrentMilestone() internal view returns (uint256) {
        if (block.timestamp < firstUnlockTime) return 0;
        
        uint256 timeSinceFirstUnlock = block.timestamp - firstUnlockTime;
        
        if (timeSinceFirstUnlock == 0) return 1;
        
        uint256 milestone = (timeSinceFirstUnlock / VESTING_INTERVAL) + 1;
        
        return milestone > VESTING_MILESTONES ? VESTING_MILESTONES : milestone;
    }
    
    // ============ VIEW FUNCTIONS ============
    
    /**
     * @notice Get claimable amount for beneficiary
     */
    function getClaimableAmount(address beneficiary) 
        public 
        view 
        returns (uint256) 
    {
        Beneficiary memory b = beneficiaries[beneficiary];
        
        if (!b.isActive || b.revoked) return 0;
        
        uint256 vested = _calculateVestedAmount(beneficiary);
        return vested > b.claimedAmount ? vested - b.claimedAmount : 0;
    }

    /**
     * @notice Get beneficiary details
     */
    function getBeneficiaryInfo(address beneficiary)
        external
        view
        returns (
            uint256 totalAllocation,
            uint256 vestedAmount,
            uint256 claimedAmount,
            uint256 claimableAmount,
            uint256 remainingAmount,
            uint256 currentMilestone,
            bool isActive,
            bool revoked
        )
    {
        Beneficiary memory b = beneficiaries[beneficiary];

        // If beneficiary is not active, return zeros for allocation-related fields
        if (!b.isActive) {
            return (0, 0, 0, 0, 0, _getCurrentMilestone(), false, false);
        }

        vestedAmount = _calculateVestedAmount(beneficiary);
        claimableAmount = getClaimableAmount(beneficiary);
        remainingAmount = b.totalAllocation - b.claimedAmount;
        currentMilestone = _getCurrentMilestone();

        return (
            b.totalAllocation,
            vestedAmount,
            b.claimedAmount,
            claimableAmount,
            remainingAmount,
            currentMilestone,
            b.isActive,
            b.revoked
        );
    }

    function getAllBeneficiaries() 
        external 
        view 
        returns (
            address[] memory addresses,
            uint256[] memory allocations,
            uint256[] memory claimed,
            bool[] memory active
        ) 
    {
        uint256 count = beneficiaryList.length;
        addresses = new address[](count);
        allocations = new uint256[](count);
        claimed = new uint256[](count);
        active = new bool[](count);
        
        for (uint256 i = 0; i < count; ) {
            address beneficiary = beneficiaryList[i];
            Beneficiary memory b = beneficiaries[beneficiary];
            
            addresses[i] = beneficiary;
            allocations[i] = b.totalAllocation;
            claimed[i] = b.claimedAmount;
            active[i] = b.isActive && !b.revoked;
            
            unchecked { i++; } // Gas optimization: unchecked increment
        }
        
        return (addresses, allocations, claimed, active);
    }
    
    /**
     * @notice Get vesting schedule info (gas optimized)
     */
    function getVestingSchedule()
        external
        view
        returns (
            uint256 startTime,
            uint256 firstUnlock,
            uint256 currentMilestone,
            uint256 totalMilestones,
            uint256 intervalDays
        )
    {
        return (
            treasuryStartTime,
            firstUnlockTime,
            _getCurrentMilestone(),
            VESTING_MILESTONES,
            VESTING_INTERVAL / 1 days
        );
    }
    
    /**
     * @notice Get next unlock time
     */
    function getNextUnlockTime() external view returns (uint256) {
        uint256 currentMilestone = _getCurrentMilestone();
        
        if (currentMilestone >= VESTING_MILESTONES) return 0;
        if (currentMilestone == 0) return firstUnlockTime;
        
        return firstUnlockTime + (currentMilestone * VESTING_INTERVAL);
    }
    
    /**
     * @notice Get treasury statistics
     */
    function getTreasuryStats() 
        external 
        view 
        returns (
            uint256 totalAlloc,
            uint256 totalClaim,
            uint256 totalRemaining,
            uint256 unallocated,
            uint256 beneficiaryCount,
            bool locked,
            bool funded
        ) 
    {
        uint256 balance = escrowToken.balanceOf(address(this));
        
        return (
            totalAllocated,
            totalClaimed,
            totalAllocated - totalClaimed,
            balance > (totalAllocated - totalClaimed) 
                ? balance - (totalAllocated - totalClaimed) 
                : 0,
            beneficiaryList.length,
            allocationsLocked,
            treasuryFunded
        );
    }
    
    /**
     * @notice Check if beneficiary exists
     */
    function isBeneficiary(address account) external view returns (bool) {
        return beneficiaries[account].isActive;
    }
    
    /**
     * @notice Get time until next unlock
     */
    function getTimeUntilNextUnlock() external view returns (uint256) {
        uint256 currentMilestone = _getCurrentMilestone();
        
        if (currentMilestone >= VESTING_MILESTONES) return 0;
        
        uint256 nextUnlock = currentMilestone == 0 
            ? firstUnlockTime 
            : firstUnlockTime + (currentMilestone * VESTING_INTERVAL);
        
        return nextUnlock > block.timestamp ? nextUnlock - block.timestamp : 0;
    }
    
    /**
     * @notice Get contract info
     */
    function getContractInfo() 
        external 
        view 
        returns (
            address tokenAddress,
            uint256 totalAllocation,
            uint256 lockDuration,
            uint256 vestingInterval,
            uint256 milestones,
            uint256 percentPerMilestone
        ) 
    {
        return (
            address(escrowToken),
            TOTAL_ALLOCATION,
            LOCK_DURATION,
            VESTING_INTERVAL,
            VESTING_MILESTONES,
            PERCENTAGE_PER_MILESTONE
        );
    }
}