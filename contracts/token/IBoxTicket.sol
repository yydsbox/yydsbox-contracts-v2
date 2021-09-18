// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

interface IBoxTicket is IERC721, IERC721Metadata, IERC721Enumerable {
    struct Ticket {
        uint256 ticketId;
        uint256 poolId;
        uint256 fromId;
        uint256 toId;
        address owner;
    }

    function create(address account, uint256 poolId, uint256 count) external returns (uint256 ticketId, uint256 fromId, uint256 toId);

    function exists(uint256 ticketId) external view returns (bool);
    function isValid(uint256 boxId) external view returns (bool);
    function getBoxRange() external view returns (uint256 minId, uint256 maxId);
    function getMinBoxId() external pure returns (uint256);
    function getTicket(uint256 ticketId) external view returns (Ticket memory result);
    function getTicketByBox(uint256 boxId) external view returns (Ticket memory result);
    function getTicketId(uint256 boxId) external view returns (uint256);
    function getTicketIds(address account, uint256 poolId) external view returns (uint256[] memory);
    function getAccountPoolIds(address account) external view returns (uint256[] memory);
}