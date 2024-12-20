// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract UnityFinance is ERC20 {
    uint256 public txFee;
    string public _imageUrl = 'bafkreieqjczhpifqujmw5h7biqjg3fmryqnkjyt6lckyrdm2pmpjrbku6u.ipfs.nftstorage.link';
    address private _owner;
    uint256 public circulating ;
    uint256 public burnt;
     
    uint256 private _totalSupply =  1000000 * 10 ** uint(decimals()); // 1M
    mapping(address => bool) public whitelists;


   constructor() ERC20("UnityFi", "UFTv3")  {
        txFee = 1;
        _owner = msg.sender;
        circulating = 0;
        burnt = 0;
        _mint(msg.sender,_totalSupply);
    }



    function transfer(
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        
        if (whitelists[to] == false) {
            uint256 tokensToBurn = (amount / 100) * txFee;
            circulating += (amount-tokensToBurn);
            burnt += tokensToBurn;           
            _burn (msg.sender,tokensToBurn);
            _transfer(msg.sender, to, (amount - tokensToBurn));
        }
        else {
            circulating += amount;
            _transfer(msg.sender, to, amount);
        }
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        address spender = _msgSender();
        
        if (whitelists[from] == false && whitelists[to] == false) {
            uint256 tokensToBurn = (amount / 100) * txFee;
            circulating += (amount-tokensToBurn);
            burnt += tokensToBurn;
            _spendAllowance(from, spender, amount);
            _burn (msg.sender,tokensToBurn);
            _transfer(from, to, amount - (tokensToBurn));
            return true;
        }
        else {
            circulating += amount;
            _spendAllowance(from, spender, amount);
            _transfer(from, to, amount);
            return true;
        }
    }

   
    function changeFee(uint256 txFee_)  public  onlyOwner  {
        txFee = txFee_;
    }

    function burnIt(uint256 tokensToBurn)  public  onlyOwner  {
        burnt += tokensToBurn;
        _burn (msg.sender,tokensToBurn);
    }
  
    function enableWhitelist(address whitelist_)  public  onlyOwner  {
        whitelists[whitelist_] = true;
    }

    function disableWhitelist(address blacklist_)  public  onlyOwner  {
        whitelists[blacklist_] = false;
    }

   modifier onlyOwner() {
    require(_owner == msg.sender, "Ownership Assertion: Caller of the function is not the owner.");
    _;
   } 

   function transferOwnership(address newOwner) public virtual onlyOwner {
    _owner = newOwner;
   } 

}
