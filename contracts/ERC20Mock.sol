// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MockEscrowToken is ERC20, Ownable {
    constructor() ERC20("MockEscrowToken", "ESC") Ownable(msg.sender) {
        // Mint 1B tokens to the deployer
        _mint(msg.sender, 1_000_000_000 * 10 ** decimals());
    }

    // Helper function to mint more tokens (for testing)
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
