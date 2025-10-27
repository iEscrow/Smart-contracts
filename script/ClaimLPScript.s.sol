
// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../EscrowMultiTreasury.sol";

contract ClaimLPScript {
    EscrowMultiTreasury public escrow;
    
    constructor(address _escrow) {
        escrow = EscrowMultiTreasury(_escrow);
    }

    function claimInitial() external {
        escrow.claimLPInitial();
    }

    function claimVested() external {
        escrow.claimLPVested();
    }

    function claimBoth() external {
        escrow.claimLPInitial();
        escrow.claimLPVested();
    }

    function checkStatus() external view returns (
        uint256 initialAmount,
        uint256 vestedAmount,
        bool initialClaimed,
        bool vestedClaimed,
        bool vestedUnlocked
    ) {
        return escrow.lpInfo();
    }
}