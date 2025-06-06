// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// OpenZeppelin Contracts (last updated v4.7.0) (utils/Address.sol)

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     * ====
     *
     * [IMPORTANT]
     * ====
     * You shouldn't rely on `isContract` to protect against flash loan attacks!
     *
     * Preventing calls from contracts is highly discouraged. It breaks composability, breaks support for smart wallets
     * like Gnosis Safe, and does not provide security since it can be circumvented by calling from a contract
     * constructor.
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize/address.code.length, which returns 0
        // for contracts in construction, since the code is only stored at the end
        // of the constructor execution.

        return account.code.length > 0;
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCall(target, data, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Tool to verifies that a low level call was successful, and revert if it wasn't, either by bubbling the
     * revert reason using the provided one.
     *
     * _Available since v4.3._
     */
    function verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly
                /// @solidity memory-safe-assembly
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}

// File: @openzeppelin/contracts/proxy/utils/Initializable.sol


// OpenZeppelin Contracts (last updated v4.7.0) (proxy/utils/Initializable.sol)


/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since proxied contracts do not make use of a constructor, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
 * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
 *
 * The initialization functions use a version number. Once a version number is used, it is consumed and cannot be
 * reused. This mechanism prevents re-execution of each "step" but allows the creation of new initialization steps in
 * case an upgrade adds a module that needs to be initialized.
 *
 * For example:
 *
 * [.hljs-theme-light.nopadding]
 * ```
 * contract MyToken is ERC20Upgradeable {
 *     function initialize() initializer public {
 *         __ERC20_init("MyToken", "MTK");
 *     }
 * }
 * contract MyTokenV2 is MyToken, ERC20PermitUpgradeable {
 *     function initializeV2() reinitializer(2) public {
 *         __ERC20Permit_init("MyToken");
 *     }
 * }
 * ```
 *
 * TIP: To avoid leaving the proxy in an uninitialized state, the initializer function should be called as early as
 * possible by providing the encoded function call as the `_data` argument to {ERC1967Proxy-constructor}.
 *
 * CAUTION: When used with inheritance, manual care must be taken to not invoke a parent initializer twice, or to ensure
 * that all initializers are idempotent. This is not verified automatically as constructors are by Solidity.
 *
 * [CAUTION]
 * ====
 * Avoid leaving a contract uninitialized.
 *
 * An uninitialized contract can be taken over by an attacker. This applies to both a proxy and its implementation
 * contract, which may impact the proxy. To prevent the implementation contract from being used, you should invoke
 * the {_disableInitializers} function in the constructor to automatically lock it when it is deployed:
 *
 * [.hljs-theme-light.nopadding]
 * ```
 * /// @custom:oz-upgrades-unsafe-allow constructor
 * constructor() {
 *     _disableInitializers();
 * }
 * ```
 * ====
 */
abstract contract Initializable {
    /**
     * @dev Indicates that the contract has been initialized.
     * @custom:oz-retyped-from bool
     */
    uint8 private _initialized;

    /**
     * @dev Indicates that the contract is in the process of being initialized.
     */
    bool private _initializing;

    /**
     * @dev Triggered when the contract has been initialized or reinitialized.
     */
    event Initialized(uint8 version);

    /**
     * @dev A modifier that defines a protected initializer function that can be invoked at most once. In its scope,
     * `onlyInitializing` functions can be used to initialize parent contracts. Equivalent to `reinitializer(1)`.
     */
    modifier initializer() {
        bool isTopLevelCall = !_initializing;
        require(
            (isTopLevelCall && _initialized < 1) || (!Address.isContract(address(this)) && _initialized == 1),
            "Initializable: contract is already initialized"
        );
        _initialized = 1;
        if (isTopLevelCall) {
            _initializing = true;
        }
        _;
        if (isTopLevelCall) {
            _initializing = false;
            emit Initialized(1);
        }
    }

    /**
     * @dev A modifier that defines a protected reinitializer function that can be invoked at most once, and only if the
     * contract hasn't been initialized to a greater version before. In its scope, `onlyInitializing` functions can be
     * used to initialize parent contracts.
     *
     * `initializer` is equivalent to `reinitializer(1)`, so a reinitializer may be used after the original
     * initialization step. This is essential to configure modules that are added through upgrades and that require
     * initialization.
     *
     * Note that versions can jump in increments greater than 1; this implies that if multiple reinitializers coexist in
     * a contract, executing them in the right order is up to the developer or operator.
     */
    modifier reinitializer(uint8 version) {
        require(!_initializing && _initialized < version, "Initializable: contract is already initialized");
        _initialized = version;
        _initializing = true;
        _;
        _initializing = false;
        emit Initialized(version);
    }

    /**
     * @dev Modifier to protect an initialization function so that it can only be invoked by functions with the
     * {initializer} and {reinitializer} modifiers, directly or indirectly.
     */
    modifier onlyInitializing() {
        require(_initializing, "Initializable: contract is not initializing");
        _;
    }

    /**
     * @dev Locks the contract, preventing any future reinitialization. This cannot be part of an initializer call.
     * Calling this in the constructor of a contract will prevent that contract from being initialized or reinitialized
     * to any version. It is recommended to use this to lock implementation contracts that are designed to be called
     * through proxies.
     */
    function _disableInitializers() internal virtual {
        require(!_initializing, "Initializable: contract is initializing");
        if (_initialized < type(uint8).max) {
            _initialized = type(uint8).max;
            emit Initialized(type(uint8).max);
        }
    }
}

