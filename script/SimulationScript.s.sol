
// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../EscrowMultiTreasury.sol";

contract SimulationScript {
    EscrowMultiTreasury public escrow;
    
    constructor(address _escrow) {
        escrow = EscrowMultiTreasury(_escrow);
    }

    function simulateTimeTravel(uint256 timeInSeconds) external view returns (
        uint256 teamUnlocked,
        uint256 lpUnlocked,
        uint256 mktUnlocked
    ) {
        uint256 futureTime = block.timestamp + timeInSeconds;
        uint256 deployTime = escrow.deployTime();
        
        uint256 lpUnlock = 0;
        if (futureTime >= deployTime + 180 days) {
            lpUnlock = 2_500_000_000 * 1e18;
        }
        
        uint256 mktMilestones = 0;
        if (futureTime >= deployTime + 180 days) {
            mktMilestones = (futureTime - deployTime) / 180 days;
            if (mktMilestones > 4) mktMilestones = 4;
        }
        uint256 mktUnlock = mktMilestones * 500_000_000 * 1e18;
        
        uint256 teamUnlock = 0;
        if (futureTime >= deployTime + (3 * 365 days)) {
            uint256 elapsed = futureTime - (deployTime + (3 * 365 days));
            uint256 milestones = (elapsed / 180 days) + 1;
            if (milestones > 5) milestones = 5;
            teamUnlock = milestones;
        }
        
        return (teamUnlock, lpUnlock, mktUnlock);
    }

    function getUnlockSchedule() external view returns (
        uint256 lpInitialUnlock,
        uint256 lpVestedUnlock,
        uint256 mktInitialUnlock,
        uint256 mktFirstVest,
        uint256 mktSecondVest,
        uint256 mktThirdVest,
        uint256 mktFourthVest,
        uint256 teamCliff,
        uint256 teamFirstVest
    ) {
        uint256 deploy = escrow.deployTime();
        
        return (
            deploy,                     // LP Initial: Immediate
            deploy + 180 days,          // LP Vested: 6 months
            deploy,                     // Mkt Initial: Immediate
            deploy + 180 days,          // Mkt Vest 1: 6 months
            deploy + 360 days,          // Mkt Vest 2: 12 months
            deploy + 540 days,          // Mkt Vest 3: 18 months
            deploy + 720 days,          // Mkt Vest 4: 24 months
            deploy + (3 * 365 days),    // Team Cliff: 3 years
            deploy + (3 * 365 days) + 1 // Team Vest 1: 3 years + instant
        );
    }
}