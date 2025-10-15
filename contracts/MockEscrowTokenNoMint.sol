// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MockEscrowTokenNoMint is ERC20, Ownable {
    constructor() ERC20("MockEscrowTokenNoMint", "MOCK") Ownable(msg.sender) {
        // No initial mint in this version
    }

    // Helper function to mint tokens (for testing)
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
