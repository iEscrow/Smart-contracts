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
 * @notice Treasury for Team (1%), LP (5%), and Marketing (3.4%) allocations
 * @dev Team: 3yr cliff + 5 milestones (20% per 6mo) | LP: instant | Marketing: 4 milestones (25% per 6mo)
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

    // Flags: bit0=funded | bit1=locked | bit2=lpClaimed
    uint8 private _flags;

    // Team
    mapping(address => uint256) public teamAlloc;
    mapping(address => uint256) public teamClaimed;
    address[] private _teamList;
    uint256 public teamTotal;

    // LP & Marketing (single recipient each)
    address public immutable lpRecipient;
    address public immutable mktRecipient;
    uint256 public mktClaimed;
    uint8 public mktLastMilestone;

    // ════════════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ════════════════════════════════════════════════════════════════════════════════

    event Funded(uint256 amount);
    event TeamSet(address indexed who, uint256 amount);
    event TeamRemoved(address indexed who, uint256 amount);
    event Locked();
    event Claimed(address indexed who, uint256 amount, uint8 milestone);

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
    error NoTokens();
    error Unauthorized();

    // ════════════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ════════════════════════════════════════════════════════════════════════════════

    constructor(
        address _token,
        address _lp,
        address _mkt
    ) Ownable(msg.sender) {
        if (_token == address(0) || _lp == address(0) || _mkt == address(0)) 
            revert ZeroAddress();

        token = IERC20(_token);
        lpRecipient = _lp;
        mktRecipient = _mkt;
        deployTime = block.timestamp;
    }

    // ════════════════════════════════════════════════════════════════════════════════
    // ADMIN
    // ════════════════════════════════════════════════════════════════════════════════

    /// @notice Fund treasury (once)
    function fund() external onlyOwner {
        if (_isFunded()) revert AlreadyFunded();
        token.safeTransferFrom(msg.sender, address(this), TOTAL_ALLOC);
        _flags |= 0x01;
        emit Funded(TOTAL_ALLOC);
    }

    /// @notice Set team beneficiary
    function setTeam(address who, uint256 amt) external onlyOwner {
        if (!_isFunded()) revert NotFunded();
        if (_isLocked()) revert AlreadyLocked();
        if (who == address(0)) revert ZeroAddress();
        if (amt == 0) revert ZeroAmount();
        if (teamAlloc[who] > 0) revert AlreadyExists();
        if (teamTotal + amt > TEAM_ALLOC) revert ExceedsLimit();

        teamAlloc[who] = amt;
        _teamList.push(who);
        teamTotal += amt;
        emit TeamSet(who, amt);
    }

    /// @notice Batch set team (gas efficient)
    function batchSetTeam(address[] calldata addrs, uint256[] calldata amts) external onlyOwner {
        if (!_isFunded()) revert NotFunded();
        if (_isLocked()) revert AlreadyLocked();
        uint256 len = addrs.length;
        if (len != amts.length || len == 0) revert ZeroAmount();

        uint256 total;
        for (uint256 i; i < len;) {
            if (addrs[i] == address(0)) revert ZeroAddress();
            if (amts[i] == 0) revert ZeroAmount();
            if (teamAlloc[addrs[i]] > 0) revert AlreadyExists();
            total += amts[i];
            unchecked { ++i; }
        }

        if (teamTotal + total > TEAM_ALLOC) revert ExceedsLimit();

        for (uint256 i; i < len;) {
            teamAlloc[addrs[i]] = amts[i];
            _teamList.push(addrs[i]);
            emit TeamSet(addrs[i], amts[i]);
            unchecked { ++i; }
        }
        teamTotal += total;
    }

    /// @notice Remove team beneficiary (before lock)
    function removeTeam(address who) external onlyOwner {
        if (_isLocked()) revert AlreadyLocked();
        uint256 amt = teamAlloc[who];
        if (amt == 0) revert NotFound();

        delete teamAlloc[who];
        teamTotal -= amt;

        // Swap & pop
        uint256 len = _teamList.length;
        for (uint256 i; i < len;) {
            if (_teamList[i] == who) {
                _teamList[i] = _teamList[len - 1];
                _teamList.pop();
                break;
            }
            unchecked { ++i; }
        }
        emit TeamRemoved(who, amt);
    }

    /// @notice Lock allocations
    function lock() external onlyOwner {
        if (!_isFunded()) revert NotFunded();
        if (_isLocked()) revert AlreadyLocked();
        if (teamTotal == 0) revert ZeroAmount();
        _flags |= 0x02;
        emit Locked();
    }

    /// @notice Emergency pause
    function pause() external onlyOwner { _pause(); }

    /// @notice Unpause
    function unpause() external onlyOwner { _unpause(); }

    // ════════════════════════════════════════════════════════════════════════════════
    // CLAIMING
    // ════════════════════════════════════════════════════════════════════════════════

    /// @notice Claim team tokens (self only)
    function claimTeam() external nonReentrant whenNotPaused {
        if (!_isFunded()) revert NotFunded();
        if (!_isLocked()) revert NotLocked();
        
        uint256 amt = teamAlloc[msg.sender];
        if (amt == 0) revert NotFound();

        uint256 claimable = _teamClaimable(msg.sender);
        if (claimable == 0) revert NoTokens();

        teamClaimed[msg.sender] += claimable;
        token.safeTransfer(msg.sender, claimable);
        emit Claimed(msg.sender, claimable, _teamMilestone());
    }

    /// @notice Claim LP tokens (recipient only, once)
    function claimLP() external nonReentrant whenNotPaused {
        if (!_isFunded()) revert NotFunded();
        if (msg.sender != lpRecipient) revert Unauthorized();
        if (_flags & 0x04 != 0) revert NoTokens(); // Already claimed

        _flags |= 0x04;
        token.safeTransfer(lpRecipient, LP_ALLOC);
        emit Claimed(lpRecipient, LP_ALLOC, 0);
    }

    /// @notice Claim marketing tokens (recipient only)
    function claimMkt() external nonReentrant whenNotPaused {
        if (!_isFunded()) revert NotFunded();
        if (msg.sender != mktRecipient) revert Unauthorized();

        uint8 curr = _mktMilestone();
        if (curr <= mktLastMilestone) revert NoTokens();

        uint256 claimable = ((curr - mktLastMilestone) * MKT_ALLOC * MKT_PCT) / BP;
        if (mktClaimed + claimable > MKT_ALLOC) claimable = MKT_ALLOC - mktClaimed;
        if (claimable == 0) revert NoTokens();

        mktClaimed += claimable;
        mktLastMilestone = curr;
        token.safeTransfer(mktRecipient, claimable);
        emit Claimed(mktRecipient, claimable, curr);
    }

    // ════════════════════════════════════════════════════════════════════════════════
    // VIEWS
    // ════════════════════════════════════════════════════════════════════════════════

    /// @notice Get team claimable amount
    function teamClaimable(address who) external view returns (uint256) {
        return _teamClaimable(who);
    }

    /// @notice Get team info
    function teamInfo(address who) external view returns (
        uint256 allocated,
        uint256 vested,
        uint256 claimed,
        uint256 claimable,
        uint8 milestone
    ) {
        allocated = teamAlloc[who];
        if (allocated == 0) return (0, 0, 0, 0, 0);
        
        claimed = teamClaimed[who];
        vested = _teamVested(who);
        claimable = vested > claimed ? vested - claimed : 0;
        milestone = _teamMilestone();
    }

    /// @notice Get marketing claimable
    function mktClaimable() external view returns (uint256) {
        uint8 curr = _mktMilestone();
        if (curr <= mktLastMilestone) return 0;
        
        uint256 amt = ((curr - mktLastMilestone) * MKT_ALLOC * MKT_PCT) / BP;
        return mktClaimed + amt > MKT_ALLOC ? MKT_ALLOC - mktClaimed : amt;
    }

    /// @notice Get treasury stats
    function stats() external view returns (
        uint256 balance,
        uint256 teamCount,
        bool funded,
        bool locked
    ) {
        return (
            token.balanceOf(address(this)),
            _teamList.length,
            _isFunded(),
            _isLocked()
        );
    }

    /// @notice Get all team beneficiaries
    function allTeam() external view returns (
        address[] memory addrs,
        uint256[] memory allocs,
        uint256[] memory claimed
    ) {
        uint256 len = _teamList.length;
        addrs = new address[](len);
        allocs = new uint256[](len);
        claimed = new uint256[](len);

        for (uint256 i; i < len;) {
            addrs[i] = _teamList[i];
            allocs[i] = teamAlloc[_teamList[i]];
            claimed[i] = teamClaimed[_teamList[i]];
            unchecked { ++i; }
        }
    }

    /// @notice Get next unlock times
    function nextUnlock() external view returns (uint256 teamNext, uint256 mktNext) {
        uint8 tm = _teamMilestone();
        if (tm == 0) {
            // Before cliff, next unlock is at cliff
            teamNext = deployTime + TEAM_CLIFF;
        } else if (tm < TEAM_MILESTONES) {
            // After cliff, next unlock is at cliff + (current milestone * interval)
            teamNext = deployTime + TEAM_CLIFF + (tm * TEAM_INTERVAL);
        } else {
            teamNext = 0; // No more team unlocks
        }

        uint8 mm = _mktMilestone();
        if (mm < MKT_MILESTONES) {
            // Next marketing unlock is at current milestone * interval
            mktNext = deployTime + (mm * MKT_INTERVAL);
        } else {
            mktNext = 0; // No more marketing unlocks
        }
    }

    // ════════════════════════════════════════════════════════════════════════════════
    // INTERNAL
    // ════════════════════════════════════════════════════════════════════════════════

    function _teamVested(address who) internal view returns (uint256) {
        uint256 alloc = teamAlloc[who];
        if (alloc == 0) return 0;

        uint8 m = _teamMilestone();
        if (m == 0) return 0;

        return (alloc * m * TEAM_PCT) / BP;
    }

    function _teamClaimable(address who) internal view returns (uint256) {
        uint256 vested = _teamVested(who);
        uint256 claimed = teamClaimed[who];
        return vested > claimed ? vested - claimed : 0;
    }

    function _teamMilestone() internal view returns (uint8) {
        uint256 unlock = deployTime + TEAM_CLIFF;
        if (block.timestamp < unlock) return 0;
        
        // At exactly unlock time, we're at milestone 1
        if (block.timestamp == unlock) return 1;
        // After unlock, calculate milestones based on intervals passed
        uint256 elapsed = block.timestamp - unlock;
        // Milestone 1 at unlock, milestone 2 at unlock + interval, etc.
        uint256 m = (elapsed / TEAM_INTERVAL) + 1;
        return m > TEAM_MILESTONES ? uint8(TEAM_MILESTONES) : uint8(m);
    }

    function _mktMilestone() internal view returns (uint8) {
        if (block.timestamp < deployTime) return 0;

        uint256 elapsed = block.timestamp - deployTime;
        if (elapsed < MKT_INTERVAL) return 1;

        uint256 m = (elapsed / MKT_INTERVAL) + 1;
        return m > MKT_MILESTONES ? uint8(MKT_MILESTONES) : uint8(m);
    }

    function _isFunded() internal view returns (bool) {
        return _flags & 0x01 != 0;
    }

    function _isLocked() internal view returns (bool) {
        return _flags & 0x02 != 0;
    }
}