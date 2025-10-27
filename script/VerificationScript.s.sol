
// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../EscrowMultiTreasury.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract VerificationScript {
    EscrowMultiTreasury public escrow;
    IERC20 public token;
    
    constructor(address _escrow, address _token) {
        escrow = EscrowMultiTreasury(_escrow);
        token = IERC20(_token);
    }

    function verifyDeployment() external view returns (
        bool allocationCorrect,
        bool funded,
        bool locked,
        uint256 teamCount,
        uint256 teamTotal,
        uint256 contractBalance
    ) {
        (uint256 balance, uint256 count, bool isFunded, bool isLocked) = escrow.stats();
        
        return (
            escrow.teamTotal() == 1_000_000_000 * 1e18,
            isFunded,
            isLocked,
            count,
            escrow.teamTotal(),
            balance
        );
    }

    function verifyTeamAllocations() external view returns (
        address[] memory members,
        uint256[] memory allocations,
        bool[] memory valid
    ) {
        (address[] memory addrs, uint256[] memory allocs,) = escrow.allTeam();
        bool[] memory validFlags = new bool[](addrs.length);
        
        for (uint256 i = 0; i < addrs.length; i++) {
            validFlags[i] = allocs[i] > 0;
        }
        
        return (addrs, allocs, validFlags);
    }

    function verifyLPSetup() external view returns (
        address lpRecipient,
        uint256 initialAmount,
        uint256 vestedAmount,
        uint256 totalLP
    ) {
        (uint256 initial, uint256 vested,,,) = escrow.lpInfo();
        return (
            escrow.lpRecipient(),
            initial,
            vested,
            initial + vested
        );
    }

    function verifyMarketingSetup() external view returns (
        address mktRecipient,
        uint256 initialAmount,
        uint256 perMilestone,
        uint256 totalMkt
    ) {
        (uint256 initial, uint256 perMile,,,,,) = escrow.mktInfo();
        return (
            escrow.mktRecipient(),
            initial,
            perMile,
            initial + (perMile * 4)
        );
    }

    function verifyTotalAllocation() external view returns (
        uint256 teamAlloc,
        uint256 lpAlloc,
        uint256 mktAlloc,
        uint256 totalAlloc,
        bool matches
    ) {
        uint256 team = escrow.teamTotal();
        (uint256 lpInit, uint256 lpVest,,,) = escrow.lpInfo();
        (uint256 mktInit, uint256 mktPerMile,,,,,) = escrow.mktInfo();
        
        uint256 lp = lpInit + lpVest;
        uint256 mkt = mktInit + (mktPerMile * 4);
        uint256 total = team + lp + mkt;
        
        return (
            team,
            lp,
            mkt,
            total,
            total == 9_400_000_000 * 1e18
        );
    }
}