// File: @openzeppelin/contracts/security/ReentrancyGuard.sol


// OpenZeppelin Contracts v4.4.1 (security/ReentrancyGuard.sol)


/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }
}

// File: @openzeppelin/contracts/utils/Context.sol


// OpenZeppelin Contracts v4.4.1 (utils/Context.sol)


/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

// File: @openzeppelin/contracts/access/Ownable.sol


// OpenZeppelin Contracts (last updated v4.7.0) (access/Ownable.sol)


/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

// File: @openzeppelin/contracts/token/ERC20/IERC20.sol


// OpenZeppelin Contracts (last updated v4.6.0) (token/ERC20/IERC20.sol)

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `from` to `to` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

contract TokenStaking is Ownable, ReentrancyGuard {
    // Struct to store the User's Details
    struct User {
        uint256 stakeAmount; // Stake Amount wei
        uint256 rewardAmount; // Reward Amount
        uint256 lastStakeTime; // Last Stake Timestamp
        uint256 lastRewardCalculationTime; // Last Reward Calculation Timestamp
        uint256 rewardsClaimedSoFar; // Sum of rewards claimed so far
        uint stakeDays; // staking days
        uint256 stakeStartDate; // start date for program
        uint256 stakeEndDate; // end date for program        
    }

    uint256 _minimumStakingAmount; // minimum staking amount

    uint256 _maxStakeTokenLimit; // maximum staking token limit for program

    uint256 _totalStakedTokens; // Total no of tokens that are staked

    uint256 _totalUsers; // Total no of users

//////////////////////////////////////////////////////////////////
// 10 K x TOKEN C-SHARE GLOBAL
    uint256 C_SHARE_GLOBAL = 10000;

/////////////////////////////////////////////
  uint256 _totalPaidTokens = 0; // Total paid tokens   


    uint256 public constant REWARD_RATE = 10000000000000000; //    0.01

    uint256 public s_rewardPerTokenStored;

    //uint256 _stakeDays; 
    // staking days
    uint256 _earlyUnstakeFeePercentage; // early unstake fee percentage

    bool _isStakingPaused; // staking status

    // Token contract address
    address private _tokenAddress;

    // APY
    uint256 _apyRate;

    uint256 public constant PERCENTAGE_DENOMINATOR = 10000;
    uint256 public constant APY_RATE_CHANGE_THRESHOLD = 10;

    // User address => User
    mapping(address => User) private _users;

    event Stake(address indexed user, uint256 amount);
    event UnStake(address indexed user, uint256 amount);
    event EarlyUnStakeFee(address indexed user, uint256 amount);
    event ClaimReward(address indexed user, uint256 amount);

    modifier whenTreasuryHasBalance(uint256 amount) {
        require(
            IERC20(_tokenAddress).balanceOf(address(this)) >= amount,
            "TokenStaking: insufficient funds in the treasury"
        );
        _;
    }

// 2000000000000000000000 = 2000% APY 

//   0xDd565537c63CfBb8899617644AAB1B7CA423ee40,2000,1,100000,25
   constructor(address tokenAddress,
        uint256 apyRate,
        uint256 minimumStakingAmount,
        uint256 maxStakeTokenLimit,
        uint256 earlyUnstakeFeePercentage) {
           // require(apyRate <= 10000, "TokenStaking: apy rate should be less than 10000");
            require(tokenAddress != address(0), "TokenStaking: token address cannot be 0 address");
        
            _tokenAddress = tokenAddress;
            //owner = msg.sender;
            _apyRate = apyRate;
            _minimumStakingAmount = minimumStakingAmount;
            _maxStakeTokenLimit = maxStakeTokenLimit;
            _earlyUnstakeFeePercentage = earlyUnstakeFeePercentage;
    }




    /* View Methods Start */

    /**
     * @notice This function is used to get the minimum staking amount
     */
    function getMinimumStakingAmount() external view returns (uint256) {
        return _minimumStakingAmount;
    }

    /**
     * @notice This function is used to get the maximum staking token limit for program
     */
    function getMaxStakingTokenLimit() external view returns (uint256) {
        return _maxStakeTokenLimit;
    }

    /**
     * @notice This function is used to get the staking start date for program
     */
    function getStakeStartDate(address _address) external view returns (uint256) {
        return _users[_address].stakeStartDate;
    }

    /**
     * @notice This function is used to get the staking end date for program
     */
    function getStakeEndDate(address _address) external view returns (uint256) {
        return _users[_address].stakeEndDate;
    }

    /**
     * @notice This function is used to get the total no of tokens that are staked
     */
    function getTotalStakedTokens() external view returns (uint256) {
        return _totalStakedTokens;
    }

    /**
     * @notice This function is used to get the total no of users
     */
    function getTotalUsers() external view returns (uint256) {
        return _totalUsers;
    }

    /**
     * @notice This function is used to get stake days
     */
    function getStakeDays(address _address) external view returns (uint256) {
        return _users[_address].stakeDays;
    }

    /**
     * @notice This function is used to get early unstake fee percentage
     */
    function getEarlyUnstakeFeePercentage() external view returns (uint256) {
        return _earlyUnstakeFeePercentage;
    }

    /**
     * @notice This function is used to get staking status
     */
    function getStakingStatus() external view returns (bool) {
        return _isStakingPaused;
    }

    /**
     * @notice This function is used to get the current APY Rate
     * @return Current APY Rate
     */
    function getAPY() external view returns (uint256) {
        return _apyRate;
    }

    /**
     * @notice This function is used to get msg.sender's estimated reward amount
     * @return msg.sender's estimated reward amount
     */
    function getUserEstimatedRewards() external view returns (uint256) {
        (uint256 amount, ) = _getUserEstimatedRewards(msg.sender);
        return _users[msg.sender].rewardAmount + amount;
    }

    /**
     * @notice This function is used to get withdrawable amount from contract
     */
    function getWithdrawableAmount() external view returns (uint256) {
        return IERC20(_tokenAddress).balanceOf(address(this)) - _totalStakedTokens * 1e18;
    }

     /**
     * @notice This function is used to get amount from ERC20 Treasury
     * used for staking rewards
     */
    function getTreasuryAmount() external view returns (uint256) {
        return IERC20(_tokenAddress).balanceOf(address(this));
    }

    /**
     * @notice This function is used to get User's details
     * @param userAddress User's address to get details of
     * @return User Struct
     */
    function getUser(address userAddress) external view returns (User memory) {
        return _users[userAddress];
    }

    /**
     * @notice This function is used to check if a user is a stakeholder
     * @param _user Address of the user to check
     * @return True if user is a stakeholder, false otherwise
     */
    function isStakeHolder(address _user) external view returns (bool) {
        return _users[_user].stakeAmount != 0;
    }
///////////////////////////////////////////////////////////
// BONUS FORMULAS TOKENS B
  function _getBonusQuantity(uint256 tokens) private pure returns(uint256) {
      uint256 amount = 0;
       if ( tokens <= 150000000* 1e18 ) amount = tokens/(1500000000* 1e18); //1.5B
       else amount = tokens + (tokens*10)/100;
       return amount;
  }
  function getBonusQuantity(uint256 tokens) external pure returns (uint256) {
        return _getBonusQuantity(tokens);
  }

  function _getBonusTime(uint256 tokens,uint bdays) private pure returns(uint256) {     uint256 amount = 0;
       if ( bdays <= 3641 ) amount = tokens * (bdays-1) / 1820* 1e18;
       else amount = tokens * 3 ; 
       return amount;
  }
  function getBonusTime(uint256 tokens,uint bdays ) external pure returns (uint256) {
        return _getBonusTime(tokens, bdays);
   }

// TOKENS C total efective tokens
  function _getUserTokensC() private view returns(uint256) {

        (uint256 amount, ) = _getUserEstimatedRewards(msg.sender);
        uint256 _stakeAmount = _users[msg.sender].stakeAmount;
        uint _bdays = _users[msg.sender].stakeDays;
        uint256 bonusQ = _getBonusQuantity(_stakeAmount);
        uint256 bonusT = _getBonusTime(_stakeAmount,_bdays);
        return (_users[msg.sender].rewardAmount + amount) + bonusQ + bonusT;
    }
   function getUserTokensC() external view returns (uint256) {
        uint256 amount = _getUserTokensC();
        return amount;
    }

// DAILY E-POOL TOKENS SHARE
   function getDailyEpool() external view returns (uint256) {
        uint256 _ctokens = _getUserTokensC();
        uint256 amount = _ctokens * (0.01 * 1e18) / _totalStakedTokens;
        return amount;
    }

   function getLateStakeAmount() external view returns (uint256) {
        uint256 _ctokens = _getUserTokensC();
        uint256 amount = _ctokens * (0.125 * 1e18) / 100;
        return amount;
    }   

  function getUpdatedCShareValue() external returns (uint256) {
        uint256 _min = 150000000;//150M for tokens
        uint _min2 = 3640; //for days
        uint256 _ctokens = _getUserTokensC();
        if ( _totalPaidTokens < 150000000 ) _min = _totalPaidTokens; //150M
        if ( _users[msg.sender].stakeDays < 3640 ) _min2 = _users[msg.sender].stakeDays -1;
        uint256 _tot = (1500000000+_min) * _totalPaidTokens / ((1820 * _ctokens)/(1820+_min2) * 1500000000);  //1500M
        if ( _tot > C_SHARE_GLOBAL ) C_SHARE_GLOBAL = _tot;
        return _tot;
    }   

////////////////////////////////////////////////////////////
    /* View Methods End */

    /* Owner Methods Start */

    /**
     * @notice This function is used to update minimum staking amount
     */
    function updateMinimumStakingAmount(uint256 newAmount) external onlyOwner {
        _minimumStakingAmount = newAmount;
    }

    /**
     * @notice This function is used to update maximum staking amount
     */
    function updateMaximumStakingAmount(uint256 newAmount) external onlyOwner {
        _maxStakeTokenLimit = newAmount;
    }

  
    /**
     * @notice This function is used to update early unstake fee percentage
     */
    function updateEarlyUnstakeFeePercentage(uint256 newPercentage) external onlyOwner {
        _earlyUnstakeFeePercentage = newPercentage;
    }

   

    /**
     * @notice enable/disable staking
     * @dev This function can be used to toggle staking status
     */
    function toggleStakingStatus() external onlyOwner {
        _isStakingPaused = !_isStakingPaused;
    }

    /**
     * @notice Withdraw the specified amount if possible.
     *
     * @dev This function can be used to withdraw the available tokens
     * with this contract to the caller
     *
     * @param amount the amount to withdraw
     */
    function withdraw(uint256 amount) external onlyOwner nonReentrant {
        require(this.getWithdrawableAmount() >= amount, "TokenStaking: not enough withdrawable tokens");
        IERC20(_tokenAddress).transfer(msg.sender, amount);
    }

    /* Owner Methods End */

    /* User Methods Start */

     /**
     * @notice stake tokens for specific user
     * @dev This function can be used to stake tokens for specific user
     *
     * @param amount the amount to stake
     * @param user user's address
     */
    function stakeForUser(uint256 amount, address user, uint _days) external onlyOwner nonReentrant {
        _stakeTokens(amount, user, _days);
    }

    /**
     * @notice This function is used to stake tokens
     * @param _amount Amount of tokens to be staked
     */
    function stake(uint256 _amount, uint _days) external nonReentrant {
        _stakeTokens(_amount, msg.sender, _days);
    }

    function _stakeTokens(uint256 _amount, address user_, uint _days) private {
        require(!_isStakingPaused, "TokenStaking: staking is paused");

        uint256 currentTime = getCurrentTime();
        //require(currentTime > _stakeStartDate, "TokenStaking: staking not started yet");
        //require(currentTime < _stakeEndDate, "TokenStaking: staking ended");
        require(_amount <= _maxStakeTokenLimit, "TokenStaking: max staking token limit reached");
        require(_amount > 0, "TokenStaking: stake amount must be non-zero");
        require(
            _amount >= _minimumStakingAmount,
            "TokenStaking: stake amount must greater than minimum amount allowed"
        );

        if (_users[user_].stakeAmount != 0) {
            _calculateRewards(user_);
        } else {
            _users[user_].lastRewardCalculationTime = currentTime;
            _totalUsers += 1;
        }

        _users[user_].stakeAmount += _amount;
        _users[user_].lastStakeTime = currentTime;
        _users[user_].stakeStartDate = currentTime;
        _users[user_].stakeEndDate = (currentTime + _days * 1 days);
        _users[user_].stakeDays =_days;
        

        _totalStakedTokens += _amount;

        require(
            IERC20(_tokenAddress).transferFrom(msg.sender, address(this), _amount * 1e18),
            "TokenStaking: failed to transfer tokens"
        );
        emit Stake(user_, _amount);

//*************************************************
// BURN THE INITIAL TOKENS
   require(IERC20(_tokenAddress).transfer(address(0),  _amount * 1e18), "TokenStaking: failed to burn");

    }

    /**
     * @notice This function is used to unstake tokens
     * @param _amount Amount of tokens to be unstaked
     */
    function unstake(uint256 _amount) external nonReentrant whenTreasuryHasBalance(_amount) {
        address user = msg.sender;

        require(_amount != 0, "TokenStaking: amount should be non-zero");
        require(this.isStakeHolder(user), "TokenStaking: not a stakeholder");
        require(_users[user].stakeAmount >= _amount, "TokenStaking: not enough stake to unstake");

        // Calculate User's rewards until now
        _calculateRewards(user);

      

        uint256 amountToUnstake = _amount; // - feeEarlyUnstake;

        _users[user].stakeAmount -= _amount;

        _totalStakedTokens -= _amount;

        if (_users[user].stakeAmount == 0) {
            // delete _users[user];
            _totalUsers -= 1;
        }

        require(IERC20(_tokenAddress).transfer( msg.sender, amountToUnstake * 1e18), "TokenStaking: failed to transfer");
        emit UnStake(user, _amount);
    }

    /**
     * @notice This function is used to claim user's rewards
     * Note: The called function should be payable if you send value 
     */
    function claimReward() external nonReentrant whenTreasuryHasBalance(_users[msg.sender].rewardAmount) {
        _calculateRewards(msg.sender);
        uint256 rewardAmount = _users[msg.sender].rewardAmount;

        require(rewardAmount > 0, "TokenStaking: no reward to claim");

        uint256 feeEarlyUnstake = 0;

        // Calculate early unstake fee % based on stakedays
        /////////////////////////////////////////////////////////////////////////
        
        if (getCurrentTime() <= _users[msg.sender].lastStakeTime +  _users[msg.sender].stakeDays * 1 days) {
            uint256 _lastStakeTime = _users[msg.sender].lastStakeTime;
            uint256 _stakeTimeSoFar = (getCurrentTime() -_users[msg.sender].lastStakeTime);
            uint256 _stake50 = (_users[msg.sender].stakeDays * 50) /100;
            uint256 _rewardxday = (rewardAmount / ( _stakeTimeSoFar * 1 days));            

            if ( _lastStakeTime * 1 days<180 ) {
                if ( _lastStakeTime * 1 days == 0 ) feeEarlyUnstake = 0;
                else if ( _lastStakeTime * 1 days < 90 ) feeEarlyUnstake = (rewardAmount * 90) / _stakeTimeSoFar;
                else if ( _lastStakeTime * 1 days == 90 ) feeEarlyUnstake = rewardAmount;
                else if ( _lastStakeTime * 1 days > 90 )  {
                    uint256 _gt90diff = ( _stakeTimeSoFar * 1 days) - 90 ;
                    uint256 _gt90feedays = ( _stakeTimeSoFar * 1 days) - _gt90diff;
                    uint256 _gt90fee = _gt90feedays * _rewardxday;
                    feeEarlyUnstake = _gt90fee;
                }
            } else if ( _lastStakeTime * 1 days>=180) {
                if ( _lastStakeTime * 1 days == 0 ) feeEarlyUnstake = 0;
                else if ( _stakeTimeSoFar * 1 days < _stake50 ) feeEarlyUnstake = (rewardAmount * _stake50) / _stakeTimeSoFar;
                else if ( _stakeTimeSoFar * 1 days == _stake50 ) feeEarlyUnstake = rewardAmount;
                else if ( _stakeTimeSoFar * 1 days > _stake50 )  {
                    // calculate remaining days after 50% time completed
                    // and get percentage return for fee early stake
                    uint256 _remainingDays = ( _stakeTimeSoFar * 1 days) - _stake50;
                    uint256 _feeEarlyAfter50 = (_remainingDays / (_stakeTimeSoFar * 1 days)) * 100;
                    feeEarlyUnstake = (rewardAmount * _feeEarlyAfter50) / 100;
                }
            }
           
            if ( feeEarlyUnstake>0 ) {
                // burn 25% of fees
                uint256 _burn25 = (feeEarlyUnstake * 25) / 100;
                require(IERC20(_tokenAddress).transfer(address(0), _burn25), "TokenStaking: failed to burn");
                emit EarlyUnStakeFee(msg.sender, _burn25);
            } 
           
          
        } else {
            // Calculate rewards
            (uint256 amount, ) = _getUserEstimatedRewards(msg.sender);
            rewardAmount = amount;  
            
        }

        rewardAmount = rewardAmount - feeEarlyUnstake; 

        require(IERC20(_tokenAddress).transfer(msg.sender, rewardAmount), "TokenStaking: failed to transfer");
     
        /////////////////////////////////
        // UPDATE TOTAL PAID TOKENS   
        _totalPaidTokens = _totalPaidTokens + rewardAmount;

        _users[msg.sender].rewardAmount = 0;
        _users[msg.sender].rewardsClaimedSoFar += rewardAmount;

        emit ClaimReward(msg.sender, rewardAmount);
    }

    /* User Methods End */

    /* Private Helper Methods Start */

    /**
     * @notice This function is used to calculate rewards for a user
     * @param _user Address of the user
     */
    function _calculateRewards(address _user) private {
        (uint256 userReward, uint256 currentTime) = _getUserEstimatedRewards(_user);

        _users[_user].rewardAmount += userReward;
        _users[_user].lastRewardCalculationTime = currentTime;
    }

    /**
     * @notice This function is used to get estimated rewards for a user
     * @param _user Address of the user
     * @return Estimated rewards for the user
     */
    function _getUserEstimatedRewards(address _user) private view returns (uint256, uint256) {
        uint256 userReward;
        //uint256 userTimestamp = _users[_user].lastRewardCalculationTime;

        uint256 currentTime = getCurrentTime();

        if (currentTime > _users[_user].lastStakeTime + _users[_user].stakeDays * 1 days) {
            currentTime = _users[_user].lastStakeTime + _users[_user].stakeDays * 1 days;
        }

        //uint256 totalStakedTime = currentTime - userTimestamp;
        uint256 currentRewardPerToken = rewardPerToken();

//      userReward += ((totalStakedTime * _users[_user].stakeAmount * REWARD_RATE * 1e18) / _totalStakedTokens);
        
        userReward += ( (_users[_user].stakeAmount * 1e18) * currentRewardPerToken ) / 1e18;

        return (userReward, currentTime);
    }

/*

 // contract emits X reward tokens per second
        // disperse tokens to all token stakers
        // reward emission != 1:1
        // MATH
        // @ 100 tokens / second (REWARD_RATE)
        // @ Time = 0
        // Person A: 80 staked
        // Preson B: 20 staked
        // @ Time = 1
        // Person A: 80 staked, Earned: 80, Withdraw 0
        // Perosn B: 20 staked, Earned: 20, Withdraw: 0
        // @ Time = 2
        // Person A: 80 staked, Earned: 160, Withdraw 0
        // Person B: 20 staked, Earned: 40, Withdraw: 0

*/

        /** @dev Basis of how long it's been during the most recent snapshot/block */
    function rewardPerToken() public view returns (uint256) {
        if (_totalStakedTokens == 0) {
            return s_rewardPerTokenStored;
        } else {
            uint256 userTimestamp = _users[msg.sender].lastRewardCalculationTime;            
            return
                s_rewardPerTokenStored +
                (((block.timestamp - userTimestamp) * REWARD_RATE) / _totalStakedTokens);
        }
    }

    /* Private Helper Methods End */

    function getCurrentTime() internal view virtual returns (uint256) {
        return block.timestamp;
    }
}