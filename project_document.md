# EscrowTeamTreasury - Technical Documentation

## Contract Architecture

### EscrowTeamTreasury.sol

#### Overview
The `EscrowTeamTreasury` contract manages the vesting and distribution of 1 billion ESCROW tokens (1% of 100B total supply) to founders, team members, and advisors. It enforces a 3-year lock period followed by a 2-year vesting schedule with 5 milestones.

#### Constants
- `TOTAL_ALLOCATION`: 1_000_000_000 * 1e18 (1 billion tokens).
- `LOCK_DURATION`: 3 * 365 days (3 years - precisely calculated).
- `VESTING_INTERVAL`: 180 days (6 months).
- `VESTING_MILESTONES`: 5.
- `PERCENTAGE_PER_MILESTONE`: 2000 basis points (20%).
- `BASIS_POINTS`: 10000.

#### Structs
- `Beneficiary`: Contains `totalAllocation`, `claimedAmount`, `isActive`, `revoked`.

#### State Variables
- `escrowToken`: Immutable IERC20 token address.
- `treasuryStartTime` and `firstUnlockTime`: Timestamps for vesting.
- `beneficiaries`: Mapping of beneficiary data.
- `beneficiaryList`: Array for efficient removals.
- `totalAllocated`, `totalClaimed`: Global counters.
- `allocationsLocked`, `treasuryFunded`: Boolean flags.
- `initialBeneficiaries` and `initialAllocations`: Predefined lists for 28 beneficiaries.

#### Events
- `TreasuryFunded`, `BeneficiaryAdded`, `BeneficiaryUpdated`, `BeneficiaryRemoved`, `TokensClaimed`, `AllocationRevoked`, `AllocationsLocked`.

#### Errors
- `InvalidAddress`, `InvalidAmount`, `ExceedsTotalAllocation`, `AlreadyAllocated`, `NotBeneficiary`, `AllocationsAlreadyLocked`, `AllocationsNotLocked`, `TreasuryNotFunded`, `TreasuryAlreadyFunded`, `LockPeriodNotEnded`, `NoTokensAvailable`, `AllocationAlreadyRevoked`, `InvalidMilestone`, `InsufficientBalance`.

#### Constructor
- Initializes token, times, and 28 pre-allocated beneficiaries.

#### Admin Functions
- `fundTreasury`: Funds with 1B tokens (one-time).
- `addBeneficiary`: Adds new beneficiary (before locking).
- `updateBeneficiary`: Updates allocation (before locking).
- `removeBeneficiary`: Removes beneficiary (before locking, gas-optimized).
- `lockAllocations`: Locks for no more changes.
- `revokeAllocation`: Revokes and claims any vested amount.

#### Beneficiary Functions
- `claimFor`: Claims vested tokens for any beneficiary (anyone can trigger).

#### Internal Functions
- `_calculateVestedAmount`: Calculates vested percentage based on milestone.
- `_getCurrentMilestone`: Determines current milestone from time.

#### View Functions
- `getClaimableAmount`: Returns claimable tokens.
- `getBeneficiaryInfo`: Detailed beneficiary data.
- `getAllBeneficiaries`: List of all beneficiaries.
- `getVestingSchedule`: Vesting details (gas optimized - no dynamic arrays).
- `getNextUnlockTime`: Time until next unlock.
- `getTreasuryStats`: Overall stats.
- `isBeneficiary`: Checks if address is beneficiary.
- `getTimeUntilNextUnlock`: Time remaining until next unlock.
- `getContractInfo`: Contract parameters.

## Security Analysis

### Threats Mitigated
- **Reentrancy**: Claims use nonReentrant modifier.
- **Unauthorized Access**: `onlyOwner` on admin functions.
- **Overflow/Underflow**: Checked allocations, SafeERC20 transfers.
- **Input Validation**: All functions validate inputs (e.g., non-zero addresses, amounts).

### Gas Optimizations
- `unchecked` increments in safe loops.
- Swap-and-pop for array removals.
- Immutable state where possible.
- Removed unnecessary emergency and pause functionality.
- Simplified struct by removing unused fields.
- Optimized view functions to avoid dynamic array creation.

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
- `claimFor(address beneficiary)`
- Various view functions as listed.

## Deployment Guide

### Foundry-based Deployment
```bash
# Install dependencies
forge install

# Build contracts
forge build

# Run tests
forge test

# Deploy locally
anvil
# Then in another terminal:
forge create --rpc-url http://localhost:8545 --private-key 0x... contracts/EscrowTeamTreasury.sol:EscrowTeamTreasury --constructor-args <TOKEN_ADDRESS>
```

### Production Deployment
```bash
# Update foundry.toml with network details
forge create --rpc-url $MAINNET_RPC --private-key $PRIVATE_KEY contracts/EscrowTeamTreasury.sol:EscrowTeamTreasury --constructor-args <TOKEN_ADDRESS>
```

## Testing Details

### Test Files
- `test/EscrowTeamTreasury.t.sol`: Main Foundry test suite.

### Test Categories
- Deployment and initialization.
- Funding and allocation management.
- Vesting and claiming at boundaries.
- Access control and error conditions.
- View functions and edge cases.

### Coverage Metrics
- **54 passing tests** (optimized from 56 by removing unnecessary tests)
- Comprehensive coverage of all functionality
- Edge cases and error scenarios included

## Gas Optimization Details

### Optimizations Implemented
1. **Removed Emergency Functions**: Eliminated pause/unpause and emergencyWithdraw for simplicity
2. **Simplified Beneficiary Struct**: Removed unused `lastClaimMilestone` field
3. **Streamlined Claiming**: Removed duplicate `claimTokens()` function
4. **Optimized View Functions**: `getVestingSchedule()` no longer creates dynamic arrays
5. **Clean Architecture**: Removed unused imports and inheritance
6. **Precise Calculations**: Fixed `LOCK_DURATION` to use exact calculation

### Gas Savings
- Reduced contract complexity
- Eliminated unnecessary function calls
- Minimized storage operations
- Optimized loop operations with unchecked increments

## Development

### Adding New Features
1. Write tests first (TDD approach)
2. Implement minimal viable functionality
3. Optimize for gas efficiency
4. Update documentation

### Code Style
- Use descriptive variable names
- Include comprehensive NatSpec documentation
- Follow Solidity best practices
- Optimize for gas where possible

## Contract Addresses

*Update after deployment:*
- **Treasury Contract**: [Deployed Address]
- **Token Contract**: [Token Address]

## Support

For technical support or questions:
- Review the README.md for quick start
- Check test files for usage examples
- Refer to inline code documentation

## Version History

- **v1.0.0**: Initial optimized release
  - Gas optimizations implemented
  - Emergency functions removed
  - Test suite updated
  - Foundry migration complete

## References
- Foundry Documentation: https://book.getfoundry.sh/
- OpenZeppelin Contracts: https://docs.openzeppelin.com/contracts/
- Solidity Documentation: https://docs.soliditylang.org/
