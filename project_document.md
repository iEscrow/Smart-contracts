# Project Documentation

## Contract Architecture

### EscrowTeamTreasury.sol

#### Overview
The `EscrowTeamTreasury` contract manages the vesting and distribution of 1 billion ESCROW tokens (1% of 100B total supply) to founders, team members, and advisors. It enforces a 3-year lock period followed by a 2-year vesting schedule with 5 milestones.

#### Constants
- `TOTAL_ALLOCATION`: 1_000_000_000 * 1e18 (1 billion tokens).
- `LOCK_DURATION`: 1095 days (3 years).
- `VESTING_INTERVAL`: 180 days (6 months).
- `VESTING_MILESTONES`: 5.
- `PERCENTAGE_PER_MILESTONE`: 2000 basis points (20%).
- `BASIS_POINTS`: 10000.

#### Structs
- `Beneficiary`: Contains `totalAllocation`, `claimedAmount`, `lastClaimMilestone`, `isActive`, `revoked`.

#### State Variables
- `escrowToken`: Immutable IERC20 token address.
- `treasuryStartTime` and `firstUnlockTime`: Timestamps for vesting.
- `beneficiaries`: Mapping of beneficiary data.
- `beneficiaryList`: Array for efficient removals.
- `totalAllocated`, `totalClaimed`: Global counters.
- `allocationsLocked`, `treasuryFunded`: Boolean flags.
- `initialBeneficiaries` and `initialAllocations`: Predefined lists for 28 beneficiaries.

#### Events
- `TreasuryFunded`, `BeneficiaryAdded`, `BeneficiaryUpdated`, `BeneficiaryRemoved`, `TokensClaimed`, `AllocationRevoked`, `AllocationsLocked`, `EmergencyWithdraw`.

#### Errors
- `InvalidAddress`, `InvalidAmount`, `ExceedsTotalAllocation`, `AlreadyAllocated`, `NotBeneficiary`, `AllocationsAlreadyLocked`, `AllocationsNotLocked`, `TreasuryNotFunded`, `TreasuryAlreadyFunded`, `LockPeriodNotEnded`, `NoTokensAvailable`, `AllocationAlreadyRevoked`, `InvalidMilestone`, `InsufficientBalance`.

#### Constructor
- Initializes token, times, and 28 pre-allocated beneficiaries.
- Emits `TreasuryFunded` event.

#### Admin Functions
- `fundTreasury`: Funds with 1B tokens (one-time).
- `addBeneficiary`: Adds new beneficiary (before locking).
- `updateBeneficiary`: Updates allocation (before locking).
- `removeBeneficiary`: Removes beneficiary (before locking, gas-optimized).
- `lockAllocations`: Locks for no more changes.
- `revokeAllocation`: Revokes and claims any vested amount.
- `pause/unpause`: Emergency controls.
- `emergencyWithdraw`: Withdraws unallocated tokens.

#### Beneficiary Functions
- `claimTokens`: Claims vested tokens for self.
- `claimFor`: Claims for another beneficiary.

#### Internal Functions
- `_calculateVestedAmount`: Calculates vested percentage based on milestone.
- `_getCurrentMilestone`: Determines current milestone from time.

#### View Functions
- `getClaimableAmount`: Returns claimable tokens.
- `getBeneficiaryInfo`: Detailed beneficiary data.
- `getAllBeneficiaries`: List of all beneficiaries.
- `getVestingSchedule`: Vesting details and unlock times.
- `getNextUnlockTime`: Time until next unlock.
- `getTreasuryStats`: Overall stats.
- `isBeneficiary`: Checks if address is beneficiary.
- `getTimeUntilNextUnlock`: Time remaining until next unlock.
- `getContractInfo`: Contract parameters.

## Security Analysis

### Threats Mitigated
- **Reentrancy**: Protected by `ReentrancyGuard` on claim functions.
- **Unauthorized Access**: `onlyOwner` on admin functions.
- **Overflow/Underflow**: Checked allocations, SafeERC20 transfers.
- **Emergency Situations**: Pausable contract, revocable allocations.
- **Input Validation**: All functions validate inputs (e.g., non-zero addresses, amounts).

### Gas Optimizations
- `unchecked` increments in safe loops.
- Swap-and-pop for array removals.
- Immutable state where possible.

### Potential Risks
- **Large Beneficiary Count**: O(n) operations in loops; recommend <100 beneficiaries for gas efficiency.
- **Token Dependency**: Relies on external ERC20; ensure it's not malicious.

## API Reference

### Function Signatures
- `constructor(address _escrowToken)`
- `fundTreasury()`
- `addBeneficiary(address beneficiary, uint256 allocation)`
- `updateBeneficiary(address beneficiary, uint256 newAllocation)`
- `removeBeneficiary(address beneficiary)`
- `lockAllocations()`
- `revokeAllocation(address beneficiary)`
- `pause()`
- `unpause()`
- `emergencyWithdraw()`
- `claimTokens()`
- `claimFor(address beneficiary)`
- Various view functions as listed.

## Deployment Guide

### Local Deployment
1. Start Hardhat node.
2. Run deploy script: `npx hardhat run scripts/deploy.js --network localhost`.
3. Verify with tests: `npm test`.

### Production Deployment
1. Configure network in `hardhat.config.js`.
2. Deploy: `npx hardhat run scripts/deploy.js --network mainnet`.
3. Verify: `npx hardhat verify --network mainnet <ADDRESS>`.

## Testing Details

### Test Files
- `test/EscrowTeamTreasury.test.js`: Main test suite.

### Test Categories
- Deployment.
- Funding.
- Beneficiary Management.
- Locking.
- Vesting & Claims.
- Emergency & Admin.
- Access Control.
- View Functions & Edge Cases.
- Additional Coverage Tests.

### Coverage Metrics
- Statements: 100%
- Branches: 100%
- Functions: 100%
- Lines: 100%

## Advanced Usage

### Custom Vesting
The contract is designed for this specific schedule but can be adapted by modifying constants.

### Integration
- Interact via ethers.js or web3.js.
- Use view functions for off-chain queries.

### Edge Cases
- Exact milestone times.
- Zero allocations.
- Revoked beneficiaries.
- Paused claims.
- Large time jumps in tests.

## Troubleshooting

### Common Issues
- Insufficient gas: Increase limits.
- Network errors: Check RPC.
- Test failures: Ensure node_modules installed.

### Debugging
- Use Hardhat console: `npx hardhat console`.
- Check events in tests.

## Glossary
- **Milestone**: Vesting point (0-5).
- **Vested Amount**: Tokens unlocked based on time.
- **Claimable**: Vested minus claimed.
- **Locked Allocations**: No more beneficiary changes.

## References
- OpenZeppelin Contracts: https://docs.openzeppelin.com/contracts/
- Hardhat Documentation: https://hardhat.org/docs/
- Solidity Docs: https://docs.soliditylang.org/
