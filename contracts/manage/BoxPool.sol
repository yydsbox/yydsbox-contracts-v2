// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "../random/IRandomGenerator.sol";
import "../random/IRandomAccessor.sol";
import "../random/IRandomReceiver.sol";
import "../token/IBoxTicket.sol";
import "../token/IBoxPrize.sol";
import "./IBoxController.sol";
import "./IBoxPool.sol";
import "./IFeeCollector.sol";

contract BoxPool is IBoxController, IBoxPool, IRandomReceiver, Ownable, ERC721Holder {
    using SafeERC20 for IERC20;

    // 随机数用途：开奖、开彩蛋
    enum RandomnessType {
        Pool,
        Egg
    }

    // 盲盒奖金(一等奖、二等奖、三等奖、普惠奖、本期蓄水池)、彩蛋奖金、手续费
    enum DistributionType {
        Bonus,
        Egg,
        Fee
    }

    struct Pool {
        uint256 poolId;                                 // poolId

        uint256 price;                                  // 单价
        uint256 capacity;                               // 容量
        uint256[] distributionRatios;                   // 资金分配比例
        uint256[] awardsOdds;                           // 各奖项数量
        uint256[] awardsRatios;                         // 各奖项奖金比例
        uint256 bufferRatio;                            // 蓄水池资金流入下期奖池的比例
        uint256 accountRatio;                           // 普惠奖中奖账号率

        uint256 fromId;                                 // 起始盲盒ID
        uint256 endId;                                  // 结束盲盒ID
        uint256 amount;                                 // 本期盲盒奖金
        uint256 balance;                                // 本期余额
        uint256 quantity;                               // Box数量
        address[] accounts;                             // 参与地址
        mapping (address => uint256) accountsQuantity;  // 各账号购买的box数量

        bytes32 requestId;                              // 请求随机数的ID
        uint256 randomness;                             // 随机数
        bool published;                                 // 是否已发布

        mapping (uint256 => uint256) winBoxIndexes;     // 中奖盲盒索引
        WinBox[] winBoxes;                              // 中奖盲盒
        mapping (address => uint256) winAccountIndexes; // 中奖账号索引
        WinAccount[] winAccounts;                       // 中奖账号

        uint256[] awards;                               // 各奖项奖励
    }

    struct Egg {
        uint256 eggId;
        uint256 fromId;                                 // 开始盲盒ID
        uint256 toId;                                   // 结束盲盒ID
        
        bytes32 requestId;                              // 请求随机数的ID
        uint256 randomness;                             // 随机数
        bool published;                                 // 是否已发布

        WinEgg winEgg;                                  // 中奖的彩蛋
    }

    struct RandomnessUse {
        RandomnessType randomnessType;
        uint256 poolId;
        uint256 eggId;
    }

    uint256 private constant BASE_RATIO = 1e4;
    uint256 private constant MIN_ID = 1e4;
    uint256 private constant MIN_CAPACITY = 100;
    uint256 private constant MAX_CAPACITY = 1e6;

    IERC20 private _token;
    IBoxTicket private _boxTicket;
    IBoxPrize private _boxPrize;

    IRandomAccessor private _randomAccessor;
    IRandomGenerator private _randomGenerator;
    IFeeCollector private _feeCollector;

    uint256 private _defaultPrice = 1e22;         // 1e4 * 1e18 = 10000个代币
    uint256[] private _defaultDistributionRatios; // 奖池奖金、彩蛋奖金、手续费 [80%, 11%, 9%]
    uint256[] private _defaultAwardsOdds;         // 中奖人数 [1, 4, 8, 0, 0] 
    uint256[] private _defaultAwardsRatios;       // 奖项奖金 [30%, 20%, 10%, 10%, 30%]
    uint256 private _defaultBufferRatio = 1e4;    // 100%的蓄水池资金将作为下期盲盒池奖金
    uint256 private _defaultAccountRatio = 2000;  // 20%的账号将中普惠奖

    uint256 private _currentCapacity = 100;       // 盲盒池当前容量
    bool private _capacityGrowDirection = true;   // true.增加 false.减少
    uint256 private _capacityGrowDelta = 10;      // 增量

    uint256 private _lastBufferBalance;           // 上期蓄水池余额

    uint256 private _eggOdds = 100;               // 100个盲盒中挑1个作为彩蛋
    uint256 private _eggRatio = 100;              // 当前彩蛋奖金 1%
    uint256 private _lastEggBoxId;                // 上期结算彩蛋时盲盒的数量
    uint256 private _lastEggBalance;              // 上期彩蛋结余
    // uint256 private _eggBalance;                  // 当前彩蛋池余额

    uint256 private _poolIdTracker = MIN_ID;
    uint256 private _eggIdTracker = 1;

    mapping (uint256 => uint256) private _prizePoolIds;
    mapping (uint256 => Pool) private _pools;
    mapping (uint256 => Egg) private _eggs;

    mapping (bytes32 => RandomnessUse) private _randomnessUses;

    modifier onlyValid(uint256 poolId) {
        require(_isValid(poolId), "BoxPool: pool not exists");
        _;
    }

    modifier onlyValidEgg(uint256 eggId) {
        require(_isValidEgg(eggId), "BoxPool: egg not exists");
        _;
    }

    modifier onlyNotEnded(uint256 poolId) {
        require(!_isEnded(poolId), "BoxPool: already ended");
        _;
    }

    modifier onlyEnded(uint256 poolId) {
        require(_isEnded(poolId), "BoxPool: not ended");
        _;
    }

    modifier onlyEndedEgg(uint256 eggId) {
        require(_isEndedEgg(eggId), "BoxPool: egg not ended");
        _;
    }

    modifier onlyNotPublished(uint256 poolId) {
        require(!_isPublished(poolId), "BoxPool: already published");
        _;
    }

    modifier onlyNotPublishedEgg(uint256 eggId) {
        require(!_isPublishedEgg(eggId), "BoxPool: egg already published");
        _;
    }

    modifier onlyPublished(uint256 poolId) {
        require(_isPublished(poolId), "BoxPool: not published");
        _;
    }

    modifier onlyPublishedEgg(uint256 eggId) {
        require(_isPublishedEgg(eggId), "BoxPool: egg not published");
        _;
    }

    constructor(address token_, address boxTicket_, address boxPrize_) {
        _token = IERC20(token_);
        _boxTicket = IBoxTicket(boxTicket_);
        _boxPrize = IBoxPrize(boxPrize_);

        _defaultDistributionRatios = new uint256[](3);
        _defaultDistributionRatios[0] = 8000;            // 80% 本期奖金
        _defaultDistributionRatios[1] = 1100;            // 11% 彩蛋奖金
        _defaultDistributionRatios[2] = 900;             // 9%  手续费

        _defaultAwardsOdds = new uint256[](5);
        _defaultAwardsOdds[0] = 1;                       // 一等奖 1个
        _defaultAwardsOdds[1] = 4;                       // 二等奖 4个
        _defaultAwardsOdds[2] = 16;                      // 三等奖 16个
        _defaultAwardsOdds[3] = 0;                       // 普惠奖
        _defaultAwardsOdds[4] = 0;                       // 彩蛋奖池

        _defaultAwardsRatios = new uint256[](5);
        _defaultAwardsRatios[0] = 2000;                  // 一等奖 20%
        _defaultAwardsRatios[1] = 2000;                  // 二等奖 20%
        _defaultAwardsRatios[2] = 2000;                  // 三等奖 20%
        _defaultAwardsRatios[3] = 1000;                  // 普惠奖 10%
        _defaultAwardsRatios[4] = 3000;                  // 彩蛋奖池 10%
    }

    function token() external override view returns (address) {
        return address(_token);
    }

    function boxTicket() external override view returns (address) {
        return address(_boxTicket);
    }

    function boxPrize() external override view returns (address) {
        return address(_boxPrize);
    }

    function randomAccessor() external override view returns (address) {
        return address(_randomAccessor);
    }

    function randomGenerator() external override view returns (address) {
        return address(_randomGenerator);
    }

    function feeCollector() external override view returns (address) {
        return address(_feeCollector);
    }

    function getDefault() external override view returns (uint256 price, uint256[] memory distributionRatios, uint256[] memory awardsOdds, uint256[] memory awardsRatios, uint256 bufferRatio, uint256 accountRatio) {
        price = _defaultPrice;
        distributionRatios = _defaultDistributionRatios;
        awardsOdds = _defaultAwardsOdds;
        awardsRatios = _defaultAwardsRatios;
        bufferRatio = _defaultBufferRatio;
        accountRatio = _defaultAccountRatio;
    }

    // 下期Pool将增加的容量
    function capacityMeta() external override view returns (uint256 growDelta, bool  growDirection) {
        growDelta = _capacityGrowDelta;
        growDirection = _capacityGrowDirection;
    }

    // 彩蛋比例
    function eggMeta() external override view returns (uint256 odds, uint256 ratio) {
        odds = _eggOdds;
        ratio = _eggRatio;
    }

    function setRandomAccessor(address randomAccessor_) external override onlyOwner {
        _randomAccessor = IRandomAccessor(randomAccessor_);
    }

    function setRandomGenerator(address randomGenerator_) external override onlyOwner {
        _randomGenerator = IRandomGenerator(randomGenerator_);
    }

    function setFeeCollector(address feeCollector_) external override onlyOwner {
        _feeCollector = IFeeCollector(feeCollector_);
    }

    function setDefault(uint256 price, uint256[] memory distributionRatios, uint256[] memory awardsOdds, uint256[] memory awardsRatios, uint256 bufferRatio, uint256 accountRatio) external override onlyOwner {
        _defaultPrice = price;
        _defaultDistributionRatios = distributionRatios;
        _defaultAwardsOdds = awardsOdds;
        _defaultAwardsRatios = awardsRatios;
        _defaultBufferRatio = bufferRatio;
        _defaultAccountRatio = accountRatio;
    }

    function setCapacityMeta(uint256 growDelta, bool growDirection) external override onlyOwner {
        _capacityGrowDelta = growDelta;
        _capacityGrowDirection = growDirection;
    }

    function setEggMeta(uint256 odds, uint256 ratio) external override onlyOwner {
        _eggOdds = odds;
        _eggRatio = ratio;
    }

    function create() external override onlyOwner {
        uint256 lastPoolId = _getLatestPoolId();
        require(lastPoolId == 0 || _isPublished(lastPoolId), "BoxPool: last pool not published");
        
        uint256 poolId = _poolIdTracker++;
        Pool storage pool = _pools[poolId];
        pool.poolId = poolId;
        pool.price = _defaultPrice;
        pool.capacity = _currentCapacity;
        pool.distributionRatios = _copyArray(_defaultDistributionRatios);
        pool.awardsOdds = _copyArray(_defaultAwardsOdds);
        pool.awardsRatios = _copyArray(_defaultAwardsRatios);
        pool.bufferRatio = _defaultBufferRatio;
        pool.accountRatio = _defaultAccountRatio;

        // 上期蓄水池作为本期奖金
        pool.amount = (_lastBufferBalance * _defaultBufferRatio / BASE_RATIO);

        // 更新容量
        _updateCapacity();

        emit Created(poolId, _poolIdTracker - MIN_ID);
    }

    function createEgg() external override onlyOwner {
        uint256 lastEggId = _getLatestEggId();
        require(lastEggId == 0 || _isPublishedEgg(lastEggId), "BoxPool: last egg not published");

        if(lastEggId == 0) {
            _lastEggBoxId = _boxTicket.getMinBoxId();
        }

        uint256 eggId = _eggIdTracker++;
        Egg storage egg = _eggs[eggId];
        egg.eggId = eggId;
        egg.fromId = _lastEggBoxId;
        egg.toId = _lastEggBoxId + _eggOdds - 1;

        _lastEggBoxId += _eggOdds;

        emit EggCreated(eggId, egg.fromId, egg.toId);
    }

    function swap(uint256 poolId, uint256 count) external override onlyValid(poolId) onlyNotEnded(poolId) {
        require(count > 0, "BoxPool: count must greater than 0");

        address sender = _msgSender();
        Pool storage pool = _pools[poolId];

        count = Math.min(pool.capacity - pool.quantity, count);
        uint256 totalAmount = pool.price * count;
        require(_token.balanceOf(sender) >= totalAmount, "BoxPool: insufficient balance");

        _token.safeTransferFrom(sender, address(this), totalAmount);
        
        (uint256 ticketId, uint256 fromId, uint256 toId) = _boxTicket.create(sender, poolId, count);
        if(pool.quantity == 0) {
            pool.fromId = fromId;
        }
        pool.endId = toId;

        pool.quantity += count;
        if(pool.accountsQuantity[sender] == 0) {
            pool.accounts.push(sender);
        }
        pool.accountsQuantity[sender] += count;

        pool.amount += _calcDistributionAmount(totalAmount, pool.distributionRatios, DistributionType.Bonus);
        // _eggBalance += _calcDistributionAmount(totalAmount, pool.distributionRatios, DistributionType.Egg);

        emit Swap(poolId, ticketId, fromId, toId);
    }

    // 领取一等奖、二等奖、三等奖
    function claimBox(uint256 boxId) external override {
        require(_boxTicket.isValid(boxId), "BoxPool: invalid box");

        IBoxTicket.Ticket memory ticket = _boxTicket.getTicketByBox(boxId);
        require(ticket.owner == _msgSender(), "BoxPool: not the owner");
        require(_isValid(ticket.poolId), "BoxPool: pool not exists");
        require(!_isExpired(ticket.poolId), "BoxPool: box is expired");

        Pool storage pool = _pools[ticket.poolId];
        uint256 index = pool.winBoxIndexes[boxId];
        require(index > 0, "BoxPool: not the winner");

        WinBox storage winBox = pool.winBoxes[index - 1];
        require(winBox.prizeId == 0, "BoxPool: box prize already claimed");

        uint256 prizeId = _boxPrize.create(ticket.owner, winBox.amount);
        winBox.prizeId = prizeId;

        pool.balance -= winBox.amount;

        _prizePoolIds[prizeId] = pool.poolId;
    }

    // 领取普惠奖
    function claimPublic(uint256 poolId) external override onlyValid(poolId) {
        require(!_isExpired(poolId), "BoxPool: pool is expired");

        address sender = _msgSender();
        Pool storage pool = _pools[poolId];
        uint256 index = pool.winAccountIndexes[sender];
        require(index > 0, "BoxPool: not the winner");

        WinAccount storage winAccount = pool.winAccounts[index - 1];
        require(winAccount.prizeId == 0, "BoxPool: public prize already claimed");

        uint256 prizeId = _boxPrize.create(sender, winAccount.amount);

        pool.balance -= winAccount.amount;

        winAccount.prizeId = prizeId;
        _prizePoolIds[prizeId] = poolId;
    }

    // 领取彩蛋
    function claimEgg(uint256 eggId) external override onlyValidEgg(eggId) onlyPublishedEgg(eggId) {
        Egg storage egg = _eggs[eggId];
        
        WinEgg storage winEgg = egg.winEgg;

        address sender = _msgSender();
        address owner = _boxTicket.ownerOf(winEgg.ticketId);
        require(sender == owner, "BoxPool: not the winner");

        uint256 prizeId = _boxPrize.create(sender, winEgg.amount);

        winEgg.prizeId = prizeId;
        _prizePoolIds[prizeId] = 0;
    }

    function buyback(uint256 prizeId) external override {
        require(_boxPrize.exists(prizeId), "BoxPool: prize not exists");
        require(!_boxPrize.isClaimed(prizeId), "BoxPool: prize already claimed");

        IBoxPrize.Prize memory prize = _boxPrize.getPrize(prizeId);
        require(prize.owner == _msgSender(), "BoxPool: not the owner");

        _boxPrize.setClaimed(prizeId);
        _boxPrize.safeTransferFrom(prize.owner, address(this), prizeId);
        _token.safeTransfer(prize.owner, prize.amount);

        emit Buyback(prizeId, prize.amount);
    }

    function onRandomReceived(bytes32 requestId, uint256 randomness) external override {
        require(_msgSender() == address(_randomAccessor), "BoxPool: invalid caller");
        require(randomness != 0, "BoxPool: invalid randomness");

        RandomnessUse memory randomnessUse = _randomnessUses[requestId];
        if(randomnessUse.randomnessType == RandomnessType.Pool) {
            _fillRandomness(requestId, randomness, randomnessUse.poolId);
        } else {
            _fillRandomnessEgg(requestId, randomness, randomnessUse.eggId);
        }
    }

    function tryPublish() external override {
        _tryPublish(_getLatestPoolId());
    }

    function publish() external override {
        _publish(_getLatestPoolId());
    }

    function tryPublishEgg() external override {
        _tryPublishEgg(_getLatestEggId());
    }

    function publishEgg() external override {
        _publishEgg(_getLatestEggId());
    }

    function canPublish() external override view returns (bool) {
        uint256 poolId = _getLatestPoolId();
        return _isValid(poolId) && _isEnded(poolId) && !_isPublished(poolId);
    }

    function canPublishEgg() external override view returns (bool) {
        uint256 eggId = _getLatestEggId();
        return _isValidEgg(eggId) && _isEndedEgg(eggId) && !_isPublishedEgg(eggId);
    }

    function getLatestPool() external override view returns (uint256 poolId, bool ended, bool published) {
        poolId = _getLatestPoolId();
        ended = _isEnded(poolId);
        published = _isPublished(poolId);
    }

    function getLatestEgg() external override view returns (uint256 eggId, bool ended, bool published) {
        eggId = _getLatestEggId();
        ended = _isEndedEgg(eggId);
        published = _isPublishedEgg(eggId);
    }

    function getWinBoxes(uint256 poolId) external override view returns (WinBox[] memory result) {
        if(_isValid(poolId)) {
            WinBox[] memory winBoxes = _pools[poolId].winBoxes;
            uint256 length = winBoxes.length;
            result = new WinBox[](length);

            WinBox memory winBox;
            IBoxPrize.Prize memory prize;
            address owner;
            bool claimed;
            for(uint256 i = 0; i < length; i++) {
                winBox = winBoxes[i];
                if(winBox.prizeId == 0) {
                    owner = _boxTicket.ownerOf(winBox.ticketId);
                    claimed = false;
                } else {
                    prize = _boxPrize.getPrize(winBox.prizeId);
                    owner = prize.owner;
                    claimed = prize.claimed;
                }
                
                result[i] = WinBox(
                    winBox.boxId,
                    winBox.ticketId,
                    winBox.poolId,
                    winBox.prizeId,
                    winBox.amount,
                    winBox.index,
                    _isExpired(winBox.poolId),
                    claimed,
                    owner
                );
            }
        }
    }

    function getWinAccountCount(uint256 poolId) external override view returns (uint256) {
        return _isValid(poolId) ? _calcWinAccountCount(_pools[poolId]) : 0;
    }

    function getWinAccount(uint256 poolId, uint256 index) external override view returns (WinAccount memory result) {
        if(_isValid(poolId)) {
            Pool storage pool = _pools[poolId];            
            if(index < pool.winAccounts.length) {
                result = _getWinAccount(pool.winAccounts[index]);
            }
        }
    }

    function getWinAccountBy(uint256 poolId, address account) external override view returns (WinAccount memory result) {
        if(_isValid(poolId)) {
            Pool storage pool = _pools[poolId];
            uint256 index = pool.winAccountIndexes[account];
            if(index > 0) {
                result = _getWinAccount(pool.winAccounts[index - 1]);
            }
        }
    }

    function _getWinAccount(WinAccount memory winAccount) private view returns (WinAccount memory result) {
        address owner;
        bool claimed;
        if(winAccount.prizeId == 0) {
            owner = winAccount.account;
            claimed = false;
        } else {
            IBoxPrize.Prize memory prize = _boxPrize.getPrize(winAccount.prizeId);
            owner = prize.owner;
            claimed = prize.claimed;
        }
        
        result = WinAccount(
            winAccount.account,
            winAccount.poolId,
            winAccount.prizeId,
            winAccount.amount,
            _isExpired(winAccount.poolId),
            claimed,
            owner
        );
    }

    function getWinEggCount() external override view returns (uint256) {
        uint256 lastEggId = _getLatestEggId();
        if(lastEggId == 0) {
            return 0;
        }

        return _isPublishedEgg(lastEggId) ? lastEggId: lastEggId - 1; 
    }

    function getWinEgg(uint256 eggId) external override view returns (WinEgg memory result) {
        if(_isValidEgg(eggId)) {
            WinEgg memory winEgg = _eggs[eggId].winEgg;

            address owner;
            bool claimed;
            if(winEgg.prizeId == 0) {
                owner = _boxTicket.ownerOf(winEgg.ticketId);
                claimed = false;
            } else {
                IBoxPrize.Prize memory prize = _boxPrize.getPrize(winEgg.prizeId);
                owner = prize.owner;
                claimed = prize.claimed;
            }

            result = WinEgg(
                winEgg.boxId,
                winEgg.ticketId,
                winEgg.prizeId,
                winEgg.amount,
                claimed,
                owner
            );
        }
    }

    function getTicket(uint256 ticketId) external override view returns (IBoxTicket.Ticket memory result) {
        result = _boxTicket.getTicket(ticketId);
    }

    function getTicketIds(address account, uint256 poolId) external override view returns (uint256[] memory) {
        return _boxTicket.getTicketIds(account, poolId);
    }

    function getAccountPoolIds(address account) external override view returns (uint256[] memory) {
        return _boxTicket.getAccountPoolIds(account);
    }

    function getRequestId(uint256 poolId) external override view returns (bytes32) {
        return _isValid(poolId) ? _pools[poolId].requestId : bytes32(uint256(0));
    }

    function isRandomnessReady(uint256 poolId) external override view returns (bool) {
        return _isValid(poolId) ? _isRandomnessReady(poolId) : false;
    }

    function getRequestIdEgg(uint256 eggId) external override view returns (bytes32) {
        return _isValidEgg(eggId) ? _eggs[eggId].requestId : bytes32(uint256(0));
    }

    function isRandomnessReadyEgg(uint256 eggId) external override view returns (bool) {
        return _isValidEgg(eggId) ? _isRandomnessReadyEgg(eggId) : false;
    }

    function getPoolRange() external override view returns (uint256 minId, uint256 maxId) {
        if(_poolIdTracker > MIN_ID) {
            minId = MIN_ID;
            maxId = _getLatestPoolId();
        }
    }

    function getPoolInfo(uint256 poolId) external override view returns (PoolInfo memory result) {
        if(_isValid(poolId)) {
            Pool storage pool = _pools[poolId];

            result = PoolInfo(
                poolId,
                pool.price,
                pool.quantity,
                pool.capacity,
                pool.balance,
                pool.amount,
                pool.accounts.length,
                poolId - MIN_ID + 1,
                pool.published ? pool.awards : _calcAwards(pool),
                _isEnded(poolId),
                pool.published
            );
        }
    }

    function getEggRange() external override view returns (uint256 minId, uint256 maxId) {
        if(_eggIdTracker > 1) {
            minId = 1;
            maxId = _getLatestEggId();
        }
    }

    function getEggInfo(uint256 eggId) external override view returns (EggInfo memory result) {
        if(_isValid(eggId)) {
            Egg storage egg = _eggs[eggId];

            result = EggInfo(
                eggId,
                egg.fromId,
                egg.toId,
                _isEndedEgg(eggId),
                egg.published
            );
        }
    }

    function isExpired(uint256 poolId) external view returns (bool) {
        return _isValid(poolId) ? _isExpired(poolId) : true;
    }

    function _updateCapacity() private {
        if(_capacityGrowDirection) {
            _currentCapacity = Math.min(_currentCapacity + _capacityGrowDelta, MAX_CAPACITY);
        } else {
            _currentCapacity = Math.max(_currentCapacity - _capacityGrowDelta, MIN_CAPACITY);
        }
    }

    function _tryPublish(uint256 poolId) private onlyValid(poolId) onlyEnded(poolId) onlyNotPublished(poolId) {
        require(!_isRandomnessReady(poolId), "BoxPool: randomness is ready");

        bytes32 requestId = _randomAccessor.requestRandom();

        RandomnessUse storage randomnessUse = _randomnessUses[requestId];
        randomnessUse.randomnessType = RandomnessType.Pool;
        randomnessUse.poolId = poolId;

        _pools[poolId].requestId = requestId;

        emit RequestRandom(requestId);
    }

    function _tryPublishEgg(uint256 eggId) private onlyValidEgg(eggId) onlyEndedEgg(eggId) onlyNotPublishedEgg(eggId) {
        require(!_isRandomnessReadyEgg(eggId), "BoxPool: egg randomness is ready");

        bytes32 requestId = _randomAccessor.requestRandom();

        RandomnessUse storage randomnessUse = _randomnessUses[requestId];
        randomnessUse.randomnessType = RandomnessType.Egg;
        randomnessUse.eggId = eggId;

        _eggs[eggId].requestId = requestId;

        emit RequestRandom(requestId);
    }

    function _publish(uint256 poolId) private onlyValid(poolId) onlyEnded(poolId) onlyNotPublished(poolId) {
        require(_isRandomnessReady(poolId), "BoxPool: randomness not ready");

        Pool storage pool = _pools[poolId];

        if(_isValid(poolId - 1)) {
            // 本期开奖前，上期未领取的一等奖、二等奖……普惠奖奖金全部作为本期奖金
            Pool storage lastPool = _pools[poolId - 1];
            pool.amount += lastPool.balance;
            lastPool.balance = 0;
        }

        uint256 ratio = pool.awardsRatios[pool.awardsRatios.length - 1];
        _lastBufferBalance = pool.amount * ratio / BASE_RATIO;

        pool.balance = pool.amount - _lastBufferBalance;
        pool.awards = _calcAwards(pool);

        _drawWinBoxes(pool);
        _drawWinAccounts(pool);
        _collectFee(pool);

        pool.published = true;
        
        emit Published(pool.poolId, pool.poolId - MIN_ID + 1);
    }

    function _drawWinBoxes(Pool storage pool) private {
        uint256[] memory randoms = _randomGenerator.randoms(pool.randomness, pool.fromId, pool.endId, _calcAwardsCount(pool));
        
        uint256 sum = pool.awardsOdds[0];
        uint256 boxId;
        uint256 index;
        uint256 ticketId;
        WinBox memory winBox;
        for(uint256 i = 0; i < randoms.length; i++) {
            if(i == sum && index + 1 < pool.awardsOdds.length - 2) {
                index++;
                sum += pool.awardsOdds[index];
            } 
            
            boxId = randoms[i];
            ticketId = _boxTicket.getTicketId(boxId);
            winBox = WinBox(boxId, ticketId, pool.poolId, 0, pool.awards[index] / pool.awardsOdds[index], index + 1, false, false, address(0));
            pool.winBoxes.push(winBox);
            pool.winBoxIndexes[boxId] = i + 1;
        }
    }

    function _drawWinAccounts(Pool storage pool) private {
        uint256 count = _calcWinAccountCount(pool);
        uint256[] memory randoms = _randomGenerator.randoms(pool.randomness, 1, pool.accounts.length, count);
        
        // 比例：一等奖、二等奖...普惠奖、蓄水池
        uint256 ratio = pool.awardsRatios[pool.awardsRatios.length - 2];
        uint256 amount = pool.amount * ratio / BASE_RATIO / count;

        uint256 index;
        address account;
        WinAccount memory winAccount;
        for(uint256 i = 0; i < randoms.length; i++) {
            index = randoms[i] - 1;
            account = pool.accounts[index];
            winAccount = WinAccount(account, pool.poolId, 0, amount, false, false, address(0));
            pool.winAccounts.push(winAccount);
            pool.winAccountIndexes[account] = i + 1;
        }
    }

    // 收取手续费
    function _collectFee(Pool storage pool) private {
        uint256 feeRatio = pool.distributionRatios[uint256(DistributionType.Fee)];
        uint256 feeAmount = pool.quantity * pool.price * feeRatio / BASE_RATIO;

        _token.safeApprove(address(_feeCollector), feeAmount);
        _feeCollector.collect(feeAmount);
    }

    function _publishEgg(uint256 eggId) private onlyValidEgg(eggId) onlyEnded(eggId) onlyNotPublished(eggId) {
        require(_isRandomnessReadyEgg(eggId), "BoxPool: egg randomness not ready");

        Egg storage egg = _eggs[eggId];

        uint256 count = egg.toId - egg.fromId + 1;
        uint256 random = _randomGenerator.random(egg.randomness);
        uint256 boxId = random % count + egg.fromId;

        // TODO: 价格、彩蛋池比例 目前不能变
        _lastEggBalance += (count * _defaultPrice * _defaultDistributionRatios[uint256(DistributionType.Egg)] / BASE_RATIO);

        uint256 ticketId = _boxTicket.getTicketId(boxId);
        uint256 amount = _calcEggAmount();
        WinEgg memory winEgg = WinEgg(boxId, ticketId, 0, amount, false, address(0));

        egg.winEgg = winEgg;
        egg.published = true;

        _lastEggBalance -= amount;
        // _eggBalance -= amount;
        
        emit EggPublished(egg.eggId, egg.fromId, egg.toId, boxId);
    }

    function _fillRandomness(bytes32 requestId, uint256 randomness, uint256 poolId) private onlyValid(poolId) onlyEnded(poolId) onlyNotPublished(poolId) {
        Pool storage pool = _pools[poolId];
        require(pool.requestId == requestId, "BoxPool: invalid pool requestId");

        pool.randomness = randomness;

        emit FillRandomness(requestId, randomness, poolId);
    }

    function _fillRandomnessEgg(bytes32 requestId, uint256 randomness, uint256 eggId) private onlyValidEgg(eggId) onlyEndedEgg(eggId) onlyNotPublishedEgg(eggId) {
        Egg storage egg = _eggs[eggId];
        require(egg.requestId == requestId, "BoxPool: invalid egg requestId");

        egg.randomness = randomness;

        emit FillRandomnessEgg(requestId, randomness, eggId);
    }

    function _copyArray(uint256[] memory arr) private pure returns (uint256[] memory result) {
        uint256 length = arr.length;
        result = new uint256[](length);
        for(uint256 i = 0; i < length; i++) {
            result[i] = arr[i];
        }
    }

    function _calcDistributionAmount(uint256 amount, uint256[] memory distributionRatios, DistributionType distributionType) private pure returns (uint256) {
        return amount * distributionRatios[uint256(distributionType)] / BASE_RATIO;
    }

    // 计算盲盒奖项奖励
    function _calcAwards(Pool storage pool) private view returns (uint256[] memory) {
        uint256 length = pool.awardsOdds.length - 2;
        uint256[] memory result = new uint256[](length);
        for(uint256 i = 0; i < length; i++) {
            result[i] = pool.amount * pool.awardsRatios[i] / BASE_RATIO;
        }

        return result;
    }

    function _calcAwardsCount(Pool storage pool) private view returns (uint256) {
        // 最后两个是普惠奖和蓄水池
        uint256 length = pool.awardsOdds.length - 2;
        uint256 count;
        for(uint256 i = 0; i < length; i++) {
            count += pool.awardsOdds[i];
        }

        return count;
    }

    function _calcWinAccountCount(Pool storage pool) private view returns (uint256) {
        // 向上取整
        return (pool.accounts.length * pool.accountRatio + BASE_RATIO - 1) / BASE_RATIO;
    }

    function _calcEggAmount() private view returns (uint256) {
        return _lastEggBalance * _eggRatio / BASE_RATIO;
    }

    function _getLatestPoolId() private view returns (uint256) {
        return _poolIdTracker > MIN_ID ? _poolIdTracker - 1 : 0;
    }

    function _getLatestEggId() private view returns (uint256) {
        return _eggIdTracker > 1 ? _eggIdTracker - 1 : 0;
    }

    function _isExpired(uint256 poolId) private view returns (bool) {
        return _isValid(poolId + 1) ? _isEnded(poolId + 1) : false;
    }

    function _isValid(uint256 poolId) private view returns (bool) {
        return poolId >= MIN_ID && poolId < _poolIdTracker;
    }

    function _isValidEgg(uint256 eggId) private view returns (bool) {
        return eggId > 0 && eggId < _eggIdTracker;
    }

    function _isEnded(uint256 poolId) private view returns (bool) {
        return _pools[poolId].quantity == _pools[poolId].capacity;
    }

    function _isEndedEgg(uint256 eggId) private view returns (bool) {
        (, uint256 maxId) = _boxTicket.getBoxRange();
        return _eggs[eggId].toId > 0 && _eggs[eggId].toId <= maxId;
    }

    function _isRandomnessReady(uint256 poolId) private view returns (bool) {
        return _pools[poolId].randomness > 0;
    }

    function _isRandomnessReadyEgg(uint256 eggId) private view returns (bool) {
        return _eggs[eggId].randomness > 0;
    }

    function _isPublished(uint256 poolId) private view returns (bool) {
        return _pools[poolId].published;
    }

    function _isPublishedEgg(uint256 eggId) private view returns (bool) {
        return _eggs[eggId].published;
    }
}