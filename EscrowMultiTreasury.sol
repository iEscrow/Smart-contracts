// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title EscrowMultiTreasury
 * @author iEscrow Team
 * @notice Enhanced treasury contract for Team (1%), LP (5%), and Marketing (3.4%) allocations
 * @dev Supports multiple allocation types with different vesting schedules:
 * - Team: 3-year lock + 5-year vesting (20% every 6 months)
 * - LP: No vesting (immediate availability)
 * - Marketing: No lock, 25% every 6 months (2 years)
 * @custom:security-contact security@iescrow.com
 * @custom:whitepaper-ref Implements vesting schedules as specified in project tokenomics
 */

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract EscrowMultiTreasury is Ownable {
    using SafeERC20 for IERC20;

    // ============ ALLOCATION CONSTANTS ============

    /// @notice Total allocation: 9.4% of 100B = 9.4 billion tokens
    uint256 public constant TOTAL_ALLOCATION = 9_400_000_000 * 1e18;

    /// @notice Team allocation: 1% of 100B = 1 billion tokens
    uint256 public constant TEAM_ALLOCATION = 1_000_000_000 * 1e18;

    /// @notice LP allocation: 5% of 100B = 5 billion tokens
    uint256 public constant LP_ALLOCATION = 5_000_000_000 * 1e18;

    /// @notice Marketing allocation: 3.4% of 100B = 3.4 billion tokens
    uint256 public constant MARKETING_ALLOCATION = 3_400_000_000 * 1e18;

    /// @notice Team vesting: Initial lock period (3 years) + 5 milestones (2 years)
    uint256 public constant TEAM_LOCK_DURATION = 3 * 365 days; // 3 years exactly
    uint256 public constant TEAM_VESTING_INTERVAL = 180 days; // 6 months
    uint256 public constant TEAM_VESTING_MILESTONES = 5;
    uint256 public constant TEAM_PERCENTAGE_PER_MILESTONE = 2000; // 20% in basis points

    /// @notice Marketing vesting: 4 milestones (25% every 6 months)
    uint256 public constant MARKETING_VESTING_INTERVAL = 180 days; // 6 months
    uint256 public constant MARKETING_VESTING_MILESTONES = 4;
    uint256 public constant MARKETING_PERCENTAGE_PER_MILESTONE = 2500; // 25% in basis points

    uint256 public constant BASIS_POINTS = 10000;

    /// @notice Structure for essential treasury statistics (optimized for gas)
    struct TreasuryStats {
        uint256 totalAllocated;     // Sum of all allocations (team + lp + marketing)
        uint256 totalClaimed;       // Sum of all claimed tokens
        uint256 contractBalance;    // Current token balance
        uint256 teamBeneficiaryCount;
        bool allocationsLocked;
        bool treasuryFunded;
    }

    /// @notice Structure for vesting schedule info (used for both team and marketing)
    struct VestingSchedule {
        uint256 startTime;
        uint256 firstUnlock;        // Only used for team (0 for marketing)
        uint256 currentMilestone;
        uint256 totalMilestones;
        uint256 intervalDays;
        bool isTeamSchedule;       // True for team, false for marketing
    }

    /// @notice Structure for essential contract info (optimized)
    struct ContractInfo {
        address tokenAddress;
        uint256 totalAllocation;
        uint256 teamAllocation;
        uint256 lpAllocation;
        uint256 marketingAllocation;
        uint256 teamLockDuration;
        uint256 teamVestingInterval;
        uint256 teamMilestones;
        uint256 teamPercentPerMilestone;
        uint256 marketingVestingInterval;
        uint256 marketingMilestones;
        uint256 marketingPercentPerMilestone;
    }

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

    /// @notice Treasury start time (team lock starts from here)
    uint256 public immutable treasuryStartTime;

    /// @notice Team first vesting unlock time (after 3 years)
    uint256 public immutable teamFirstUnlockTime;

    /// @notice Marketing start time (no lock period)
    uint256 public immutable marketingStartTime;

    // ============ TEAM ALLOCATION STATE ============

    /// @notice Team beneficiaries mapping
    mapping(address => Beneficiary) public teamBeneficiaries;

    /// @notice List of all team beneficiary addresses
    address[] public teamBeneficiaryList;

    /// @notice Total allocated to team beneficiaries
    uint256 public teamTotalAllocated;

    /// @notice Total claimed by team beneficiaries
    uint256 public teamTotalClaimed;

    /// @notice Packed boolean flags (bit 0: lpAllocationActive, bit 1: marketingAllocationActive, bit 2: treasuryFunded, bit 3: teamAllocationsLocked)
    uint256 private allocationFlags;

    // ============ LP ALLOCATION STATE ============

    /// @notice LP recipient address
    address public lpRecipient;

    /// @notice LP allocation amount
    uint256 public lpAllocation;

    /// @notice LP tokens claimed
    uint256 public lpClaimed;

    // ============ MARKETING ALLOCATION STATE ============

    /// @notice Marketing recipient address
    address public marketingRecipient;

    /// @notice Marketing allocation amount
    uint256 public marketingAllocation;

    /// @notice Marketing tokens claimed
    uint256 public marketingClaimed;

    /// @notice Marketing last claim milestone
    uint256 public marketingLastClaimMilestone;

    // ============ HARDCODED BENEFICIARY DATA ============

    /// @notice Fixed team beneficiary addresses (28 total)
    address[28] private teamBeneficiaryAddresses;

    /// @notice Fixed team beneficiary allocations (10M or 50M tokens each)
    uint256[28] private teamBeneficiaryAllocations;

    // ============ HELPER FUNCTIONS ============

    /// @notice Check if LP allocation is active
    function lpAllocationActive() public view returns (bool) {
        return (allocationFlags & 1) != 0;
    }

    /// @notice Check if marketing allocation is active
    function marketingAllocationActive() public view returns (bool) {
        return (allocationFlags & 2) != 0;
    }

    /// @notice Check if treasury is funded
    function treasuryFunded() public view returns (bool) {
        return (allocationFlags & 4) != 0;
    }

    /// @notice Check if team allocations are locked
    function teamAllocationsLocked() public view returns (bool) {
        return (allocationFlags & 8) != 0;
    }

    /// @notice Set LP allocation active status
    function _setLpAllocationActive(bool active) internal {
        if (active) {
            allocationFlags |= 1;
        } else {
            allocationFlags &= type(uint256).max - 1;
        }
    }

    /// @notice Set marketing allocation active status
    function _setMarketingAllocationActive(bool active) internal {
        if (active) {
            allocationFlags |= 2;
        } else {
            allocationFlags &= type(uint256).max - 2;
        }
    }

    /// @notice Set treasury funded status
    function _setTreasuryFunded(bool funded) internal {
        if (funded) {
            allocationFlags |= 4;
        } else {
            allocationFlags &= type(uint256).max - 4;
        }
    }

    /// @notice Set team allocations locked status
    function _setTeamAllocationsLocked(bool locked) internal {
        if (locked) {
            allocationFlags |= 8;
        } else {
            allocationFlags &= type(uint256).max - 8;
        }
    }

    /// @notice Emitted when treasury is funded with tokens
    /// @param amount Amount of tokens funded
    /// @param timestamp Time when funding occurred
    event TreasuryFunded(uint256 amount, uint256 timestamp);

    /// @notice Emitted when a new beneficiary is added
    /// @param beneficiary Address of the new beneficiary
    /// @param allocation Token allocation for the beneficiary
    event BeneficiaryAdded(address indexed beneficiary, uint256 allocation);

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

    /// @notice Emitted when LP allocation is set up
    /// @param recipient LP recipient address
    /// @param allocation Token allocation amount
    event LPAllocationSet(address indexed recipient, uint256 allocation);

    /// @notice Emitted when LP tokens are claimed
    /// @param recipient Address that claimed tokens
    /// @param amount Amount of tokens claimed
    event LPClaimed(address indexed recipient, uint256 amount);

    /// @notice Emitted when marketing allocation is set up
    /// @param recipient Marketing recipient address
    /// @param allocation Token allocation amount
    event MarketingAllocationSet(address indexed recipient, uint256 allocation);

    /// @notice Emitted when marketing tokens are claimed
    /// @param recipient Address that claimed tokens
    /// @param amount Amount of tokens claimed
    /// @param milestone Vesting milestone when claimed
    event MarketingClaimed(address indexed recipient, uint256 amount, uint256 milestone);

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

    /// @notice Error thrown when no tokens are available to claim
    error NoTokensAvailable();

    /// @notice Error thrown when allocation has already been revoked
    error AllocationAlreadyRevoked();

    /// @notice Error thrown when balance is insufficient for operation
    error InsufficientBalance();

    // ============ CONSTRUCTOR ============

    /**
     * @notice Initialize treasury contract with all allocation types
     * @param _escrowToken Address of ESCROW token
     */
    constructor(address _escrowToken) Ownable(msg.sender) {
        if (_escrowToken == address(0)) revert InvalidAddress();

        escrowToken = IERC20(_escrowToken);
        treasuryStartTime = block.timestamp;
        teamFirstUnlockTime = block.timestamp + TEAM_LOCK_DURATION;
        marketingStartTime = block.timestamp;

        // Set up LP allocation
        lpRecipient = 0x5f5868Bb7E708aAb9C25c80AEBFA0131735233af;
        lpAllocation = LP_ALLOCATION;
        _setLpAllocationActive(true);
        emit LPAllocationSet(lpRecipient, lpAllocation);

        // Set up Marketing allocation
        marketingRecipient = 0xa315b46cA80982278eD28A3496718B1524Df467b;
        marketingAllocation = MARKETING_ALLOCATION;
        _setMarketingAllocationActive(true);
        marketingLastClaimMilestone = 0;
        emit MarketingAllocationSet(marketingRecipient, marketingAllocation);

        // Initialize team beneficiary data
        teamBeneficiaryAddresses = [
            0x04435410a78192baAfa00c72C659aD3187a2C2cF,
            0x9005132849bC9585A948269D96F23f56e5981A61,
            0x1C5cf9Cb69effeeb31E261BB6519AF7247A97A74,
            0x507541B0Caf529a063E97c6C145E521d3F394264,
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

        teamBeneficiaryAllocations = [
            10_000_000 * 1e18, 10_000_000 * 1e18, 10_000_000 * 1e18, 10_000_000 * 1e18,
            10_000_000 * 1e18, 10_000_000 * 1e18, 10_000_000 * 1e18, 10_000_000 * 1e18,
            10_000_000 * 1e18, 10_000_000 * 1e18, 50_000_000 * 1e18, 50_000_000 * 1e18,
            50_000_000 * 1e18, 50_000_000 * 1e18, 50_000_000 * 1e18, 50_000_000 * 1e18,
            50_000_000 * 1e18, 50_000_000 * 1e18, 50_000_000 * 1e18, 50_000_000 * 1e18,
            50_000_000 * 1e18, 50_000_000 * 1e18, 50_000_000 * 1e18, 50_000_000 * 1e18,
            50_000_000 * 1e18, 50_000_000 * 1e18, 50_000_000 * 1e18, 50_000_000 * 1e18
        ];

        // Initialize team beneficiaries from hardcoded constants
        for (uint256 i = 0; i < teamBeneficiaryAddresses.length; i++) {
            teamBeneficiaries[teamBeneficiaryAddresses[i]] = Beneficiary({
                totalAllocation: teamBeneficiaryAllocations[i],
                claimedAmount: 0,
                isActive: true,
                revoked: false
            });
            teamBeneficiaryList.push(teamBeneficiaryAddresses[i]);
            teamTotalAllocated += teamBeneficiaryAllocations[i];
        }
    }

    /**
     * @notice Initialize contract with test beneficiaries (only for testing)
     * @param beneficiaries Array of beneficiary addresses
     * @param allocations Array of token allocations
     */
    function initializeTestBeneficiaries(address[] calldata beneficiaries, uint256[] calldata allocations)
        external
        onlyOwner
    {
        require(!treasuryFunded(), "Treasury already funded");
        require(beneficiaries.length == allocations.length, "Array length mismatch");
        require(beneficiaries.length <= 50, "Too many beneficiaries");

        for (uint256 i = 0; i < beneficiaries.length; i++) {
            require(beneficiaries[i] != address(0), "Invalid address");
            require(allocations[i] > 0, "Invalid allocation");
            require(!teamBeneficiaries[beneficiaries[i]].isActive, "Already allocated");

            teamBeneficiaries[beneficiaries[i]] = Beneficiary({
                totalAllocation: allocations[i],
                claimedAmount: 0,
                isActive: true,
                revoked: false
            });

            teamBeneficiaryList.push(beneficiaries[i]);
            teamTotalAllocated += allocations[i];
        }
    }

    // ============ ADMIN FUNCTIONS ============

    /**
     * @notice Fund treasury with 9.4 billion ESCROW tokens (one-time only)
     */
    function fundTreasury() external {
        if (treasuryFunded()) revert TreasuryAlreadyFunded();

        uint256 balance = escrowToken.balanceOf(msg.sender);
        if (balance < TOTAL_ALLOCATION) revert InsufficientBalance();

        escrowToken.safeTransferFrom(msg.sender, address(this), TOTAL_ALLOCATION);
        _setTreasuryFunded(true);

        emit TreasuryFunded(TOTAL_ALLOCATION, block.timestamp);
    }

    /**
     * @notice Add new team beneficiary (only before locking)
     * @param beneficiary Beneficiary address
     * @param allocation Amount of tokens to allocate
     */
    function addBeneficiary(address beneficiary, uint256 allocation)
        external
        onlyOwner
    {
        if (teamAllocationsLocked()) revert AllocationsAlreadyLocked();
        if (!treasuryFunded()) revert TreasuryNotFunded();
        if (beneficiary == address(0)) revert InvalidAddress();
        if (allocation == 0) revert InvalidAmount();
        if (teamBeneficiaries[beneficiary].isActive) revert AlreadyAllocated();

        // Check team allocation doesn't exceed team limit
        if (teamTotalAllocated + allocation > TEAM_ALLOCATION) {
            revert ExceedsTotalAllocation();
        }

        teamBeneficiaries[beneficiary] = Beneficiary({
            totalAllocation: allocation,
            claimedAmount: 0,
            isActive: true,
            revoked: false
        });

        teamBeneficiaryList.push(beneficiary);
        teamTotalAllocated += allocation;

        emit BeneficiaryAdded(beneficiary, allocation);
    }


    /**
     * @notice Remove team beneficiary (only before locking)
     * @param beneficiary Beneficiary address
     */
    function removeBeneficiary(address beneficiary) external onlyOwner {
        if (teamAllocationsLocked()) revert AllocationsAlreadyLocked();
        if (!teamBeneficiaries[beneficiary].isActive) revert NotBeneficiary();

        Beneficiary storage b = teamBeneficiaries[beneficiary];
        uint256 allocation = b.totalAllocation;

        b.isActive = false;
        teamTotalAllocated -= allocation;

        // Remove from list
        uint256 length = teamBeneficiaryList.length;
        for (uint256 i = 0; i < length; ) {
            if (teamBeneficiaryList[i] == beneficiary) {
                teamBeneficiaryList[i] = teamBeneficiaryList[length - 1];
                teamBeneficiaryList.pop();
                break;
            }
            unchecked { i++; }
        }

        emit BeneficiaryRemoved(beneficiary, allocation);
    }

    /**
     * @notice Lock team allocations (no more changes allowed)
     */
    function lockAllocations() external onlyOwner {
        if (teamAllocationsLocked()) revert AllocationsAlreadyLocked();
        if (!treasuryFunded()) revert TreasuryNotFunded();
        if (teamTotalAllocated == 0) revert InvalidAmount();

        _setTeamAllocationsLocked(true);

        emit AllocationsLocked(block.timestamp);
    }

    /**
     * @notice Revoke team beneficiary allocation (emergency only)
     * @param beneficiary Beneficiary to revoke
     */
    function revokeAllocation(address beneficiary) external onlyOwner {
        if (!teamBeneficiaries[beneficiary].isActive) revert NotBeneficiary();

        Beneficiary storage b = teamBeneficiaries[beneficiary];
        if (b.revoked) revert AllocationAlreadyRevoked();

        // Calculate unvested amount
        uint256 vestedAmount = _calculateTeamVestedAmount(beneficiary);
        uint256 claimableNow = vestedAmount - b.claimedAmount;

        // If there's claimable amount, allow claim first
        if (claimableNow > 0) {
            b.claimedAmount += claimableNow;
            teamTotalClaimed += claimableNow;
            escrowToken.safeTransfer(beneficiary, claimableNow);
            emit TokensClaimed(beneficiary, claimableNow, _getTeamCurrentMilestone());
        }

        uint256 unvestedAmount = b.totalAllocation - b.claimedAmount;
        b.revoked = true;

        emit AllocationRevoked(beneficiary, unvestedAmount);
    }

    /**
     * @notice Claim tokens for team beneficiary (anyone can trigger)
     * @param beneficiary Address to claim for
     */
    function claimFor(address beneficiary) external {
        if (!teamAllocationsLocked()) revert AllocationsNotLocked();
        if (!teamBeneficiaries[beneficiary].isActive) revert NotBeneficiary();

        Beneficiary storage b = teamBeneficiaries[beneficiary];
        if (b.revoked) revert AllocationAlreadyRevoked();

        uint256 claimable = getTeamClaimableAmount(beneficiary);
        if (claimable == 0) revert NoTokensAvailable();

        uint256 currentMilestone = _getTeamCurrentMilestone();
        b.claimedAmount += claimable;
        teamTotalClaimed += claimable;

        escrowToken.safeTransfer(beneficiary, claimable);

        emit TokensClaimed(beneficiary, claimable, currentMilestone);
    }

    // ============ LP CLAIMING FUNCTIONS ============

    /**
     * @notice Claim LP tokens (anyone can trigger)
     * @dev LP tokens have no vesting - can be claimed immediately after funding
     */
    function claimLP() external {
        if (!treasuryFunded()) revert TreasuryNotFunded();
        if (!lpAllocationActive()) revert InvalidAmount();
        if (lpClaimed >= lpAllocation) revert NoTokensAvailable();

        uint256 claimableAmount = lpAllocation - lpClaimed;
        lpClaimed += claimableAmount;

        escrowToken.safeTransfer(lpRecipient, claimableAmount);

        emit LPClaimed(lpRecipient, claimableAmount);
    }

    // ============ MARKETING CLAIMING FUNCTIONS ============

    /**
     * @notice Claim marketing tokens (anyone can trigger)
     * @dev Marketing tokens vest 25% every 6 months for 2 years (4 milestones total)
     */
    function claimMarketing() external {
        if (!treasuryFunded()) revert TreasuryNotFunded();
        if (!marketingAllocationActive()) revert InvalidAmount();

        uint256 currentMilestone = _getMarketingCurrentMilestone();
        if (currentMilestone <= marketingLastClaimMilestone) revert NoTokensAvailable();

        uint256 milestonesToClaim = currentMilestone - marketingLastClaimMilestone;
        uint256 claimableAmount = (marketingAllocation * milestonesToClaim * MARKETING_PERCENTAGE_PER_MILESTONE) / BASIS_POINTS;

        if (marketingClaimed + claimableAmount > marketingAllocation) {
            claimableAmount = marketingAllocation - marketingClaimed;
        }

        if (claimableAmount == 0) revert NoTokensAvailable();

        marketingClaimed += claimableAmount;
        marketingLastClaimMilestone = currentMilestone;

        escrowToken.safeTransfer(marketingRecipient, claimableAmount);

        emit MarketingClaimed(marketingRecipient, claimableAmount, currentMilestone);
    }

    // ============ VIEW FUNCTIONS ============

    /**
     * @notice Get team claimable amount for beneficiary
     */
    function getTeamClaimableAmount(address beneficiary)
        public
        view
        returns (uint256)
    {
        Beneficiary memory b = teamBeneficiaries[beneficiary];

        if (!b.isActive || b.revoked) return 0;

        uint256 vested = _calculateTeamVestedAmount(beneficiary);
        return vested > b.claimedAmount ? vested - b.claimedAmount : 0;
    }

    /**
     * @notice Get team beneficiary details
     */
    function getTeamBeneficiaryInfo(address beneficiary)
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
        Beneficiary memory b = teamBeneficiaries[beneficiary];

        // If beneficiary is not active, return zeros for allocation-related fields
        if (!b.isActive) {
            return (0, 0, 0, 0, 0, _getTeamCurrentMilestone(), false, false);
        }

        vestedAmount = _calculateTeamVestedAmount(beneficiary);
        claimableAmount = getTeamClaimableAmount(beneficiary);
        remainingAmount = b.totalAllocation - b.claimedAmount;
        currentMilestone = _getTeamCurrentMilestone();

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
     * @notice Get all team beneficiaries
     */
    function getAllTeamBeneficiaries()
        external
        view
        returns (
            address[] memory addresses,
            uint256[] memory allocations,
            uint256[] memory claimed,
            bool[] memory active
        )
    {
        uint256 count = teamBeneficiaryList.length;
        addresses = new address[](count);
        allocations = new uint256[](count);
        claimed = new uint256[](count);
        active = new bool[](count);

        for (uint256 i = 0; i < count; ) {
            address beneficiary = teamBeneficiaryList[i];
            Beneficiary memory b = teamBeneficiaries[beneficiary];

            addresses[i] = beneficiary;
            allocations[i] = b.totalAllocation;
            claimed[i] = b.claimedAmount;
            active[i] = b.isActive && !b.revoked;

            unchecked { i++; }
        }

        return (addresses, allocations, claimed, active);
    }

    /**
     * @notice Get marketing claimable amount
     */
    function getMarketingClaimableAmount()
        external
        view
        returns (uint256)
    {
        if (!marketingAllocationActive()) return 0;

        uint256 currentMilestone = _getMarketingCurrentMilestone();
        if (currentMilestone <= marketingLastClaimMilestone) return 0;

        uint256 milestonesToClaim = currentMilestone - marketingLastClaimMilestone;
        uint256 claimableAmount = (marketingAllocation * milestonesToClaim * MARKETING_PERCENTAGE_PER_MILESTONE) / BASIS_POINTS;

        if (marketingClaimed + claimableAmount > marketingAllocation) {
            claimableAmount = marketingAllocation - marketingClaimed;
        }

        return claimableAmount;
    }

    /**
     * @notice Get marketing current milestone
     */
    function getMarketingCurrentMilestone() external view returns (uint256) {
        return _getMarketingCurrentMilestone();
    }

    /**
     * @notice Get essential treasury statistics
     */
    function getTreasuryStats() external view returns (TreasuryStats memory) {
        uint256 balance = escrowToken.balanceOf(address(this));
        uint256 totalAllocated = teamTotalAllocated + lpAllocation + marketingAllocation;
        uint256 totalClaimed = teamTotalClaimed + lpClaimed + marketingClaimed;

        return TreasuryStats({
            totalAllocated: totalAllocated,
            totalClaimed: totalClaimed,
            contractBalance: balance,
            teamBeneficiaryCount: teamBeneficiaryList.length,
            allocationsLocked: teamAllocationsLocked(),
            treasuryFunded: treasuryFunded()
        });
    }

    /**
     * @notice Check if address is a team beneficiary
     */
    function isTeamBeneficiary(address account) external view returns (bool) {
        return teamBeneficiaries[account].isActive;
    }

    /**
     * @notice Get team vesting schedule info
     */
    function getTeamVestingSchedule() external view returns (VestingSchedule memory) {
        return VestingSchedule({
            startTime: treasuryStartTime,
            firstUnlock: teamFirstUnlockTime,
            currentMilestone: _getTeamCurrentMilestone(),
            totalMilestones: TEAM_VESTING_MILESTONES,
            intervalDays: TEAM_VESTING_INTERVAL / 1 days,
            isTeamSchedule: true
        });
    }

    /**
     * @notice Get marketing vesting schedule info
     */
    function getMarketingVestingSchedule() external view returns (VestingSchedule memory) {
        return VestingSchedule({
            startTime: marketingStartTime,
            firstUnlock: 0, // Marketing has no lock period
            currentMilestone: _getMarketingCurrentMilestone(),
            totalMilestones: MARKETING_VESTING_MILESTONES,
            intervalDays: MARKETING_VESTING_INTERVAL / 1 days,
            isTeamSchedule: false
        });
    }

    /**
     * @notice Get next team unlock time
     */
    function getNextTeamUnlockTime() external view returns (uint256) {
        uint256 currentMilestone = _getTeamCurrentMilestone();

        if (currentMilestone >= TEAM_VESTING_MILESTONES) return 0;
        if (currentMilestone == 0) return teamFirstUnlockTime;

        return teamFirstUnlockTime + (currentMilestone * TEAM_VESTING_INTERVAL);
    }

    /**
     * @notice Get time until next marketing unlock
     */
    function getTimeUntilNextMarketingUnlock() external view returns (uint256) {
        uint256 currentMilestone = _getMarketingCurrentMilestone();

        if (currentMilestone >= MARKETING_VESTING_MILESTONES) return 0;

        // Calculate when the next milestone becomes available
        uint256 nextMilestoneTime = marketingStartTime + (currentMilestone * MARKETING_VESTING_INTERVAL);

        return nextMilestoneTime;
    }

    /**
     * @notice Get comprehensive contract info
     */
    function getContractInfo() external view returns (ContractInfo memory) {
        return ContractInfo({
            tokenAddress: address(escrowToken),
            totalAllocation: TOTAL_ALLOCATION,
            teamAllocation: TEAM_ALLOCATION,
            lpAllocation: LP_ALLOCATION,
            marketingAllocation: MARKETING_ALLOCATION,
            teamLockDuration: TEAM_LOCK_DURATION,
            teamVestingInterval: TEAM_VESTING_INTERVAL,
            teamMilestones: TEAM_VESTING_MILESTONES,
            teamPercentPerMilestone: TEAM_PERCENTAGE_PER_MILESTONE,
            marketingVestingInterval: MARKETING_VESTING_INTERVAL,
            marketingMilestones: MARKETING_VESTING_MILESTONES,
            marketingPercentPerMilestone: MARKETING_PERCENTAGE_PER_MILESTONE
        });
    }

    // ============ INTERNAL FUNCTIONS ============

    /**
     * @notice Calculate vested amount for team beneficiary
     */
    function _calculateTeamVestedAmount(address beneficiary)
        internal
        view
        returns (uint256)
    {
        Beneficiary memory b = teamBeneficiaries[beneficiary];

        if (!b.isActive || b.revoked) return 0;

        uint256 currentMilestone = _getTeamCurrentMilestone();
        if (currentMilestone == 0) return 0;

        // Each milestone unlocks 20% (milestone 1 = 20%, 2 = 40%, etc.)
        uint256 vestedPercentage = currentMilestone * TEAM_PERCENTAGE_PER_MILESTONE;
        return (b.totalAllocation * vestedPercentage) / BASIS_POINTS;
    }

    /**
     * @notice Get current team vesting milestone (0-5)
     * @dev Milestone 0 = no vesting, 1 = 20% unlocked, 2 = 40%, etc.
     */
    function _getTeamCurrentMilestone() internal view returns (uint256) {
        if (block.timestamp < teamFirstUnlockTime) return 0;

        // Start at milestone 1 immediately when lock period ends
        uint256 timeSinceFirstUnlock = block.timestamp - teamFirstUnlockTime;

        // If we're exactly at the unlock time or just after, return milestone 1
        if (timeSinceFirstUnlock < TEAM_VESTING_INTERVAL) return 1;

        // For subsequent milestones
        uint256 milestone = (timeSinceFirstUnlock / TEAM_VESTING_INTERVAL) + 1;

        return milestone > TEAM_VESTING_MILESTONES ? TEAM_VESTING_MILESTONES : milestone;
    }

    /**
     * @notice Get current marketing milestone (0-4)
     * @dev Milestone 0 = no tokens, 1 = 25% unlocked, 2 = 50%, etc.
     */
    function _getMarketingCurrentMilestone() internal view returns (uint256) {
        if (block.timestamp < marketingStartTime) return 0;

        // Start at milestone 1 immediately when marketing starts
        uint256 timeSinceStart = block.timestamp - marketingStartTime;

        // If we're exactly at the start time or just after, return milestone 1
        if (timeSinceStart < MARKETING_VESTING_INTERVAL) return 1;

        // For subsequent milestones
        uint256 milestone = (timeSinceStart / MARKETING_VESTING_INTERVAL) + 1;

        return milestone > MARKETING_VESTING_MILESTONES ? MARKETING_VESTING_MILESTONES : milestone;
    }
}
