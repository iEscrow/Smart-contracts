
// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../EscrowMultiTreasury.sol";

contract ClaimTeamScript {
    EscrowMultiTreasury public escrow;
    
    constructor(address _escrow) {
        escrow = EscrowMultiTreasury(_escrow);
    }

    function claim() external {
        escrow.claimTeam();
    }

    function checkClaimable(address member) external view returns (uint256) {
        return escrow.teamClaimable(member);
    }

    function checkInfo(address member) external view returns (
        uint256 allocated,
        uint256 vested,
        uint256 claimed,
        uint256 claimable,
        uint8 milestone
    ) {
        return escrow.teamInfo(member);
    }
}