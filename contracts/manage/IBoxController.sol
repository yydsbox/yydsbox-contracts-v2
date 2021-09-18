// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IBoxController {
    event Created(uint256 indexed poolId, uint256 index);
    event Published(uint256 indexed poolId, uint256 index);

    event EggCreated(uint256 indexed eggId, uint256 fromId, uint256 toId);
    event EggPublished(uint256 indexed eggId, uint256 fromId, uint256 toId, uint256 winId);

    event RequestRandom(bytes32 requestId);
    event FillRandomness(bytes32 requestId, uint256 randomness, uint256 poolId);
    event FillRandomnessEgg(bytes32 requestId, uint256 randomness, uint256 poolId);

    function token() external view returns (address);
    function boxTicket() external view returns (address);
    function boxPrize() external view returns (address);

    function randomAccessor() external view returns (address);
    function randomGenerator() external view returns (address);
    function feeCollector() external view returns (address);

    // 默认参数：价格、奖项数量、奖金比例、蓄水池资金作为下期奖金的比例
    function getDefault() external view returns (uint256 price, uint256[] memory distributionRatios, uint256[] memory awardsOdds, uint256[] memory awardsRatios, uint256 bufferRatio, uint256 accountRatio);
    // 下期将增加的容量
    function capacityMeta() external view returns (uint256 growDelta, bool growDirection);
    // 彩蛋参数：多少个盲盒开出1个彩蛋，奖金比例
    function eggMeta() external view returns (uint256 odds, uint256 ratio);

    function setRandomAccessor(address randomAccessor_) external;
    function setRandomGenerator(address randomGenerator_) external;
    function setFeeCollector(address feeCollector_) external;

    // 设置默认参数：价格、奖项数量、奖金比例、蓄水池资金作为下期奖金的比例
    function setDefault(uint256 price, uint256[] memory distributionRatios, uint256[] memory awardsOdds, uint256[] memory awardsRatios, uint256 bufferRatio, uint256 accountRatio) external;
    // 设置容量参数：容量增量、增加还是减少
    function setCapacityMeta(uint256 growDelta, bool growDirection) external;
    // 设置彩蛋参数：多少个盲盒开出1个彩蛋，奖金比例
    function setEggMeta(uint256 odds, uint256 ratio) external;

    function create() external;
    function createEgg() external;

    // 开奖
    function canPublish() external view returns (bool);
    function tryPublish() external;
    function publish() external;
    
    function isRandomnessReady(uint256 poolId) external view returns (bool);
    function getRequestId(uint256 poolId) external view returns (bytes32);

    // 开彩蛋
    function canPublishEgg() external view returns (bool);
    function tryPublishEgg() external;
    function publishEgg() external;

    function isRandomnessReadyEgg(uint256 eggId) external view returns (bool);
    function getRequestIdEgg(uint256 eggId) external view returns (bytes32);
}