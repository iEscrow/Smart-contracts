
// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../EscrowMultiTreasury.sol";

contract ClaimMarketingScript {
    EscrowMultiTreasury public escrow;
    
    constructor(address _escrow) {
        escrow = EscrowMultiTreasury(_escrow);
    }

    function claimInitial() external {
        escrow.claimMktInitial();
    }

    function claimVested() external {
        escrow.claimMktVested();
    }

    function claimBoth() external {
        escrow.claimMktInitial();
        escrow.claimMktVested();
    }

    function checkStatus() external view returns (
        uint256 initialAmount,
        uint256 perMilestone,
        uint256 totalClaimed,
        uint256 claimableNow,
        uint8 currentMilestone,
        uint8 lastClaimedMilestone,
        bool initialClaimed
    ) {
        return escrow.mktInfo();
    }
}