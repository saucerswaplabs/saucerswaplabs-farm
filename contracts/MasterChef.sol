// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import './OpenZeppelin/IERC20.sol';
import './OpenZeppelin/Ownable.sol';
import './OpenZeppelin/ReentrancyGuard.sol';
import './OpenZeppelin/SafeCast.sol';
import './hedera/SafeHederaTokenService.sol';

// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance system once Sauce is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. 

// Note: massUpdatePools() is removed, mass updates must be done one by one

contract MasterChef is Ownable, ReentrancyGuard, SafeHederaTokenService {
    
    using SafeCast for uint256;
    using SafeCast for int256;
    
    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 rewardDebtHbar; // reward debt for hbar
        //
        // We do some fancy math here. Basically, any point in time, the amount of Sauces
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accSaucePerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accSaucePerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        address lpToken;           // Address of LP token solidity address.
        uint256 allocPoint;       // How many allocation points assigned to this pool. Sauces to distribute per block.
        uint256 lastRewardTime;  // Last block time that Sauces distribution occurs.
        uint256 accSaucePerShare; // Accumulated Sauces per share, times 1e12. See below.
        uint256 accHBARPerShare; // Accumulated HBAR per share, times 1e12, while hbar reward period is on
    }

    // address of Sauce token
    address public sauce;
    // keep track of total supply of Sauce
    uint256 totalSupply;
    // Dev address.
    address public devaddr;
    // Rent payer address
    address public rentPayer;
    // Sauce tokens created per second
    uint256 public saucePerSecond;
    //hbar emitted per second
    uint256 public hbarPerSecond;
    // max Sauce supply
    uint256 public maxSauceSupply;

    // set a max Sauce per second, which can never be higher than 50 per second
    uint256 public constant maxSaucePerSecond = 50e6;
    // maximum allocPoint for a pool
    uint256 public constant MaxAllocPoint = 4000;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block time when Sauce mining starts.
    uint256 public immutable startTime;
    // deposit fee for smart contract rent
    uint256 public depositFee;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event DidNotReceiveHbar(address indexed to, uint256 amount);

    /**
     * @dev constructor
     *
     * @param _devaddr dev address
     * @param _rentPayer rent payer address
     * @param _saucePerSecond sauce per second rewards
     * @param _hbarPerSecond hbar per second rewards
     * @param _maxSauceSupply max supply of sauce
     * @param _depositFeeTinyCents deposit fee for rent
     */    
    constructor(
        address _devaddr,
        address _rentPayer,
        uint256 _saucePerSecond,
        uint256 _hbarPerSecond,
        uint256 _maxSauceSupply,
        uint256 _depositFeeTinyCents
    ) {
        require(_devaddr != address(0), "devaddr != address(0)");
        require(_rentPayer != address(0), "devaddr != address(0)");

        devaddr = _devaddr;
        rentPayer = _rentPayer;
        saucePerSecond = _saucePerSecond;
        hbarPerSecond = _hbarPerSecond;
        maxSauceSupply = _maxSauceSupply;
        depositFee = _depositFeeTinyCents;

        startTime = block.timestamp;
    }

    /**
     * @dev receive function
     */
    receive() external payable {}

    /**
     * @dev Sets the address for the sauce token
     *
     * only owner callable
     *
     * @param _sauce new address for sauce
     */    
    function setSauceAddress(address _sauce) external onlyOwner {
        require(_sauce != address(0), "sauce != address(0)");
        sauce = _sauce;
    }

    /**
     * @dev deposit fee is in terms of tiny cents (1 cent = 1e8)
     *
     * only owner callable
     *
     * @param _depositFee deposit fee in tiny cents 
     */
    function setDepositFee(uint256 _depositFee) external onlyOwner {
        depositFee = _depositFee;
    }

    /**
     * @dev gets the amount of pools in the contract
     *
     * @return amount of pools in the contract
     */
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    /**
     * @dev set hbar per second rewards
     *
     * only owner callable
     *
     * @param _hbarPerSecond new hbar per second rewards value
     */    
    function setHbarPerSecond(uint256 _hbarPerSecond) external onlyOwner {
        hbarPerSecond = _hbarPerSecond;
    }

    /**
     * @dev set max supply of sauce
     *
     * only owner callable
     *
     * @param _maxSauceSupply new value for max sauce supply
     */
    function setMaxSauceSupply(uint256 _maxSauceSupply) external onlyOwner {
        maxSauceSupply = _maxSauceSupply;
    }

    /**
     * @dev set sauce per second
     *
     * only owner callable
     *
     * @param _saucePerSecond new sauce per second value
     */    
    function setSaucePerSecond(uint256 _saucePerSecond) external onlyOwner {
        require(_saucePerSecond <= maxSaucePerSecond, "setSaucePerSecond: too many sauces!");

        saucePerSecond = _saucePerSecond;
    }
    
    /**
     * @dev Add a new lp to the pool. Can only be called by the owner.
     * 
     * only owner callable
     *
     * @param _allocPoint sauce allocation points
     * @param _lpToken lp token address
     */
    function add(uint256 _allocPoint, address _lpToken) external onlyOwner {
        require(_allocPoint <= MaxAllocPoint, "add: too many alloc points!!");
        
        safeAssociateToken(address(this), _lpToken); // enforces that token is not already associated => not duplicated
        uint256 lastRewardTime = block.timestamp;
        totalAllocPoint = totalAllocPoint + (_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardTime: lastRewardTime,
            accSaucePerShare: 0,
            accHBARPerShare: 0
        }));

    }

    /**
     * @dev Update the given pool's Sauce allocation point. Can only be called by the owner.
     *
     * only owner callable
     *
     * @param _pid pool ID
     * @param _allocPoint new allocation point value to use
     */
    function set(uint256 _pid, uint256 _allocPoint) external onlyOwner {
        require(_allocPoint <= MaxAllocPoint, "add: too many alloc points!!");

        totalAllocPoint = totalAllocPoint - poolInfo[_pid].allocPoint + _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    /**
     * @dev Return reward multiplier over the given _from to _to block.
     *
     * @param _from from block/start time
     * @param _to to block/start time
     *
     * @return difference in _to to _from to determine the multiplier value for rewards
     */
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        _from = _from > startTime ? _from : startTime;
        if (_to < startTime) {
            return 0;
        }
        return _to - _from;
    }

    /**
     * @dev View function to see pending Sauces and hbar
     *
     * @param _pid pool ID
     * @param _user user's address
     * 
     * @return pending sauce and hbar
     */
    function pendingSauce(uint256 _pid, address _user) external view returns (uint256, uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accSaucePerShare = pool.accSaucePerShare;
        uint256 accHBARPerShare = pool.accHBARPerShare;
        uint256 lpSupply = IERC20(pool.lpToken).balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
            uint256 sauceReward = multiplier * (saucePerSecond) * (pool.allocPoint) / (totalAllocPoint);
            uint256 hbarReward = multiplier * (hbarPerSecond) * (pool.allocPoint) / (totalAllocPoint);
            accSaucePerShare = accSaucePerShare + (sauceReward * (1e12) / (lpSupply));
            accHBARPerShare = accHBARPerShare + (hbarReward * (1e12) / (lpSupply));
        }

        return (user.amount * (accSaucePerShare) / (1e12) - (user.rewardDebt), user.amount * (accHBARPerShare) / (1e12) - (user.rewardDebtHbar));
    }

    /**
     * @dev Update reward variables of the given pool to be up-to-date.
     *
     * @param _pid pool ID
     */
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }
        uint256 lpSupply = IERC20(pool.lpToken).balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);

        if (saucePerSecond > 0) {
            uint256 sauceReward = multiplier * saucePerSecond * pool.allocPoint / totalAllocPoint; 
            uint devCut = sauceReward / 10;     

            if (sauceReward + devCut + totalSupply > maxSauceSupply) {
                sauceReward = (maxSauceSupply - (IERC20(sauce).totalSupply())) * 9 / 10;
                devCut = (maxSauceSupply - (IERC20(sauce).totalSupply())) / 10;
                saucePerSecond = 0;
            }

            (, totalSupply, ) = safeMintToken(address(sauce), (devCut + sauceReward).toUint64(), new bytes[](0));
            safeTransferToken(address(sauce), address(this), devaddr, devCut.toInt256().toInt64());

            pool.accSaucePerShare = pool.accSaucePerShare + (sauceReward * (1e12) / (lpSupply));
        }
        
        if (hbarPerSecond > 0) {
            uint256 hbarReward = multiplier * hbarPerSecond * pool.allocPoint / totalAllocPoint;

            if (hbarReward > address(this).balance) {
                hbarReward = address(this).balance;
                hbarPerSecond = 0;
            }
            pool.accHBARPerShare = pool.accHBARPerShare + (hbarReward * (1e12) / (lpSupply));
        }
        
        pool.lastRewardTime = block.timestamp;
    }

    /**
     * @dev Deposit LP tokens to MasterChef for Sauce allocation.
     * 
     * uses nonReentrant, is payable
     *
     * @param _pid pool ID
     * @param _amount amount to send
     */
    function deposit(uint256 _pid, uint256 _amount) external payable nonReentrant {
        require(msg.value >= tinycentsToTinybars(depositFee), 'msg.value < depositFee');
        
        // send rent to rentPayer
        (bool result, ) = rentPayer.call{value: msg.value}("");
        if (!result) {
            emit DidNotReceiveHbar(rentPayer, msg.value);
        }
        
        UserInfo storage user = userInfo[_pid][msg.sender];        
        PoolInfo storage pool = poolInfo[_pid];

        updatePool(_pid);

        uint256 pending = (user.amount * pool.accSaucePerShare / 1e12) - user.rewardDebt;
        uint256 pendingHbar = (user.amount * pool.accHBARPerShare / 1e12) - user.rewardDebtHbar;

        user.amount = user.amount + _amount;
        user.rewardDebt = user.amount * pool.accSaucePerShare / 1e12;
        user.rewardDebtHbar = user.amount * pool.accHBARPerShare / 1e12;

        if(pending > 0) {
            safeSauceTransfer(msg.sender, pending);
        }
        
        if (_amount > 0) {
            safeTransferToken(pool.lpToken, msg.sender, address(this), _amount.toInt256().toInt64());
        }

        emit Deposit(msg.sender, _pid, _amount);

        if (pendingHbar > 0) {
            safeHBARTransfer(msg.sender, pendingHbar);
        }
    }

    /**
     * @dev Withdraw LP tokens from MasterChef.
     * 
     * uses nonReentrant
     *
     * @param _pid pool ID from which to withdraw
     * @param _amount amount to withdraw
     */
    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {  
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);

        uint256 pending = (user.amount * pool.accSaucePerShare / 1e12) - user.rewardDebt;
        uint256 pendingHbar = (user.amount * pool.accHBARPerShare / 1e12) - user.rewardDebtHbar;

        user.amount = user.amount - _amount;
        user.rewardDebt = user.amount * pool.accSaucePerShare / 1e12;
        user.rewardDebtHbar = user.amount * pool.accHBARPerShare / 1e12;

        if(pending > 0) {
            safeSauceTransfer(msg.sender, pending);
        }
        
        if(_amount > 0) {
            safeTransferToken(address(pool.lpToken), address(this), msg.sender, _amount.toInt256().toInt64());
        }

        emit Withdraw(msg.sender, _pid, _amount);

        if (pendingHbar > 0) { 
            safeHBARTransfer(msg.sender, pendingHbar);
        }
    }

    /**
     * @dev Withdraw without caring about rewards. EMERGENCY ONLY.
     *
     * @param _pid pool ID from which to withdraw 
     */
    function emergencyWithdraw(uint256 _pid) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint oldUserAmount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        user.rewardDebtHbar = 0;

        safeTransferToken(address(pool.lpToken), address(this), msg.sender, oldUserAmount.toInt256().toInt64());
        emit EmergencyWithdraw(msg.sender, _pid, oldUserAmount);

    }

    /**
     * @dev Safe sauce transfer function, just in case if rounding error causes pool to not have enough Sauces.
     *
     * @param _to recipient address
     * @param _amount amount to send
     */
    function safeSauceTransfer(address _to, uint256 _amount) internal returns(uint) {
        uint256 sauceBal = IERC20(sauce).balanceOf(address(this));
        if (_amount > sauceBal) {
            safeTransferToken(sauce, address(this), _to, sauceBal.toInt256().toInt64());
        } else {
            safeTransferToken(sauce, address(this), _to, _amount.toInt256().toInt64());
        }
        return sauceBal;
    }

    /**
     * @dev Safe hbar transfer function, just in case if rounding error causes pool to not have enough hbar.
     *
     * @param _to recipient address
     * @param _amount amount to send
     */    
    function safeHBARTransfer(address _to, uint256 _amount) internal returns (uint) {
        uint256 hbarBal = address(this).balance;
        if (_amount > hbarBal) {
            (bool result, ) = _to.call{value: hbarBal}("");

            if (!result) {
                emit DidNotReceiveHbar(_to, hbarBal);
            }
        } else {
            (bool result, ) = _to.call{value: _amount}("");
            
            if (!result) {
                emit DidNotReceiveHbar(_to, _amount);
            }
        }
        return hbarBal;
    }

    /**
     * @dev only owner function that updates the dev address to the specified one
     *
     * only owner callable
     * 
     * @param _devaddr new dev address
     */  
    function setDevAddr(address _devaddr) external onlyOwner {
        require(_devaddr != address(0), "devaddr != address(0)");
        devaddr = _devaddr;
    }

    /**
     * @dev only owner function that sets the rentPayer address
     *
     * only owner callable
     *
     * @param _rentPayer new rent payer address
     */
    function setRentPayer(address _rentPayer) external onlyOwner {
        require(_rentPayer != address(0), "devaddr != address(0)");
        rentPayer = _rentPayer;
    }
}
