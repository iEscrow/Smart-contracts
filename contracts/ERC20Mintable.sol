// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @dev Token ERC-20 que cualquier propietario puede “mint” para pruebas
contract ERC20Mintable is ERC20, Ownable {
    constructor() ERC20("TestToken", "TTK") {}

    /// @notice Mint de prueba que solo el owner puede invocar
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
