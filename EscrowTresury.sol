// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title EscrowMultiTreasury
 * @author iEscrow Team
 * @notice Vesting treasury for Team (1%), LP (5%), and Marketing (3.4%) allocations
 * @dev Team: 3yr cliff + 5 milestones (20% per 6mo) | LP: instant | Marketing: 4 milestones (25% per 6mo)
 * 
 * Security features:
 * - ReentrancyGuard on all claim functions
 * - Pausable for emergency stops
 * - SafeERC20 for token transfers
 * - Immutable token, LP, and marketing addresses
 * - Single funding mechanism
 * - Lock mechanism to prevent allocation changes post-deployment
 */
contract EscrowMultiTreasury is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ════════════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ════════════════════════════════════════════════════════════════════════════════

    uint256 private constant BP = 10_000;
    uint256 private constant TOTAL_ALLOC = 9_400_000_000 * 1e18;
    uint256 private constant TEAM_ALLOC = 1_000_000_000 * 1e18;
    uint256 private constant LP_ALLOC = 5_000_000_000 * 1e18;
    uint256 private constant MKT_ALLOC = 3_400_000_000 * 1e18;

    uint256 private constant TEAM_CLIFF = 3 * 365 days;
    uint256 private constant TEAM_INTERVAL = 180 days;
    uint256 private constant TEAM_MILESTONES = 5;
    uint256 private constant TEAM_PCT = 2000; // 20%

    uint256 private constant MKT_INTERVAL = 180 days;
    uint256 private constant MKT_MILESTONES = 4;
    uint256 private constant MKT_PCT = 2500; // 25%

    // ════════════════════════════════════════════════════════════════════════════════
    // STATE
    // ════════════════════════════════════════════════════════════════════════════════

    IERC20 public immutable token;
    uint256 public immutable deployTime;
    address public immutable lpRecipient;
    address public immutable mktRecipient;

    // Packed flags: bit0=funded | bit1=locked | bit2=lpClaimed
    uint8 private _flags;

    // Team vesting
    mapping(address => uint256) public teamAlloc;
    mapping(address => uint256) public teamClaimed;
    address[] private _teamList;
    uint256 public teamTotal;

    // Marketing vesting
    uint256 public mktClaimed;
    uint8 public mktLastMilestone;

    // ════════════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ════════════════════════════════════════════════════════════════════════════════

    event Funded(uint256 amount);
    event TeamSet(address indexed beneficiary, uint256 amount);
    event TeamRemoved(address indexed beneficiary, uint256 amount);
    event Locked();
    event Claimed(address indexed recipient, uint256 amount, string category);

    // ════════════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ════════════════════════════════════════════════════════════════════════════════

    error AlreadyFunded();
    error NotFunded();
    error AlreadyLocked();
    error NotLocked();
    error ZeroAddress();
    error ZeroAmount();
    error ExceedsLimit();
    error AlreadyExists();
    error NotFound();
    error NoTokensAvailable();
    error Unauthorized();
    error ArrayLengthMismatch();

    // ════════════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ════════════════════════════════════════════════════════════════════════════════

    constructor(address _token, address _lp, address _mkt) Ownable(msg.sender) {
        if (_token == address(0) || _lp == address(0) || _mkt == address(0)) {
            revert ZeroAddress();
        }
        token = IERC20(_token);
        lpRecipient = _lp;
        mktRecipient = _mkt;
        deployTime = block.timestamp;
    }

    // ════════════════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ════════════════════════════════════════════════════════════════════════════════

    /// @notice Fund treasury with tokens (one-time operation)
    function fund() external onlyOwner {
        if (_isFunded()) revert AlreadyFunded();
        token.safeTransferFrom(msg.sender, address(this), TOTAL_ALLOC);
        _flags |= 0x01;
        emit Funded(TOTAL_ALLOC);
    }

    /// @notice Set individual team beneficiary allocation
    function setTeam(address beneficiary, uint256 amount) external onlyOwner {
        if (!_isFunded()) revert NotFunded();
        if (_isLocked()) revert AlreadyLocked();
        if (beneficiary == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (teamAlloc[beneficiary] > 0) revert AlreadyExists();
        if (teamTotal + amount > TEAM_ALLOC) revert ExceedsLimit();

        teamAlloc[beneficiary] = amount;
        _teamList.push(beneficiary);
        teamTotal += amount;
        emit TeamSet(beneficiary, amount);
    }

    /// @notice Batch set team beneficiaries (gas efficient)
    function batchSetTeam(address[] calldata beneficiaries, uint256[] calldata amounts) external onlyOwner {
        if (!_isFunded()) revert NotFunded();
        if (_isLocked()) revert AlreadyLocked();
        
        uint256 len = beneficiaries.length;
        if (len != amounts.length || len == 0) revert ArrayLengthMismatch();

        uint256 total;
        for (uint256 i; i < len;) {
            if (beneficiaries[i] == address(0)) revert ZeroAddress();
            if (amounts[i] == 0) revert ZeroAmount();
            if (teamAlloc[beneficiaries[i]] > 0) revert AlreadyExists();
            total += amounts[i];
            unchecked { ++i; }
        }

        if (teamTotal + total > TEAM_ALLOC) revert ExceedsLimit();

        for (uint256 i; i < len;) {
            teamAlloc[beneficiaries[i]] = amounts[i];
            _teamList.push(beneficiaries[i]);
            emit TeamSet(beneficiaries[i], amounts[i]);
            unchecked { ++i; }
        }
        teamTotal += total;
    }

    /// @notice Remove team beneficiary (only before lock)
    function removeTeam(address beneficiary) external onlyOwner {
        if (_isLocked()) revert AlreadyLocked();
        
        uint256 amount = teamAlloc[beneficiary];
        if (amount == 0) revert NotFound();

        delete teamAlloc[beneficiary];
        teamTotal -= amount;

        // Remove from array using swap and pop
        uint256 len = _teamList.length;
        for (uint256 i; i < len;) {
            if (_teamList[i] == beneficiary) {
                _teamList[i] = _teamList[len - 1];
                _teamList.pop();
                break;
            }
            unchecked { ++i; }
        }
        emit TeamRemoved(beneficiary, amount);
    }

    /// @notice Lock allocations (irreversible)
    function lock() external onlyOwner {
        if (!_isFunded()) revert NotFunded();
        if (_isLocked()) revert AlreadyLocked();
        if (teamTotal == 0) revert ZeroAmount();
        _flags |= 0x02;
        emit Locked();
    }

    /// @notice Emergency pause all claims
    function pause() external onlyOwner { 
        _pause(); 
    }

    /// @notice Resume claims
    function unpause() external onlyOwner { 
        _unpause(); 
    }

    // ════════════════════════════════════════════════════════════════════════════════
    // CLAIM FUNCTIONS
    // ════════════════════════════════════════════════════════════════════════════════

    /// @notice Claim vested team tokens (beneficiary only)
    function claimTeam() external nonReentrant whenNotPaused {
        if (!_isFunded()) revert NotFunded();
        if (!_isLocked()) revert NotLocked();
        
        uint256 allocated = teamAlloc[msg.sender];
        if (allocated == 0) revert NotFound();

        uint256 claimable = _calculateTeamClaimable(msg.sender);
        if (claimable == 0) revert NoTokensAvailable();

        teamClaimed[msg.sender] += claimable;
        token.safeTransfer(msg.sender, claimable);
        emit Claimed(msg.sender, claimable, "Team");
    }

    /// @notice Claim LP tokens (instant, one-time)
    function claimLP() external nonReentrant whenNotPaused {
        if (!_isFunded()) revert NotFunded();
        if (msg.sender != lpRecipient) revert Unauthorized();
        if (_flags & 0x04 != 0) revert NoTokensAvailable();

        _flags |= 0x04;
        token.safeTransfer(lpRecipient, LP_ALLOC);
        emit Claimed(lpRecipient, LP_ALLOC, "LP");
    }

    /// @notice Claim vested marketing tokens
    function claimMkt() external nonReentrant whenNotPaused {
        if (!_isFunded()) revert NotFunded();
        if (msg.sender != mktRecipient) revert Unauthorized();

        uint8 currentMilestone = _calculateMktMilestone();
        if (currentMilestone <= mktLastMilestone) revert NoTokensAvailable();

        uint256 claimable = ((currentMilestone - mktLastMilestone) * MKT_ALLOC * MKT_PCT) / BP;
        if (mktClaimed + claimable > MKT_ALLOC) {
            claimable = MKT_ALLOC - mktClaimed;
        }
        if (claimable == 0) revert NoTokensAvailable();

        mktClaimed += claimable;
        mktLastMilestone = currentMilestone;
        token.safeTransfer(mktRecipient, claimable);
        emit Claimed(mktRecipient, claimable, "Marketing");
    }

    // ════════════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ════════════════════════════════════════════════════════════════════════════════

    /// @notice Get claimable amount for team member
    function teamClaimable(address beneficiary) external view returns (uint256) {
        return _calculateTeamClaimable(beneficiary);
    }

    /// @notice Get comprehensive team member info
    function teamInfo(address beneficiary) external view returns (
        uint256 allocated,
        uint256 vested,
        uint256 claimed,
        uint256 claimable,
        uint8 milestone
    ) {
        allocated = teamAlloc[beneficiary];
        if (allocated == 0) return (0, 0, 0, 0, 0);
        
        claimed = teamClaimed[beneficiary];
        vested = _calculateTeamVested(beneficiary);
        claimable = vested > claimed ? vested - claimed : 0;
        milestone = _calculateTeamMilestone();
    }

    /// @notice Get claimable marketing tokens
    function mktClaimable() external view returns (uint256) {
        uint8 current = _calculateMktMilestone();
        if (current <= mktLastMilestone) return 0;
        
        uint256 amount = ((current - mktLastMilestone) * MKT_ALLOC * MKT_PCT) / BP;
        return mktClaimed + amount > MKT_ALLOC ? MKT_ALLOC - mktClaimed : amount;
    }

    /// @notice Get treasury statistics
    function stats() external view returns (
        uint256 balance,
        uint256 teamCount,
        bool funded,
        bool locked,
        bool lpClaimed
    ) {
        return (
            token.balanceOf(address(this)),
            _teamList.length,
            _isFunded(),
            _isLocked(),
            _flags & 0x04 != 0
        );
    }

    /// @notice Get all team beneficiaries and their allocations
    function allTeam() external view returns (
        address[] memory beneficiaries,
        uint256[] memory allocations,
        uint256[] memory claimed
    ) {
        uint256 len = _teamList.length;
        beneficiaries = new address[](len);
        allocations = new uint256[](len);
        claimed = new uint256[](len);

        for (uint256 i; i < len;) {
            beneficiaries[i] = _teamList[i];
            allocations[i] = teamAlloc[_teamList[i]];
            claimed[i] = teamClaimed[_teamList[i]];
            unchecked { ++i; }
        }
    }

    /// @notice Get next unlock timestamps
    function nextUnlock() external view returns (uint256 teamNext, uint256 mktNext) {
        uint8 teamMilestone = _calculateTeamMilestone();
        
        if (teamMilestone == 0) {
            teamNext = deployTime + TEAM_CLIFF;
        } else if (teamMilestone < TEAM_MILESTONES) {
            teamNext = deployTime + TEAM_CLIFF + (teamMilestone * TEAM_INTERVAL);
        }

        uint8 mktMilestone = _calculateMktMilestone();
        if (mktMilestone < MKT_MILESTONES) {
            mktNext = deployTime + (mktMilestone * MKT_INTERVAL);
        }
    }

    // ════════════════════════════════════════════════════════════════════════════════
    // INTERNAL HELPERS
    // ════════════════════════════════════════════════════════════════════════════════

    function _calculateTeamVested(address beneficiary) internal view returns (uint256) {
        uint256 allocated = teamAlloc[beneficiary];
        if (allocated == 0) return 0;

        uint8 milestone = _calculateTeamMilestone();
        if (milestone == 0) return 0;

        return (allocated * milestone * TEAM_PCT) / BP;
    }

    function _calculateTeamClaimable(address beneficiary) internal view returns (uint256) {
        uint256 vested = _calculateTeamVested(beneficiary);
        uint256 claimed = teamClaimed[beneficiary];
        return vested > claimed ? vested - claimed : 0;
    }

    function _calculateTeamMilestone() internal view returns (uint8) {
        uint256 unlockTime = deployTime + TEAM_CLIFF;
        if (block.timestamp < unlockTime) return 0;
        
        uint256 elapsed = block.timestamp - unlockTime;
        uint256 milestone = (elapsed / TEAM_INTERVAL) + 1;
        return milestone > TEAM_MILESTONES ? uint8(TEAM_MILESTONES) : uint8(milestone);
    }

    function _calculateMktMilestone() internal view returns (uint8) {
        if (block.timestamp < deployTime) return 0;

        uint256 elapsed = block.timestamp - deployTime;
        if (elapsed < MKT_INTERVAL) return 1;

        uint256 milestone = (elapsed / MKT_INTERVAL) + 1;
        return milestone > MKT_MILESTONES ? uint8(MKT_MILESTONES) : uint8(milestone);
    }

    function _isFunded() internal view returns (bool) {
        return _flags & 0x01 != 0;
    }

    function _isLocked() internal view returns (bool) {
        return _flags & 0x02 != 0;
    }
}