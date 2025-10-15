// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title EscrowTeamTreasury
 * @author iEscrow Team
 * @notice Treasury contract for Founders, Team & Advisors (1% allocation)
 * @dev Flexible vesting with 3-year lock + 2-year release (20% every 6 months)
 * @custom:security-contact security@iescrow.com
 */

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract EscrowTeamTreasury is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    
    // ============ CONSTANTS ============
    
    /// @notice Total allocation: 1% of 100B = 1 billion tokens
    uint256 public constant TOTAL_ALLOCATION = 1_000_000_000 * 1e18;
    
    /// @notice Initial lock period: 3 years
    uint256 public constant LOCK_DURATION = 1095 days; // 3 years
    
    /// @notice Vesting interval: 6 months
    uint256 public constant VESTING_INTERVAL = 180 days;
    
    /// @notice Number of vesting milestones
    uint256 public constant VESTING_MILESTONES = 5;
    
    /// @notice Percentage per milestone (20%)
    uint256 public constant PERCENTAGE_PER_MILESTONE = 2000; // 20% in basis points
    uint256 public constant BASIS_POINTS = 10000;
    
    // ============ STRUCTS ============
    
    struct Beneficiary {
        uint256 totalAllocation;      // Total tokens allocated
        uint256 claimedAmount;        // Amount already claimed
        uint256 lastClaimMilestone;   // Last milestone claimed (0-4)
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
    
    // ============ EVENTS ============
    
    event TreasuryFunded(uint256 amount, uint256 timestamp);
    event BeneficiaryAdded(address indexed beneficiary, uint256 allocation);
    event BeneficiaryUpdated(address indexed beneficiary, uint256 newAllocation);
    event BeneficiaryRemoved(address indexed beneficiary, uint256 allocation);
    event TokensClaimed(address indexed beneficiary, uint256 amount, uint256 milestone);
    event AllocationRevoked(address indexed beneficiary, uint256 unvestedAmount);
    event AllocationsLocked(uint256 timestamp);
    event EmergencyWithdraw(address indexed token, uint256 amount);
    
    // ============ ERRORS ============
    
    error InvalidAddress();
    error InvalidAmount();
    error ExceedsTotalAllocation();
    error AlreadyAllocated();
    error NotBeneficiary();
    error AllocationsAlreadyLocked();
    error AllocationsNotLocked();
    error TreasuryNotFunded();
    error TreasuryAlreadyFunded();
    error LockPeriodNotEnded();
    error NoTokensAvailable();
    error AllocationRevoked();
    error InvalidMilestone();
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
        
        emit TreasuryFunded(0, block.timestamp); // Deployment event
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
            lastClaimMilestone: 0,
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
     */
    function removeBeneficiary(address beneficiary) external onlyOwner {
        if (allocationsLocked) revert AllocationsAlreadyLocked();
        if (!beneficiaries[beneficiary].isActive) revert NotBeneficiary();
        
        Beneficiary storage b = beneficiaries[beneficiary];
        uint256 allocation = b.totalAllocation;
        
        b.isActive = false;
        totalAllocated -= allocation;
        
        // Remove from list
        for (uint256 i = 0; i < beneficiaryList.length; i++) {
            if (beneficiaryList[i] == beneficiary) {
                beneficiaryList[i] = beneficiaryList[beneficiaryList.length - 1];
                beneficiaryList.pop();
                break;
            }
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
        if (b.revoked) revert AllocationRevoked();
        
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
     * @notice Pause contract (emergency)
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @notice Unpause contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /**
     * @notice Emergency withdraw (only unallocated tokens)
     */
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = escrowToken.balanceOf(address(this));
        uint256 locked = totalAllocated - totalClaimed;
        
        if (balance <= locked) revert InsufficientBalance();
        
        uint256 withdrawable = balance - locked;
        escrowToken.safeTransfer(owner(), withdrawable);
        
        emit EmergencyWithdraw(address(escrowToken), withdrawable);
    }
    
    // ============ BENEFICIARY FUNCTIONS ============
    
    /**
     * @notice Claim vested tokens
     */
    function claimTokens() external nonReentrant whenNotPaused {
        if (!allocationsLocked) revert AllocationsNotLocked();
        if (!beneficiaries[msg.sender].isActive) revert NotBeneficiary();
        
        Beneficiary storage b = beneficiaries[msg.sender];
        if (b.revoked) revert AllocationRevoked();
        
        uint256 claimable = getClaimableAmount(msg.sender);
        if (claimable == 0) revert NoTokensAvailable();
        
        uint256 currentMilestone = _getCurrentMilestone();
        b.claimedAmount += claimable;
        b.lastClaimMilestone = currentMilestone;
        totalClaimed += claimable;
        
        escrowToken.safeTransfer(msg.sender, claimable);
        
        emit TokensClaimed(msg.sender, claimable, currentMilestone);
    }
    
    /**
     * @notice Claim tokens for specific beneficiary (anyone can trigger)
     * @param beneficiary Address to claim for
     */
    function claimFor(address beneficiary) external nonReentrant whenNotPaused {
        if (!allocationsLocked) revert AllocationsNotLocked();
        if (!beneficiaries[beneficiary].isActive) revert NotBeneficiary();
        
        Beneficiary storage b = beneficiaries[beneficiary];
        if (b.revoked) revert AllocationRevoked();
        
        uint256 claimable = getClaimableAmount(beneficiary);
        if (claimable == 0) revert NoTokensAvailable();
        
        uint256 currentMilestone = _getCurrentMilestone();
        b.claimedAmount += claimable;
        b.lastClaimMilestone = currentMilestone;
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
        if (block.timestamp < firstUnlockTime) return 0;
        
        uint256 currentMilestone = _getCurrentMilestone();
        if (currentMilestone == 0) return 0;
        
        // Each milestone unlocks 20%
        uint256 vestedPercentage = currentMilestone * PERCENTAGE_PER_MILESTONE;
        return (b.totalAllocation * vestedPercentage) / BASIS_POINTS;
    }
    
    /**
     * @notice Get current vesting milestone (0-5)
     */
    function _getCurrentMilestone() internal view returns (uint256) {
        if (block.timestamp < firstUnlockTime) return 0;
        
        uint256 timeSinceFirstUnlock = block.timestamp - firstUnlockTime;
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
    
    /**
     * @notice Get all beneficiaries
     */
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
        
        for (uint256 i = 0; i < count; i++) {
            address beneficiary = beneficiaryList[i];
            Beneficiary memory b = beneficiaries[beneficiary];
            
            addresses[i] = beneficiary;
            allocations[i] = b.totalAllocation;
            claimed[i] = b.claimedAmount;
            active[i] = b.isActive && !b.revoked;
        }
        
        return (addresses, allocations, claimed, active);
    }
    
    /**
     * @notice Get vesting schedule info
     */
    function getVestingSchedule() 
        external 
        view 
        returns (
            uint256 startTime,
            uint256 firstUnlock,
            uint256 currentMilestone,
            uint256 totalMilestones,
            uint256 intervalDays,
            uint256[] memory unlockTimes
        ) 
    {
        unlockTimes = new uint256[](VESTING_MILESTONES);
        
        for (uint256 i = 0; i < VESTING_MILESTONES; i++) {
            unlockTimes[i] = firstUnlockTime + (i * VESTING_INTERVAL);
        }
        
        return (
            treasuryStartTime,
            firstUnlockTime,
            _getCurrentMilestone(),
            VESTING_MILESTONES,
            VESTING_INTERVAL / 1 days,
            unlockTimes
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