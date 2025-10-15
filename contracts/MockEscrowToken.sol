// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockEscrowToken
 * @notice Simple mock token for testing treasury contract
 */
contract MockEscrowToken is ERC20 {
    constructor() ERC20("Mock ESCROW", "mESCROW") {
        // Mint 100 billion tokens to deployer
        _mint(msg.sender, 100_000_000_000 * 1e18);
    }
    
    // Helper function to mint more if needed
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}