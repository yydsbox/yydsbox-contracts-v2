// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

interface IBoxPrize is IERC721, IERC721Metadata {
    struct Prize {
        uint256 prizeId;             // tokenId
        uint256 amount;              // 奖金数量
        address owner;               // 所有者
        bool claimed;                // 是否已领取
    }

    function create(address owner, uint256 amount) external returns (uint256);
    function setClaimed(uint256 prizeId) external;

    function exists(uint256 prizeId) external view returns (bool);
    function isClaimed(uint256 prizeId) external view returns (bool);
    function getPrize(uint256 prizeId) external view returns (Prize memory result);
}