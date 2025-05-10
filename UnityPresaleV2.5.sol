// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IST20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}
 
library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;
        return c;
    }
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        return c;
    }
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract TokenPresale {
  using SafeMath for uint256;
  IST20 public token;
  uint256 public rate;
  uint256 public weiRaised;
  uint256 public weiMaxPurchaseBnb;
  address private admin ;
  address payable private _admin;
  AggregatorV3Interface internal priceFeed;
  address aggregatorInterface = 0x2514895c72f50D8bd4B4F9b1110F0D6bD2c97526; // BNB/USD bsc testnet
  address USDCInterface = 0x64544969ed7EBf5f083679233325356EbE738930;       // USDC BSC BEP20
  mapping(address => uint256) public purchasedBnb;
  mapping(address => uint256) public purchasedUSDC;
  event TokenPurchase(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 amount);
  event Claim(address to, uint256 amount);

  //  1 ETH = 10K tokens
  //  10000000000000000000000,0xDd565537c63CfBb8899617644AAB1B7CA423ee40,100000
  constructor(uint256 _rate, IST20 _token, uint256 _max)  {
    require(_rate > 0); // 1ETH=_rate WEI
    require(_max > 0);	// MAX TOKENS user can buy in WEI
    require(_token != IST20(address(0))); //token address for presale
    rate = _rate;
    token = _token;
    weiMaxPurchaseBnb = _max;
    admin = msg.sender;
    _admin = payable(admin);
    //priceFeed = AggregatorV3Interface(aggregatorInterface);
    //admin wallet receiving contract balance
  }
  fallback () external payable {
    revert();    
  }
  receive () external payable {
    revert();
  }


    function getLatestPrice() public view returns (uint256) {
        (, int256 ethPrice, , , ) = AggregatorV3Interface(aggregatorInterface)
            .latestRoundData();
        ethPrice = (ethPrice * (10 ** 10));
        return uint256(ethPrice);
    }

    function ethBuyHelper(
        uint256 ethAmount
    ) public view returns (uint256 amount) {
        amount = (ethAmount * getLatestPrice() * rate) / (1e6 * 10 ** 18);
    }


  function buyTokens(address _beneficiary) public payable {
    uint256 maxBnbAmount = maxBnb(_beneficiary);
    uint256 weiAmount = msg.value > maxBnbAmount ? maxBnbAmount : msg.value;
    weiAmount = _preValidatePurchase(_beneficiary, weiAmount);
    uint256 tokens = _getTokenAmount(weiAmount);
    weiRaised = weiRaised.add(weiAmount);
    //_processPurchase(_beneficiary, tokens);
    emit TokenPurchase(msg.sender, _beneficiary, weiAmount, tokens);
    _updatePurchasingState(_beneficiary, weiAmount);
    
    if (msg.value > weiAmount) {
      uint256 refundAmount = msg.value.sub(weiAmount);
      payable(msg.sender).transfer(refundAmount);      
    }
    
  }

  
    function buyTokensWithUSDC(uint256 usdcAmount, address _beneficiary) public {
        require(usdcAmount > 0, "Amount must be > 0");
        IST20 usdc = IST20(USDCInterface);
        require(usdc.transferFrom(msg.sender, address(this), usdcAmount), "USDC transfer failed");

        uint256 tokens = _getTokenAmount(usdcAmount); // Assumes USDC has 18 decimals like token
        purchasedUSDC[_beneficiary] = purchasedUSDC[_beneficiary] + tokens;

        emit TokenPurchase(msg.sender, _beneficiary, usdcAmount, tokens);
    }
