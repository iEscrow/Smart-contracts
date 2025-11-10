
// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../EscrowMultiTreasury.sol";

contract AdminScript {
    EscrowMultiTreasury public escrow;
    
    constructor(address _escrow) {
        escrow = EscrowMultiTreasury(_escrow);
    }

    function pause() external {
        escrow.pause();
    }

    function unpause() external {
        escrow.unpause();
    }

    function addTeamMember(address member, uint256 amount) external {
        escrow.setTeam(member, amount);
    }

    function removeTeamMember(address member) external {
        escrow.removeTeam(member);
    }

    function getStats() external view returns (
        uint256 balance,
        uint256 teamCount,
        bool funded,
        bool locked
    ) {
        return escrow.stats();
    }

    function getNextUnlocks() external view returns (
        uint256 teamNext,
        uint256 lpNext,
        uint256 mktNext
    ) {
        return escrow.nextUnlock();
    }

    function getAllTeam() external view returns (
        address[] memory beneficiaries,
        uint256[] memory allocations,
        uint256[] memory claimed
    ) {
        return escrow.allTeam();
    }
}