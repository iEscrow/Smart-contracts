// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title EscrowMultiTreasury
 * @notice Vesting treasury for Team (1%), LP (5%), and Marketing (3.4%)
 * @dev Team: 3yr cliff + 5x20% | LP: 2.5B instant + 2.5B@6mo | Mkt: 1.4B instant + 4x500M@6mo
 */
contract EscrowMultiTreasury is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    uint256 private constant BP = 10_000;
    uint256 private constant TOTAL_ALLOC = 9_400_000_000 * 1e18;
    uint256 private constant TEAM_ALLOC = 1_000_000_000 * 1e18;
    uint256 private constant LP_INITIAL = 2_500_000_000 * 1e18;
    uint256 private constant LP_VESTED = 2_500_000_000 * 1e18;
    uint256 private constant MKT_INITIAL = 1_400_000_000 * 1e18;
    uint256 private constant MKT_PER_MILESTONE = 500_000_000 * 1e18;

    uint256 private constant TEAM_CLIFF = 3 * 365 days;
    uint256 private constant TEAM_INTERVAL = 180 days;
    uint256 private constant TEAM_MILESTONES = 5;
    uint256 private constant TEAM_PCT = 2000;
    uint256 private constant LP_INTERVAL = 180 days;
    uint256 private constant MKT_INTERVAL = 180 days;
    uint256 private constant MKT_MILESTONES = 4;

    IERC20 public immutable token;
    uint256 public immutable deployTime;
    address public immutable lpRecipient;
    address public immutable mktRecipient;

    uint8 private _flags; // bit0=funded|bit1=locked|bit2=lpInit|bit3=lpVest|bit4=mktInit
    mapping(address => uint256) public teamAlloc;
    mapping(address => uint256) public teamClaimed;
    address[] private _teamList;
    uint256 public teamTotal;
    uint256 public mktClaimed;
    uint8 public mktLastMilestone;

    event Funded(uint256 amount);
    event TeamSet(address indexed beneficiary, uint256 amount);
    event TeamRemoved(address indexed beneficiary, uint256 amount);
    event Locked();
    event Claimed(address indexed recipient, uint256 amount, string category);

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

    constructor(address _token, address _lp, address _mkt) Ownable(msg.sender) {
        if (_token == address(0) || _lp == address(0) || _mkt == address(0)) revert ZeroAddress();
        token = IERC20(_token);
        lpRecipient = _lp;
        mktRecipient = _mkt;
        deployTime = block.timestamp;
    }

    function fund() external onlyOwner {
        if (_isFunded()) revert AlreadyFunded();
        token.safeTransferFrom(msg.sender, address(this), TOTAL_ALLOC);
        _flags |= 0x01;
        emit Funded(TOTAL_ALLOC);
    }

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

    function removeTeam(address beneficiary) external onlyOwner {
        if (_isLocked()) revert AlreadyLocked();
        uint256 amount = teamAlloc[beneficiary];
        if (amount == 0) revert NotFound();
        delete teamAlloc[beneficiary];
        teamTotal -= amount;
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

    function lock() external onlyOwner {
        if (!_isFunded()) revert NotFunded();
        if (_isLocked()) revert AlreadyLocked();
        if (teamTotal == 0) revert ZeroAmount();
        _flags |= 0x02;
        emit Locked();
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    function claimTeam() external nonReentrant whenNotPaused {
        if (!_isFunded()) revert NotFunded();
        if (!_isLocked()) revert NotLocked();
        if (teamAlloc[msg.sender] == 0) revert NotFound();
        uint256 claimable = _teamClaimable(msg.sender);
        if (claimable == 0) revert NoTokensAvailable();
        teamClaimed[msg.sender] += claimable;
        token.safeTransfer(msg.sender, claimable);
        emit Claimed(msg.sender, claimable, "Team");
    }

    function claimLPInitial() external nonReentrant whenNotPaused {
        if (!_isFunded()) revert NotFunded();
        if (msg.sender != lpRecipient) revert Unauthorized();
        if (_flags & 0x04 != 0) revert NoTokensAvailable();
        _flags |= 0x04;
        token.safeTransfer(lpRecipient, LP_INITIAL);
        emit Claimed(lpRecipient, LP_INITIAL, "LP-Initial");
    }

    function claimLPVested() external nonReentrant whenNotPaused {
        if (!_isFunded()) revert NotFunded();
        if (msg.sender != lpRecipient) revert Unauthorized();
        if (_flags & 0x08 != 0) revert NoTokensAvailable();
        if (block.timestamp < deployTime + LP_INTERVAL) revert NoTokensAvailable();
        _flags |= 0x08;
        token.safeTransfer(lpRecipient, LP_VESTED);
        emit Claimed(lpRecipient, LP_VESTED, "LP-Vested");
    }

    function claimMktInitial() external nonReentrant whenNotPaused {
        if (!_isFunded()) revert NotFunded();
        if (msg.sender != mktRecipient) revert Unauthorized();
        if (_flags & 0x10 != 0) revert NoTokensAvailable();
        _flags |= 0x10;
        mktClaimed += MKT_INITIAL;
        token.safeTransfer(mktRecipient, MKT_INITIAL);
        emit Claimed(mktRecipient, MKT_INITIAL, "Marketing-Initial");
    }

    function claimMktVested() external nonReentrant whenNotPaused {
        if (!_isFunded()) revert NotFunded();
        if (msg.sender != mktRecipient) revert Unauthorized();
        uint8 current = _mktMilestone();
        if (current <= mktLastMilestone) revert NoTokensAvailable();
        uint256 claimable = (current - mktLastMilestone) * MKT_PER_MILESTONE;
        if (claimable == 0) revert NoTokensAvailable();
        mktClaimed += claimable;
        mktLastMilestone = current;
        token.safeTransfer(mktRecipient, claimable);
        emit Claimed(mktRecipient, claimable, "Marketing-Vested");
    }

    function teamClaimable(address beneficiary) external view returns (uint256) {
        return _teamClaimable(beneficiary);
    }

    function teamInfo(address beneficiary) external view returns (
        uint256 allocated, uint256 vested, uint256 claimed, uint256 claimable, uint8 milestone
    ) {
        allocated = teamAlloc[beneficiary];
        if (allocated == 0) return (0, 0, 0, 0, 0);
        claimed = teamClaimed[beneficiary];
        vested = _teamVested(beneficiary);
        claimable = vested > claimed ? vested - claimed : 0;
        milestone = _teamMilestone();
    }

    function lpInfo() external view returns (
        uint256 initialAmount, uint256 vestedAmount, bool initialClaimed, bool vestedClaimed, bool vestedUnlocked
    ) {
        return (
            LP_INITIAL, LP_VESTED, _flags & 0x04 != 0, _flags & 0x08 != 0, 
            block.timestamp >= deployTime + LP_INTERVAL
        );
    }

    function mktInfo() external view returns (
        uint256 initialAmount, uint256 perMilestone, uint256 totalClaimed, 
        uint256 claimableNow, uint8 currentMilestone, uint8 lastClaimedMilestone, bool initialClaimed
    ) {
        uint8 current = _mktMilestone();
        uint256 claimable = current > mktLastMilestone ? (current - mktLastMilestone) * MKT_PER_MILESTONE : 0;
        return (MKT_INITIAL, MKT_PER_MILESTONE, mktClaimed, claimable, current, mktLastMilestone, _flags & 0x10 != 0);
    }

    function stats() external view returns (uint256 balance, uint256 teamCount, bool funded, bool locked) {
        return (token.balanceOf(address(this)), _teamList.length, _isFunded(), _isLocked());
    }

    function allTeam() external view returns (
        address[] memory beneficiaries, uint256[] memory allocations, uint256[] memory claimed
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

    function nextUnlock() external view returns (uint256 teamNext, uint256 lpNext, uint256 mktNext) {
        uint8 tm = _teamMilestone();
        if (tm == 0) teamNext = deployTime + TEAM_CLIFF;
        else if (tm < TEAM_MILESTONES) teamNext = deployTime + TEAM_CLIFF + (tm * TEAM_INTERVAL);
        if (_flags & 0x08 == 0 && block.timestamp < deployTime + LP_INTERVAL) lpNext = deployTime + LP_INTERVAL;
        uint8 mm = _mktMilestone();
        if (mm < MKT_MILESTONES) mktNext = deployTime + ((mm + 1) * MKT_INTERVAL);
    }

    function _teamVested(address beneficiary) internal view returns (uint256) {
        uint256 allocated = teamAlloc[beneficiary];
        if (allocated == 0) return 0;
        uint8 milestone = _teamMilestone();
        if (milestone == 0) return 0;
        return (allocated * milestone * TEAM_PCT) / BP;
    }

    function _teamClaimable(address beneficiary) internal view returns (uint256) {
        uint256 vested = _teamVested(beneficiary);
        uint256 claimed = teamClaimed[beneficiary];
        return vested > claimed ? vested - claimed : 0;
    }

    function _teamMilestone() internal view returns (uint8) {
        uint256 unlock = deployTime + TEAM_CLIFF;
        if (block.timestamp < unlock) return 0;
        uint256 elapsed = block.timestamp - unlock;
        uint256 m = (elapsed / TEAM_INTERVAL) + 1;
        return m > TEAM_MILESTONES ? uint8(TEAM_MILESTONES) : uint8(m);
    }

    function _mktMilestone() internal view returns (uint8) {
        if (block.timestamp < deployTime + MKT_INTERVAL) return 0;
        uint256 elapsed = block.timestamp - deployTime;
        uint256 m = elapsed / MKT_INTERVAL;
        return m > MKT_MILESTONES ? uint8(MKT_MILESTONES) : uint8(m);
    }

    function _isFunded() internal view returns (bool) { return _flags & 0x01 != 0; }
    function _isLocked() internal view returns (bool) { return _flags & 0x02 != 0; }
}