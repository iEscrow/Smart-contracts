// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockEscrowToken
 * @notice Mock ERC20 token for testing the EscrowTeamTreasury contract
 * @dev This contract is used for testing purposes only
 */
contract MockEscrowToken is ERC20, Ownable {
    /**
     * @notice Initialize mock token with 1 billion tokens minted to deployer
     * @dev Mints 1 billion tokens to the contract deployer for testing
     */
    constructor() ERC20("MockEscrowToken", "ESC") Ownable(msg.sender) {
        _mint(msg.sender, 1_000_000_000 * 10 ** decimals());
    }

    /**
     * @notice Mint additional tokens to specified address
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     * @dev Only owner can mint tokens. Used for testing purposes.
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
