// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../token/IBoxTicket.sol";

interface IBoxPool {
    struct PoolInfo {
        uint256 poolId;
        uint256 price;
        uint256 quantity;
        uint256 capacity;
        uint256 balance;
        uint256 amount;
        uint256 accountCount;
        uint256 index;
        uint256[] awards;
        bool ended;
        bool published;
    }

    struct EggInfo {
        uint256 eggId;
        uint256 fromId;
        uint256 toId;
        bool ended;
        bool published;
    }

    struct WinBox {
        uint256 boxId;
        uint256 ticketId;
        uint256 poolId;
        uint256 prizeId;
        uint256 amount;
        uint256 index;
        bool expired;
        bool claimed;
        address owner;
    }

    struct WinAccount {
        address account;
        uint256 poolId;
        uint256 prizeId;
        uint256 amount;
        bool expired;
        bool claimed;
        address owner;
    }

    struct WinEgg {
        uint256 boxId;
        uint256 ticketId;
        uint256 prizeId;
        uint256 amount;
        bool claimed;
        address owner;
    }

    event Swap(uint256 indexed poolId, uint256 ticketId, uint256 fromId, uint256 toId);
    event Open(uint256 prizeId, uint256 amount);
    event Buyback(uint256 prizeId, uint256 amount);

    // 购买
    function swap(uint256 poolId, uint256 count) external;
    // 领取盲盒奖
    function claimBox(uint256 boxId) external;
    // 领取普惠奖
    function claimPublic(uint256 poolId) external;
    // 领取彩蛋
    function claimEgg(uint256 eggId) external;
    // 回购
    function buyback(uint256 prizeId) external;

    function getLatestPool() external view returns (uint256 poolId, bool ended, bool published);
    function getLatestEgg() external view returns (uint256 eggId, bool ended, bool published);

    // 盲盒池信息
    function getPoolRange() external view returns (uint256 minId, uint256 maxId);
    function getPoolInfo(uint256 poolId) external view returns (PoolInfo memory result);
    // 彩蛋信息
    function getEggRange() external view returns (uint256 minId, uint256 maxId);
    function getEggInfo(uint256 eggId) external view returns (EggInfo memory result);

    // 一等奖、二等奖、三等奖
    function getWinBoxes(uint256 poolId) external view returns (WinBox[] memory result);

    // 普惠奖
    function getWinAccountCount(uint256 poolId) external view returns (uint256);
    function getWinAccount(uint256 poolId, uint256 index) external view returns (WinAccount memory result);
    function getWinAccountBy(uint256 poolId, address account) external view returns (WinAccount memory result);

    // 彩蛋奖
    function getWinEggCount() external view returns (uint256);
    function getWinEgg(uint256 eggId) external view returns (WinEgg memory result);

    // 票据信息
    function getTicket(uint256 ticketId) external view returns (IBoxTicket.Ticket memory result);
    function getTicketIds(address account, uint256 poolId) external view returns (uint256[] memory);

    // 获取用户参与的盲盒池ID
    function getAccountPoolIds(address account) external view returns (uint256[] memory);
}