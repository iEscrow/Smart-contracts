// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// =======================================
// === BEGIN: OpenZeppelin (librerías) ===
// =======================================

// OpenZeppelin Contracts (last updated v4.7.0) (utils/Address.sol)
/**
 * @dev Collection of functions related to the address type
 */
library Address {
    function isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }

    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");
        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCall(target, data, "Address: low-level call failed");
    }

    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

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

    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    function functionDelegateCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    function verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Si hubo "revert reason" en returndata, se hace revert con ese reason
            if (returndata.length > 0) {
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

// OpenZeppelin Contracts (last updated v4.7.0) (proxy/utils/Initializable.sol)
abstract contract Initializable {
    uint8 private _initialized;
    bool private _initializing;
    event Initialized(uint8 version);

    modifier initializer() {
        bool isTopLevelCall = !_initializing;
        require(
            (isTopLevelCall && _initialized < 1) ||
            (!Address.isContract(address(this)) && _initialized == 1),
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

    modifier reinitializer(uint8 version) {
        require(!_initializing && _initialized < version, "Initializable: contract is already initialized");
        _initialized = version;
        _initializing = true;
        _;
        _initializing = false;
        emit Initialized(version);
    }

    modifier onlyInitializing() {
        require(_initializing, "Initializable: contract is not initializing");
        _;
    }

    function _disableInitializers() internal virtual {
        require(!_initializing, "Initializable: contract is initializing");
        if (_initialized < type(uint8).max) {
            _initialized = type(uint8).max;
            emit Initialized(type(uint8).max);
        }
    }
}

// OpenZeppelin Contracts v4.4.1 (security/ReentrancyGuard.sol)
abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

// OpenZeppelin Contracts v4.4.1 (utils/Context.sol)
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

// OpenZeppelin Contracts (last updated v4.7.0) (access/Ownable.sol)
abstract contract Ownable is Context {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    constructor() {
        _transferOwnership(_msgSender());
    }
    modifier onlyOwner() {
        _checkOwner();
        _;
    }
    function owner() public view virtual returns (address) {
        return _owner;
    }
    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

// OpenZeppelin Contracts (last updated v4.6.0) (token/ERC20/IERC20.sol)
interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

// =====================================
// ===  END: OpenZeppelin (librerías)  ===
// =====================================


// ****************************************************************
// ************************ COMIENZA TokenStaking *****************
// ****************************************************************

/// @dev Extended ERC20 interface para soportar minting al deshacer stake.
interface IMintableERC20 is IERC20 {
    function mint(address to, uint256 amount) external;
}

contract TokenStaking is Ownable, ReentrancyGuard {
    // ===================================================
    // === CONSTANTES PARA QUEMA DE TOKENS ===
    // ===================================================
    address private constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    // -------------------------------------------
    // === 1) Estructura "User" original (monostake) ===
    // -------------------------------------------
    // La conservamos, pero ya no almacenará el stake "global",
    // sino solo campos necesarios para seguimiento de rewards. 
    // El "stakeAmount" y fechas originales se reemplazan por un array de stakes.
    struct User {
        uint256 rewardAmount;            // recompensa acumulada pending
        uint256 lastRewardCalculationTime; 
        uint256 rewardsClaimedSoFar;     
        // Los campos stakeAmount, lastStakeTime, stakeDays, stakeStartDate, stakeEndDate
        // se eliminan (se reemplazan con StakeInfo[]). 
    }

    // ------------------------------------------------
    // === 2) Nueva estructura para cada stake individual ===  (multi-stake)
    // ------------------------------------------------
    struct StakeInfo {
        uint256 amount;                 // cantidad stakeada (sin decimales)
        uint256 start;                  // timestamp de inicio
        uint256 end;                    // timestamp de fin (start + daysStaked * 1 days)
        uint256 daysStaked;             // días elegidos
        uint256 lastRewardCalculation;  // último cálculo de reward para este stake
        uint256 rewardAmount;           // reward acumulada (pendiente de cobrar) para este stake 
    }

    // -----------------------------------------
    // === 3) Mappings originales / nuevos mappings ===
    // -----------------------------------------
    // Antes:
    // mapping(address => User) private _users;
    // mapping(address => User) private _users;
    mapping(address => User) private _users;                      // sigue existiendo para trackear rewards "globales" del usuario, si hace falta
    
    // Nuevo: cada usuario puede tener varios stakes
    mapping(address => StakeInfo[]) private _stakes;             // *** CAMBIO
    
    // Para tracking de usuarios activos (distribución diaria)
    address[] private _activeUsers;                              // Array de usuarios activos
    mapping(address => bool) private _isActiveUser;              // Mapping para verificar si es usuario activo
    mapping(address => uint256) private _userIndex;              // Índice en el array _activeUsers

    // ----------------------------------------
    // === 4) Variables de estado (casi igual al original) ===
    // ----------------------------------------
    uint256 _minimumStakingAmount;       // mínimo a stakear
    uint256 _maxStakeTokenLimit;         // máximo a stakear
    uint256 _totalStakedTokens;          // total de tokens actualmente stakeados
    uint256 _totalUsers;                 // total de usuarios con al menos 1 stake
    uint256 _totalPaidTokens = 0;        // total de tokens pagados en rewards

    // === C-SHARE GLOBAL ===
    uint256 C_SHARE_GLOBAL = 10000;       // 10 K tokens (valor inicial)
    
    uint256 public constant REWARD_RATE = 10000000000000000; // 0.01 (idéntico al original: 0.01 tokens/seg)
    uint256 public s_rewardPerTokenStored;                    // mismo nombre, pero en la práctica ya no lo usamos exactamente igual

    uint256 _earlyUnstakeFeePercentage;    // % de penalización temprana (igual que antes)
    bool _isStakingPaused;                 // si staking está pausado
    address private _tokenAddress;         // dirección del token
    uint256 _apyRate;                      // APY (igual que antes)

    uint256 public constant PERCENTAGE_DENOMINATOR = 10000; 
    uint256 public constant APY_RATE_CHANGE_THRESHOLD = 10;  // igual que original (aunque no se usa explícitamente)

    // ------------------------------------
    // === 5) Eventos (prácticamente iguales) ===
    // ------------------------------------
    event Stake(address indexed user, uint256 amount);                   // se sigue emitiendo cuando se hace stake
    event UnStake(address indexed user, uint256 amount);                 // se emite al deshacer stake
    event EarlyUnStakeFee(address indexed user, uint256 amount);         // se emite cuando se quema parte de la fee
    event ClaimReward(address indexed user, uint256 amount);             // se emite cuando se cobra reward

    // =====================================================
    // === 6) Modifier original "whenTreasuryHasBalance" ===
    // =====================================================
    modifier whenTreasuryHasBalance(uint256 amount) {
        require(
            IERC20(_tokenAddress).balanceOf(address(this)) >= amount,
            "TokenStaking: insufficient funds in the treasury"
        );
        _;
    }

    // =====================================================
    // === 7) Constructor (idéntico al original) =============
    // =====================================================
    constructor(
        address tokenAddress,
        uint256 apyRate,
        uint256 minimumStakingAmount,
        uint256 maxStakeTokenLimit,
        uint256 earlyUnstakeFeePercentage
    ) {
        require(tokenAddress != address(0), "TokenStaking: token address cannot be 0 address");
        _tokenAddress = tokenAddress;
        _apyRate = apyRate;
        _minimumStakingAmount = minimumStakingAmount;
        _maxStakeTokenLimit = maxStakeTokenLimit;
        _earlyUnstakeFeePercentage = earlyUnstakeFeePercentage;
    }

    // ======================================
    // === 8) VIEW METHODS (se mantienen) ===
    // ======================================
    function getMinimumStakingAmount() external view returns (uint256) {
        return _minimumStakingAmount;
    }

    function getMaxStakingTokenLimit() external view returns (uint256) {
        return _maxStakeTokenLimit;
    }

    function getStakeStartDate(address _address) external view returns (uint256) {
        // *** CAMBIO: ahora que puede haber varios stakes, devolvemos la fecha de inicio
        // del primer stake activo (índice 0) si existe, o 0 si no hay stakes.
        StakeInfo[] storage arr = _stakes[_address];
        if (arr.length == 0) {
            return 0;
        }
        return arr[0].start;
    }

    function getStakeEndDate(address _address) external view returns (uint256) {
        // *** CAMBIO: devuelve el 'end' del primer stake activo (índice 0), o 0 si no hay.
        StakeInfo[] storage arr = _stakes[_address];
        if (arr.length == 0) {
            return 0;
        }
        return arr[0].end;
    }

    function getTotalStakedTokens() external view returns (uint256) {
        return _totalStakedTokens;
    }

    function getTotalUsers() external view returns (uint256) {
        return _totalUsers;
    }

    function getStakeDays(address _address) external view returns (uint256) {
        // *** CAMBIO: devolvemos daysStaked del primer stake (índice 0) si existe; 0 si no.
        StakeInfo[] storage arr = _stakes[_address];
        if (arr.length == 0) {
            return 0;
        }
        return arr[0].daysStaked;
    }

    function getEarlyUnstakeFeePercentage() external view returns (uint256) {
        return _earlyUnstakeFeePercentage;
    }

    function getStakingStatus() external view returns (bool) {
        return _isStakingPaused;
    }

    function getAPY() external view returns (uint256) {
        return _apyRate;
    }

    function getUserEstimatedRewards() external view returns (uint256) {
        // *** CAMBIO: sumamos rewardAmount "global" almacenado en _users + reward pendientede calcular en cada stake
        uint256 globalStored = _users[msg.sender].rewardAmount;
        uint256 accumulated = 0;
        StakeInfo[] storage arr = _stakes[msg.sender];
        for (uint256 i = 0; i < arr.length; i++) {
            // calcular reward pendientede cada stake (similar a _getUserEstimatedRewards en original)
            uint256 currentTime = block.timestamp;
            uint256 effectiveEnd = currentTime > arr[i].end ? arr[i].end : currentTime;
            uint256 elapsed = effectiveEnd - arr[i].lastRewardCalculation;
            if (_totalStakedTokens > 0) {
                uint256 rewardPerSec = (REWARD_RATE * arr[i].amount * 1e18) / _totalStakedTokens;
                uint256 pending = (elapsed * rewardPerSec) / 1e18 + arr[i].rewardAmount;
                accumulated += pending;
            }
        }
        return globalStored + accumulated;
    }

    function getWithdrawableAmount() external view returns (uint256) {
        return IERC20(_tokenAddress).balanceOf(address(this)) - _totalStakedTokens * 1e18;
    }

    function getTreasuryAmount() external view returns (uint256) {
        return IERC20(_tokenAddress).balanceOf(address(this));
    }

    function getUser(address userAddress) external view returns (User memory) {
        return _users[userAddress];
    }

    function isStakeHolder(address _user) external view returns (bool) {
        return _stakes[_user].length > 0;   // *** CAMBIO: ahora es true si tiene al menos 1 stake
    }

    // ================================
    // === BONUS FORMULAS (idénticas) ===
    // ================================
    function _getBonusQuantity(uint256 tokens) private pure returns (uint256) {
        uint256 amount = 0;
        if (tokens <= 150000000 * 1e18) {
            amount = tokens / (1500000000 * 1e18); // 1.5 B
        } else {
            amount = tokens + (tokens * 10) / 100;
        }
        return amount;
    }

    function getBonusQuantity(uint256 tokens) external pure returns (uint256) {
        return _getBonusQuantity(tokens);
    }

    function _getBonusTime(uint256 tokens, uint bdays) private pure returns (uint256) {
        uint256 amount = 0;
        if (bdays <= 3641) {
            amount = (tokens * (bdays - 1)) / 1820 * 1e18;
        } else {
            amount = tokens * 3;
        }
        return amount;
    }

    function getBonusTime(uint256 tokens, uint bdays) external pure returns (uint256) {
        return _getBonusTime(tokens, bdays);
    }

    // ======================================================
    // === 9) MÉTODOS NUEVOS para tokens "C" y C-Share etc. ===
    // ======================================================
    // Estos métodos no existían en el original, los agregamos justo aquí:

    /// @notice Devuelve los tokens "C" efectivos de un stake específico
    function _getUserTokensC(address user, uint256 stakeIndex) private view returns (uint256) {
        StakeInfo storage s = _stakes[user][stakeIndex];

        uint256 currentTime = block.timestamp;
        if (currentTime > s.end) {
            currentTime = s.end;
        }
        uint256 elapsed = currentTime - s.lastRewardCalculation;
        uint256 pendingReward = 0;
        if (_totalStakedTokens > 0) {
            uint256 rewardPerSec = (REWARD_RATE * s.amount * 1e18) / _totalStakedTokens;
            pendingReward = (elapsed * rewardPerSec) / 1e18 + s.rewardAmount;
        }

        uint256 bonusQ = _getBonusQuantity(s.amount);
        uint256 bonusT = _getBonusTime(s.amount, s.daysStaked);
        return pendingReward + bonusQ + bonusT;
    }

    /// @notice Función pública para obtener C-Shares de un stake específico
    function getStakeTokensC(address user, uint256 stakeIndex) external view returns (uint256) {
        require(stakeIndex < _stakes[user].length, "TokenStaking: invalid stake index");
        return _getUserTokensC(user, stakeIndex);
    }

    /// @notice Devuelve la suma de todos los tokens "C" de un usuario (todos sus stakes)
    function getUserTokensC(address user) external view returns (uint256) {
        uint256 totalC = 0;
        StakeInfo[] storage arr = _stakes[user];
        for (uint256 i = 0; i < arr.length; i++) {
            totalC += _getUserTokensC(user, i);
        }
        return totalC;
    }

    /// @notice Daily E-Pool = userCtoks * (0.01 * 1e18) / _totalStakedTokens
    function getDailyEpool(address user) external view returns (uint256) {
        uint256 userCtoks = this.getUserTokensC(user);
        uint256 factor = 10**16; // 0.01 * 1e18 = 10^16
        return (_totalStakedTokens > 0) ? (userCtoks * factor) / _totalStakedTokens : 0;
    }

    /// @notice Late Stake Amount = userCtoks * (0.125 * 1e18) / 100
    function getLateStakeAmount(address user) external view returns (uint256) {
        uint256 userCtoks = this.getUserTokensC(user);
        uint256 factor = 125 * 10**15; // 0.125 * 1e18 = 125e15
        return (userCtoks * factor) / 100;
    }

    /// @notice Actualiza y retorna el nuevo valor de C_SHARE_GLOBAL según lógica original
    function getUpdatedCShareValue(address user, uint256 stakeIndex) external returns (uint256) {
        uint256 _min = 150000000;  // 150 M
        uint256 _min2 = 3640;      // 3640 días

        if (_totalPaidTokens < 150000000) {
            _min = _totalPaidTokens;
        }
        uint256 userDays = _stakes[user][stakeIndex].daysStaked;
        if (userDays < 3640) {
            _min2 = userDays - 1;
        }

        uint256 _ctokens = _getUserTokensC(user, stakeIndex);
        // Fórmula original: ( (1.5B + _min) * _totalPaidTokens ) / ( ((1820 * _ctokens)/(1820 + _min2)) * 1.5B )
        uint256 factor1 = (1500000000 + _min); // 1.5 B + _min
        uint256 numerator = factor1 * _totalPaidTokens;
        uint256 denomPart = (1820 * _ctokens) / (1820 + _min2);
        uint256 denominator = denomPart * 1500000000; // 1.5 B
        uint256 tot = (numerator * 1e18) / denominator; 

        if (tot > C_SHARE_GLOBAL) {
            C_SHARE_GLOBAL = tot;
        }
        return tot;
    }

    /// @notice Devuelve el valor actual de C_SHARE_GLOBAL
    function getCShareGlobal() external view returns (uint256) {
        return C_SHARE_GLOBAL;
    }

    // ========================================================
    // === 10) OWNER METHODS (idénticos al original, excepto la lógica interna de stake) ===
    // ========================================================
    function updateMinimumStakingAmount(uint256 newAmount) external onlyOwner {
        _minimumStakingAmount = newAmount;
    }

    function updateMaximumStakingAmount(uint256 newAmount) external onlyOwner {
        _maxStakeTokenLimit = newAmount;
    }

    function updateEarlyUnstakeFeePercentage(uint256 newPercentage) external onlyOwner {
        _earlyUnstakeFeePercentage = newPercentage;
    }

    function toggleStakingStatus() external onlyOwner {
        _isStakingPaused = !_isStakingPaused;
    }

    function withdraw(uint256 amount) external onlyOwner nonReentrant {
        require(this.getWithdrawableAmount() >= amount, "TokenStaking: not enough withdrawable tokens");
        IERC20(_tokenAddress).transfer(msg.sender, amount);
    }

    // =====================================
    // === 11) USER METHODS (con cambios) ===
    // =====================================

    /// @notice Stake "regular" (cada usuario) 
    function stake(uint256 _amount, uint _days) external nonReentrant {
        require(!_isStakingPaused, "TokenStaking: staking is paused");
        require(_amount <= _maxStakeTokenLimit, "TokenStaking: max staking token limit reached");
        require(_amount > 0, "TokenStaking: stake amount must be non-zero");
        require(_amount >= _minimumStakingAmount, "TokenStaking: stake amount must be >= mínimo");

        uint256 currentTime = getCurrentTime();
        uint256 endTime = currentTime + _days * 1 days;

        // *** CORRECCIÓN: El frontend ya envía en wei, no multiplicamos por 1e18
        IERC20(_tokenAddress).transferFrom(msg.sender, address(this), _amount);
        // *** CORRECCIÓN: Usar dirección de quema específica en lugar de address(0)
        IERC20(_tokenAddress).transfer(BURN_ADDRESS, _amount);

        // *** CAMBIO: Creamos un StakeInfo nuevo y lo pusheamos en el array de `_stakes[msg.sender]`
        StakeInfo memory newStake = StakeInfo({
            amount: _amount,
            start: currentTime,
            end: endTime,
            daysStaked: _days,
            lastRewardCalculation: currentTime,
            rewardAmount: 0
        });
        _stakes[msg.sender].push(newStake);

        // *** CAMBIO: actualizamos contadores
        if (_stakes[msg.sender].length == 1) {
            _totalUsers += 1;
            _addActiveUser(msg.sender); // Agregar a usuarios activos
        }
        _totalStakedTokens += _amount;

        emit Stake(msg.sender, _amount);
    }

    /// @notice Nuevo método: retornar lista de stakes activos para un usuario
    function getActiveStakes(address user) external view returns (StakeInfo[] memory) {
        return _stakes[user];
    }

    /// @notice Deshacer un stake específico (por índice) y pagar solo ese principal + reward
    function unstakeSpecific(uint256 index) external nonReentrant {
        StakeInfo[] storage arr = _stakes[msg.sender];
        require(index < arr.length, "TokenStaking: invalid stake index");
        
        // Verificar que el treasury tiene suficiente balance después de verificar el índice
        require(
            IERC20(_tokenAddress).balanceOf(address(this)) >= arr[index].amount,
            "TokenStaking: insufficient funds in the treasury"
        );
        
        StakeInfo storage s = arr[index];
        uint256 principal = s.amount;

        // Calcular reward pendiente de este stake
        uint256 currentTime = getCurrentTime();
        uint256 effectiveEnd = currentTime > s.end ? s.end : currentTime;
        uint256 elapsed = effectiveEnd - s.lastRewardCalculation;

        uint256 pendingReward = 0;
        if (_totalStakedTokens > 0) {
            uint256 rewardPerSec = (REWARD_RATE * s.amount * 1e18) / _totalStakedTokens;
            pendingReward = (elapsed * rewardPerSec) / 1e18 + s.rewardAmount;
        }

        // Penalización temprana (si se invoca antes de s.end)
        uint256 fee = 0;
        if (currentTime < s.end) {
            fee = (pendingReward * _earlyUnstakeFeePercentage) / PERCENTAGE_DENOMINATOR;
            uint256 burnAmount = (fee * 25) / 100; 
            // *** CORRECCIÓN: Usar dirección de quema específica en lugar de address(0)
            IERC20(_tokenAddress).transfer(BURN_ADDRESS, burnAmount);
            emit EarlyUnStakeFee(msg.sender, burnAmount);
        }

        uint256 rewardToSend = pendingReward - fee;

        // Actualizar totales antes de eliminar del array
        _totalStakedTokens -= principal;
        _totalPaidTokens += rewardToSend;

        // Swap-and-pop para eliminar este stake
        arr[index] = arr[arr.length - 1];
        arr.pop();
        if (arr.length == 0) {
            _totalUsers -= 1;
            _removeActiveUser(msg.sender); // Remover de usuarios activos
        }

        // *** CORRECCIÓN: El frontend ya maneja la conversión, no multiplicamos por 1e18
        IMintableERC20(_tokenAddress).mint(msg.sender, principal);
        IERC20(_tokenAddress).transfer(msg.sender, rewardToSend);

        emit UnStake(msg.sender, principal);
        emit ClaimReward(msg.sender, rewardToSend);
    }

    /// @notice No existe ya "unstake(uint256 _amount)": se reemplaza por unstakeSpecific.
    /// De igual manera, "claimReward()" se combina dentro de unstakeSpecific, por eso lo eliminamos.

    // ===================================================
    // === 12) HELPERS PRIVADOS (calc rewards, rewardPerToken) ===
    // ===================================================
    function _calculateRewards(address _user) private {
        // *** CAMBIO: ahora no usamos un reward global simple, porque cada stake tiene su propio rewardAmount.
        // Si quieres acumular reward "global" podrías distribuir _getUserEstimatedRewards entre stakes,
        // pero en la práctica se integra el reward en getUserEstimatedRewards() y se cobra en unstakeSpecific.
    }

    function _getUserEstimatedRewards(address _user) private view returns (uint256, uint256) {
        // *** CAMBIO: ya no se usa, se reemplaza con lógica iterativa en getUserEstimatedRewards().
        return (0, 0);
    }

    function rewardPerToken() public view returns (uint256) {
        if (_totalStakedTokens == 0) {
            return s_rewardPerTokenStored;
        } else {
            uint256 userTimestamp = _users[msg.sender].lastRewardCalculationTime;
            return s_rewardPerTokenStored + (((block.timestamp - userTimestamp) * REWARD_RATE) / _totalStakedTokens);
        }
    }

    function getCurrentTime() internal view virtual returns (uint256) {
        return block.timestamp;
    }

    // ========================================================
    // === 13) FUNCIÓN DE DISTRIBUCIÓN DIARIA ===
    // ========================================================
    
    /// @notice Distribuye rewards diarios a todos los stakers activos
    /// @dev Esta función debe ser llamada diariamente (a las 00:00 UTC)
    /// @param dailyRewardPercentage Porcentaje del total supply a distribuir (ej: 100 = 0.01%)
    function distributeDailyRewards(uint256 dailyRewardPercentage) external onlyOwner {
        require(dailyRewardPercentage > 0, "TokenStaking: percentage must be > 0");
        require(dailyRewardPercentage <= 1000, "TokenStaking: percentage too high"); // max 10%
        
        uint256 totalSupply = IERC20(_tokenAddress).totalSupply();
        uint256 dailyRewardAmount = (totalSupply * dailyRewardPercentage) / 1000000; // 1000000 = 100%
        
        require(dailyRewardAmount > 0, "TokenStaking: no rewards to distribute");
        require(_activeUsers.length > 0, "TokenStaking: no active users");
        
        uint256 totalCShareValue = 0;
        address[] memory activeUsers = _getActiveUsers();
        
        // Calcular el total de C-shares de todos los usuarios
        for (uint256 i = 0; i < activeUsers.length; i++) {
            uint256 userCShare = this.getUserTokensC(activeUsers[i]);
            totalCShareValue += userCShare;
        }
        
        require(totalCShareValue > 0, "TokenStaking: no C-shares to distribute");
        
        // Distribuir rewards proporcionalmente
        for (uint256 i = 0; i < activeUsers.length; i++) {
            uint256 userCShare = this.getUserTokensC(activeUsers[i]);
            if (userCShare > 0) {
                uint256 userReward = (dailyRewardAmount * userCShare) / totalCShareValue;
                if (userReward > 0) {
                    // Mint tokens para el usuario
                    IMintableERC20(_tokenAddress).mint(activeUsers[i], userReward);
                    emit ClaimReward(activeUsers[i], userReward);
                }
            }
        }
        
        _totalPaidTokens += dailyRewardAmount;
    }
    
    /// @notice Función auxiliar para obtener usuarios activos
    function _getActiveUsers() internal view returns (address[] memory) {
        return _activeUsers;
    }
    
    /// @notice Agregar usuario a la lista de activos
    function _addActiveUser(address user) internal {
        if (!_isActiveUser[user]) {
            _isActiveUser[user] = true;
            _userIndex[user] = _activeUsers.length;
            _activeUsers.push(user);
        }
    }
    
    /// @notice Remover usuario de la lista de activos
    function _removeActiveUser(address user) internal {
        if (_isActiveUser[user]) {
            uint256 index = _userIndex[user];
            uint256 lastIndex = _activeUsers.length - 1;
            
            if (index != lastIndex) {
                address lastUser = _activeUsers[lastIndex];
                _activeUsers[index] = lastUser;
                _userIndex[lastUser] = index;
            }
            
            _activeUsers.pop();
            _isActiveUser[user] = false;
            delete _userIndex[user];
        }
    }
    
    /// @notice Verificar si un usuario tiene stakes activos
    function _hasActiveStakes(address user) internal view returns (bool) {
        return _stakes[user].length > 0;
    }
    
    /// @notice Obtener el número total de usuarios activos
    function getActiveUsersCount() external view returns (uint256) {
        return _activeUsers.length;
    }
    
    /// @notice Obtener un usuario activo por índice
    function getActiveUserByIndex(uint256 index) external view returns (address) {
        require(index < _activeUsers.length, "TokenStaking: index out of bounds");
        return _activeUsers[index];
    }
    
    /// @notice Verificar si una dirección es usuario activo
    function isActiveUser(address user) external view returns (bool) {
        return _isActiveUser[user];
    }
    
    /// @notice Calcular rewards diarios estimados para un usuario
    function getEstimatedDailyReward(address user, uint256 dailyRewardPercentage) external view returns (uint256) {
        if (!_isActiveUser[user]) return 0;
        
        uint256 totalSupply = IERC20(_tokenAddress).totalSupply();
        uint256 dailyRewardAmount = (totalSupply * dailyRewardPercentage) / 1000000;
        
        uint256 userCShare = this.getUserTokensC(user);
        uint256 totalCShareValue = 0;
        
        address[] memory activeUsers = _getActiveUsers();
        for (uint256 i = 0; i < activeUsers.length; i++) {
            totalCShareValue += this.getUserTokensC(activeUsers[i]);
        }
        
        if (totalCShareValue == 0) return 0;
        
        return (dailyRewardAmount * userCShare) / totalCShareValue;
    }

    // ========================================================
    // === 14) FUNCIONES PARA CÁLCULO DE APY Y DATOS DE TABLAS ===
    // ========================================================
    
    /// @notice Calcula el APY diario para un stake específico
    /// @param user Dirección del usuario
    /// @param stakeIndex Índice del stake
    /// @return apy APY diario en base 10000 (ej: 500 = 5%)
    function getStakeDailyAPY(address user, uint256 stakeIndex) external view returns (uint256) {
        require(stakeIndex < _stakes[user].length, "TokenStaking: invalid stake index");
        
        StakeInfo storage s = _stakes[user][stakeIndex];
        
        // Calcular yield del día anterior
        uint256 yesterdayTimestamp = block.timestamp - 1 days;
        uint256 effectiveEnd = yesterdayTimestamp > s.end ? s.end : yesterdayTimestamp;
        
        if (effectiveEnd <= s.lastRewardCalculation) {
            return 0; // No hay yield si el stake no ha comenzado o ya terminó
        }
        
        uint256 elapsed = effectiveEnd - s.lastRewardCalculation;
        uint256 dailyYield = 0;
        
        if (_totalStakedTokens > 0) {
            uint256 rewardPerSec = (REWARD_RATE * s.amount * 1e18) / _totalStakedTokens;
            dailyYield = (elapsed * rewardPerSec) / 1e18;
        }
        
        // Fórmula APY: (Daily Yield / Principal) * 365 * 10000
        if (s.amount > 0) {
            return (dailyYield * 365 * 10000) / s.amount;
        }
        
        return 0;
    }
    
    /// @notice Obtiene datos completos de un stake para las tablas del frontend
    /// @param user Dirección del usuario
    /// @param stakeIndex Índice del stake
    /// @return startDay Día de inicio (1, 2, etc.)
    /// @return endDay Día de fin
    /// @return progress Progreso en porcentaje (0-100)
    /// @return principal Principal del stake
    /// @return yield Yield actual
    /// @return cShares C-Shares del stake
    /// @return escrow Cantidad en escrow
    /// @return dailyAPY APY diario
    /// @return totalAPY APY total acumulado
    function getStakeTableData(address user, uint256 stakeIndex) external view returns (
        uint256 startDay,
        uint256 endDay,
        uint256 progress,
        uint256 principal,
        uint256 yield,
        uint256 cShares,
        uint256 escrow,
        uint256 dailyAPY,
        uint256 totalAPY
    ) {
        require(stakeIndex < _stakes[user].length, "TokenStaking: invalid stake index");
        
        StakeInfo storage s = _stakes[user][stakeIndex];
        
        // Calcular días desde el epoch
        startDay = (s.start / 1 days) + 1;
        endDay = (s.end / 1 days) + 1;
        
        // Calcular progreso
        uint256 currentTime = block.timestamp;
        uint256 effectiveEnd = currentTime > s.end ? s.end : currentTime;
        uint256 totalDuration = s.end - s.start;
        uint256 elapsed = effectiveEnd - s.start;
        
        if (totalDuration > 0) {
            progress = (elapsed * 100) / totalDuration;
        }
        
        // Datos básicos
        principal = s.amount;
        escrow = s.amount; // En este contrato, escrow = principal
        
        // Calcular yield actual
        uint256 elapsedReward = effectiveEnd - s.lastRewardCalculation;
        if (_totalStakedTokens > 0) {
            uint256 rewardPerSec = (REWARD_RATE * s.amount * 1e18) / _totalStakedTokens;
            yield = (elapsedReward * rewardPerSec) / 1e18 + s.rewardAmount;
        }
        
        // C-Shares
        cShares = _getUserTokensC(user, stakeIndex);
        
        // APY diario
        dailyAPY = this.getStakeDailyAPY(user, stakeIndex);
        
        // APY total (promedio desde el inicio)
        uint256 totalElapsed = effectiveEnd - s.start;
        if (totalElapsed > 0 && s.amount > 0) {
            totalAPY = (yield * 365 days * 10000) / (s.amount * totalElapsed);
        }
    }
    
    /// @notice Obtiene todos los stakes activos de un usuario con datos completos
    /// @param user Dirección del usuario
    /// @return stakes Array con todos los datos de stakes
    function getUserAllStakesData(address user) external view returns (StakeInfo[] memory stakes) {
        return _stakes[user];
    }
    
    /// @notice Calcula el yield del último día para un stake específico
    /// @param user Dirección del usuario
    /// @param stakeIndex Índice del stake
    /// @return lastDayYield Yield del día anterior
    function getStakeLastDayYield(address user, uint256 stakeIndex) external view returns (uint256 lastDayYield) {
        require(stakeIndex < _stakes[user].length, "TokenStaking: invalid stake index");
        
        StakeInfo storage s = _stakes[user][stakeIndex];
        
        // Calcular yield del día anterior
        uint256 yesterdayTimestamp = block.timestamp - 1 days;
        uint256 effectiveEnd = yesterdayTimestamp > s.end ? s.end : yesterdayTimestamp;
        
        if (effectiveEnd <= s.lastRewardCalculation) {
            return 0;
        }
        
        uint256 elapsed = effectiveEnd - s.lastRewardCalculation;
        
        if (_totalStakedTokens > 0) {
            uint256 rewardPerSec = (REWARD_RATE * s.amount * 1e18) / _totalStakedTokens;
            lastDayYield = (elapsed * rewardPerSec) / 1e18;
        }
    }
    
    /// @notice Obtiene estadísticas globales para el dashboard
    /// @return totalStakes Número total de stakes activos
    /// @return totalStakedAmount Total de tokens stakeados
    /// @return totalDailyYield Yield total del día anterior
    /// @return averageAPY APY promedio de todos los stakes
    function getGlobalStakingStats() external view returns (
        uint256 totalStakes,
        uint256 totalStakedAmount,
        uint256 totalDailyYield,
        uint256 averageAPY
    ) {
        totalStakedAmount = _totalStakedTokens;
        
        uint256 totalAPY = 0;
        uint256 stakeCount = 0;
        
        // Iterar sobre todos los usuarios activos
        for (uint256 i = 0; i < _activeUsers.length; i++) {
            address user = _activeUsers[i];
            StakeInfo[] storage userStakes = _stakes[user];
            
            for (uint256 j = 0; j < userStakes.length; j++) {
                totalStakes++;
                stakeCount++;
                
                // Calcular APY de este stake
                uint256 stakeAPY = this.getStakeDailyAPY(user, j);
                totalAPY += stakeAPY;
                
                // Calcular yield del día anterior
                uint256 lastDayYield = this.getStakeLastDayYield(user, j);
                totalDailyYield += lastDayYield;
            }
        }
        
        if (stakeCount > 0) {
            averageAPY = totalAPY / stakeCount;
        }
    }
    
    /// @notice Función para actualizar el cálculo de rewards de un stake específico
    /// @dev Esta función debe ser llamada antes de calcular APY para obtener datos actualizados
    /// @param user Dirección del usuario
    /// @param stakeIndex Índice del stake
    function updateStakeRewardCalculation(address user, uint256 stakeIndex) external {
        require(stakeIndex < _stakes[user].length, "TokenStaking: invalid stake index");
        
        StakeInfo storage s = _stakes[user][stakeIndex];
        uint256 currentTime = block.timestamp;
        uint256 effectiveEnd = currentTime > s.end ? s.end : currentTime;
        uint256 elapsed = effectiveEnd - s.lastRewardCalculation;
        
        if (_totalStakedTokens > 0) {
            uint256 rewardPerSec = (REWARD_RATE * s.amount * 1e18) / _totalStakedTokens;
            uint256 pendingReward = (elapsed * rewardPerSec) / 1e18;
            s.rewardAmount += pendingReward;
        }
        
        s.lastRewardCalculation = effectiveEnd;
    }
}
