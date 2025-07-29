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
    
    // Token configuration
    IST20 public token;
    uint8 public tokenDecimals;
    uint256 public rate;
    uint256 public weiRaised;
    uint256 public weiMaxPurchaseBnb;
    
    // Presale timing
    uint256 public presaleStartTime;
    uint256 public presaleEndTime;
    bool public presaleActive;
    
    // Admin
    address private admin;
    address payable private _admin;
    
    // Price feeds
    AggregatorV3Interface internal priceFeed;
    address aggregatorInterface = 0x2514895c72f50D8bd4B4F9b1110F0D6bD2c97526; // BNB/USD bsc testnet
    address USDCInterface = 0x64544969ed7EBf5f083679233325356EbE738930;       // USDC BSC BEP20
    
    // Purchase tracking
    mapping(address => uint256) public purchasedBnb;
    mapping(address => uint256) public purchasedUSDC;
    mapping(address => uint256) public claimedTokens;
    
    // Events for better traceability
    event TokenPurchase(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 amount);
    event Claim(address indexed to, uint256 amount);
    event PresaleStarted(uint256 startTime, uint256 endTime);
    event PresaleEnded(uint256 endTime);
    event WithdrawBNB(address indexed admin, uint256 amount);
    event WithdrawUSDC(address indexed admin, uint256 amount);
    event WithdrawTokens(address indexed admin, address indexed token, uint256 amount);
    event RateUpdated(uint256 oldRate, uint256 newRate);
    event MaxPurchaseUpdated(uint256 oldMax, uint256 newMax);
    event PresaleConfigured(uint256 startTime, uint256 endTime, uint256 rate, uint256 maxPurchase);

    modifier onlyAdmin() {
        require(admin == msg.sender, "caller is not the admin");
        _;
    }

    modifier presaleActive() {
        require(block.timestamp >= presaleStartTime, "Presale has not started yet");
        require(block.timestamp <= presaleEndTime, "Presale has ended");
        require(presaleActive, "Presale is not active");
        _;
    }

    constructor(
        uint256 _rate, 
        IST20 _token, 
        uint256 _max,
        uint256 _startTime,
        uint256 _endTime
    ) {
        require(_rate > 0, "Rate must be greater than 0");
        require(_max > 0, "Max purchase must be greater than 0");
        require(_token != IST20(address(0)), "Token address cannot be zero");
        require(_startTime > block.timestamp, "Start time must be in the future");
        require(_endTime > _startTime, "End time must be after start time");
        
        rate = _rate;
        token = _token;
        weiMaxPurchaseBnb = _max;
        presaleStartTime = _startTime;
        presaleEndTime = _endTime;
        presaleActive = false;
        admin = msg.sender;
        _admin = payable(admin);
        
        // Get token decimals
        tokenDecimals = token.decimals();
        require(tokenDecimals == 6 || tokenDecimals == 18, "Token must have 6 or 18 decimals");
        
        emit PresaleConfigured(_startTime, _endTime, _rate, _max);
    }

    fallback() external payable {
        revert("Direct payments not allowed");
    }

    receive() external payable {
        revert("Direct payments not allowed");
    }

    function getLatestPrice() public view returns (uint256) {
        (, int256 ethPrice, , , ) = AggregatorV3Interface(aggregatorInterface)
            .latestRoundData();
        ethPrice = (ethPrice * (10 ** 10));
        return uint256(ethPrice);
    }

    function ethBuyHelper(uint256 ethAmount) public view returns (uint256 amount) {
        amount = (ethAmount * getLatestPrice() * rate) / (1e6 * 10 ** 18);
    }

    function startPresale() external onlyAdmin {
        require(block.timestamp >= presaleStartTime, "Cannot start before scheduled time");
        require(!presaleActive, "Presale is already active");
        presaleActive = true;
        emit PresaleStarted(presaleStartTime, presaleEndTime);
    }

    function endPresale() external onlyAdmin {
        require(presaleActive, "Presale is not active");
        presaleActive = false;
        emit PresaleEnded(block.timestamp);
    }

    function buyTokens(address _beneficiary) public payable presaleActive {
        require(_beneficiary != address(0), "Beneficiary cannot be zero address");
        require(msg.value > 0, "Must send some BNB");
        
        uint256 maxBnbAmount = maxBnb(_beneficiary);
        uint256 weiAmount = msg.value > maxBnbAmount ? maxBnbAmount : msg.value;
        
        weiAmount = _preValidatePurchase(_beneficiary, weiAmount);
        uint256 tokens = _getTokenAmount(weiAmount);
        
        weiRaised = weiRaised.add(weiAmount);
        _updatePurchasingState(_beneficiary, weiAmount);
        
        emit TokenPurchase(msg.sender, _beneficiary, weiAmount, tokens);
        
        // Refund excess BNB
        if (msg.value > weiAmount) {
            uint256 refundAmount = msg.value.sub(weiAmount);
            payable(msg.sender).transfer(refundAmount);
        }
    }

    function buyTokensWithUSDC(address _beneficiary, uint256 usdcAmount) public presaleActive {
        require(_beneficiary != address(0), "Beneficiary cannot be zero address");
        require(usdcAmount > 0, "Must send some USDC");
        
        uint256 maxBnbAmount = maxBnb(_beneficiary);
        uint256 weiAmount = usdcAmount > maxBnbAmount ? maxBnbAmount : usdcAmount;
        
        weiAmount = _preValidatePurchase(_beneficiary, weiAmount);
        uint256 tokens = _getTokenAmount(weiAmount);
        
        weiRaised = weiRaised.add(weiAmount);
        _updatePurchasingStateUSDC(_beneficiary, weiAmount);
        
        emit TokenPurchase(msg.sender, _beneficiary, weiAmount, tokens);
        
        // Transfer USDC from user to contract
        require(
            IST20(USDCInterface).transferFrom(msg.sender, address(this), weiAmount),
            "USDC transfer failed"
        );
        
        // Refund excess USDC
        if (usdcAmount > weiAmount) {
            uint256 refundAmount = usdcAmount.sub(weiAmount);
            IST20(USDCInterface).transfer(msg.sender, refundAmount);
        }
    }

    function _preValidatePurchase(address _beneficiary, uint256 _weiAmount) public view returns (uint256) {
        require(_beneficiary != address(0), "Beneficiary cannot be zero address");
        require(_weiAmount > 0, "Amount must be greater than 0");
        
        uint256 tokenAmount = _getTokenAmount(_weiAmount);
        uint256 curBalance = token.balanceOf(address(this));
        
        if (tokenAmount > curBalance) {
            return curBalance.mul(10 ** 18).div(rate);
        }
        
        return _weiAmount;
    }

    function claimUserToken() public {
        uint256 userPurchased = purchasedBnb[msg.sender];
        require(userPurchased > 0, "No tokens purchased with BNB");
        require(claimedTokens[msg.sender] == 0, "Tokens already claimed");
        
        uint256 tokenAmount = _getTokenAmount(userPurchased);
        uint256 contractBalance = token.balanceOf(address(this));
        
        require(tokenAmount <= contractBalance, "Insufficient tokens in contract");
        
        claimedTokens[msg.sender] = tokenAmount;
        purchasedBnb[msg.sender] = 0;
        
        require(token.transfer(msg.sender, tokenAmount), "Token transfer failed");
        emit Claim(msg.sender, tokenAmount);
    }

    function claimUserTokenWithUSDC() public {
        uint256 userPurchased = purchasedUSDC[msg.sender];
        require(userPurchased > 0, "No tokens purchased with USDC");
        require(claimedTokens[msg.sender] == 0, "Tokens already claimed");
        
        uint256 tokenAmount = _getTokenAmount(userPurchased);
        uint256 contractBalance = token.balanceOf(address(this));
        
        require(tokenAmount <= contractBalance, "Insufficient tokens in contract");
        
        claimedTokens[msg.sender] = tokenAmount;
        purchasedUSDC[msg.sender] = 0;
        
        require(token.transfer(msg.sender, tokenAmount), "Token transfer failed");
        emit Claim(msg.sender, tokenAmount);
    }

    function getUSDCBalance() external view returns (uint256) {
        return IST20(USDCInterface).balanceOf(address(this));
    }

    function getTokenBalance() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    function getUserPurchased(address user) external view returns (uint256 bnbAmount, uint256 usdcAmount) {
        bnbAmount = purchasedBnb[user];
        usdcAmount = purchasedUSDC[user];
    }

    function getUserClaimed(address user) external view returns (uint256) {
        return claimedTokens[user];
    }

    function _deliverTokens(address _beneficiary, uint256 _tokenAmount) internal {
        token.transfer(_beneficiary, _tokenAmount);
    }

    function _processPurchase(address _beneficiary, uint256 _tokenAmount) internal {
        _deliverTokens(_beneficiary, _tokenAmount);
    }

    function _updatePurchasingState(address _beneficiary, uint256 _weiAmount) internal {
        purchasedBnb[_beneficiary] = _weiAmount.add(purchasedBnb[_beneficiary]);
    }
 
    function _updatePurchasingStateUSDC(address _beneficiary, uint256 _weiAmount) internal {
        purchasedUSDC[_beneficiary] = _weiAmount.add(purchasedUSDC[_beneficiary]);
    }

    function _getTokenAmount(uint256 _weiAmount) public view returns (uint256) {
        // Adjust calculation based on token decimals
        if (tokenDecimals == 18) {
            return _weiAmount.mul(rate).div(10 ** 18);
        } else {
            // For 6 decimals tokens
            return _weiAmount.mul(rate).div(10 ** 12);
        }
    }

    function setPresaleRate(uint256 _rate) external onlyAdmin {
        require(_rate > 0, "Rate must be greater than 0");
        uint256 oldRate = rate;
        rate = _rate;
        emit RateUpdated(oldRate, _rate);
    }

    function setMaxBNB(uint256 _max) external onlyAdmin {
        require(_max > 0, "Max purchase must be greater than 0");
        uint256 oldMax = weiMaxPurchaseBnb;
        weiMaxPurchaseBnb = _max;
        emit MaxPurchaseUpdated(oldMax, _max);
    }

    function setPresaleTiming(uint256 _startTime, uint256 _endTime) external onlyAdmin {
        require(_startTime > block.timestamp, "Start time must be in the future");
        require(_endTime > _startTime, "End time must be after start time");
        presaleStartTime = _startTime;
        presaleEndTime = _endTime;
        emit PresaleConfigured(_startTime, _endTime, rate, weiMaxPurchaseBnb);
    }

    function maxBnb(address _beneficiary) public view returns (uint256) {
        return weiMaxPurchaseBnb.sub(purchasedBnb[_beneficiary]);
    }

    function withdrawBalance() external onlyAdmin {
        uint256 bnbBalance = address(this).balance;
        uint256 usdcBalance = IST20(USDCInterface).balanceOf(address(this));
        
        if (bnbBalance > 0) {
            _admin.transfer(bnbBalance);
            emit WithdrawBNB(admin, bnbBalance);
        }
        
        if (usdcBalance > 0) {
            require(IST20(USDCInterface).transfer(admin, usdcBalance), "USDC transfer failed");
            emit WithdrawUSDC(admin, usdcBalance);
        }
    }
  
    function withdrawTokens(address tokenAddress, uint256 tokens) external onlyAdmin {
        require(tokenAddress != address(0), "Token address cannot be zero");
        require(tokens > 0, "Amount must be greater than 0");
        
        uint256 contractBalance = IST20(tokenAddress).balanceOf(address(this));
        require(tokens <= contractBalance, "Insufficient tokens in contract");
        
        require(IST20(tokenAddress).transfer(admin, tokens), "Token transfer failed");
        emit WithdrawTokens(admin, tokenAddress, tokens);
    }

    function getPresaleStatus() external view returns (
        bool active,
        uint256 startTime,
        uint256 endTime,
        uint256 currentTime,
        bool canStart,
        bool hasEnded
    ) {
        active = presaleActive;
        startTime = presaleStartTime;
        endTime = presaleEndTime;
        currentTime = block.timestamp;
        canStart = block.timestamp >= presaleStartTime && !presaleActive;
        hasEnded = block.timestamp > presaleEndTime;
    }
}