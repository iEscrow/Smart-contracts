// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockEscrowTokenNoMint
 * @notice Mock ERC20 token without initial mint for testing treasury allocation scenarios
 * @dev This contract is used for testing purposes only - no tokens minted in constructor
 */
contract MockEscrowTokenNoMint is ERC20, Ownable {
    /**
     * @notice Initialize mock token without initial mint
     * @dev Constructor does not mint any tokens - tokens must be minted manually for testing
     */
    constructor() ERC20("MockEscrowTokenNoMint", "MOCK") Ownable(msg.sender) {
        // No initial mint in this version
    }

    /**
     * @notice Mint tokens to specified address
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     * @dev Only owner can mint tokens. Used for testing treasury funding scenarios.
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
