// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

import "./IBoxTicket.sol";

contract BoxTicket is IBoxTicket, Ownable, ERC721Enumerable {
    uint256 private constant MIN_ID = 1e4;
    address public minter;

    uint256 private _ticketIdTracker = MIN_ID;
    uint256 private _boxIdTracker = MIN_ID;

    mapping(uint256 => Ticket) private _tickets;

    mapping(uint256 => mapping(address => uint256[])) private _ownerTicketIds;
    mapping(address => uint256[]) private _ownerPoolIds;

    constructor() ERC721("YYDSBOX Ticket", "YBT") {}

    modifier onlyMinter() {
        require(_msgSender() == minter, "BoxTicket: not the minter");
        _;
    }

    function setMinter(address minter_) external onlyOwner {
        require(minter_ != address(0), "BoxTicket: minter invalid");
        require(minter == address(0), "BoxTicket: minter already exists");

        minter = minter_;

        renounceOwnership();
    }

    function create(address account, uint256 poolId, uint256 count) external override onlyMinter returns (uint256 ticketId, uint256 fromId, uint256 toId) {
        ticketId = _ticketIdTracker++;

        _mint(account, ticketId);

        fromId = _boxIdTracker;
        toId = _boxIdTracker + count - 1;

        _boxIdTracker += count;

        Ticket memory ticket = Ticket(ticketId, poolId, fromId, toId, account);
        _tickets[ticketId] = ticket;
        _ownerTicketIds[poolId][account].push(ticketId);

        uint256 index = _findIndex(_ownerPoolIds[account], poolId);
        if (index == 0) {
            _ownerPoolIds[account].push(poolId);
        }
    }

    function exists(uint256 ticketId) external override view returns (bool) {
        return _exists(ticketId);
    }

    function isValid(uint256 boxId) external override view returns (bool) {
        return _isValid(boxId);
    }

    function getBoxRange() external override view returns (uint256 minId, uint256 maxId) {
        if(_boxIdTracker > MIN_ID) {
            minId = MIN_ID;
            maxId = _boxIdTracker - 1;
        }
    }

    function getMinBoxId() external override pure returns (uint256) {
        return MIN_ID;
    }

    function getTicket(uint256 ticketId) external override view returns (Ticket memory result) {
        if(_exists(ticketId)) {
            result = _tickets[ticketId];
        }
    }

    function getTicketByBox(uint256 boxId) external override view returns (Ticket memory result) {
        uint256 ticketId = _isValid(boxId) ? _findTicketId(boxId) : 0;
        if(_exists(ticketId)) {
            result = _tickets[ticketId];
        }
    }

    function getTicketId(uint256 boxId) external override view returns (uint256) {
        return _isValid(boxId) ? _findTicketId(boxId) : 0;
    }

    function getTicketIds(address account, uint256 poolId) external override view returns (uint256[] memory) {
        return _ownerTicketIds[poolId][account];
    }

    function getAccountPoolIds(address account) external override view returns (uint256[] memory) {
        return _ownerPoolIds[account];
    }

    function _transfer(address from, address to, uint256 tokenId) internal override {
        super._transfer(from, to, tokenId);

        _tickets[tokenId].owner = to;

        uint256 poolId = _tickets[tokenId].poolId;
        uint256[] storage ticketIds = _ownerTicketIds[poolId][from];

        uint256 index = _findIndex(ticketIds, tokenId) - 1;
        _removeValue(ticketIds, index);

        if(ticketIds.length == 0) {
            index = _findIndex(_ownerPoolIds[from], poolId) - 1;
            _removeValue(_ownerPoolIds[from], index);
        }

        _ownerTicketIds[poolId][to].push(tokenId);
        if(_ownerPoolIds[to].length == 0) {
            _ownerPoolIds[to].push(poolId);
        }
    }

    function _isValid(uint256 boxId) private view returns (bool) {
        return boxId >= MIN_ID && boxId < _boxIdTracker;
    }

    function _findTicketId(uint256 boxId) private view returns (uint256) {
        uint256 left = MIN_ID;
        uint256 right = _ticketIdTracker - 1;
        uint256 mid;

        while(left <= right) {
            mid = (right + left) / 2 | 0;

            if(left == mid && boxId <= _tickets[left].toId) {
                break;
            } else if(left == mid && boxId <= _tickets[right].toId) {
                mid = right;
                break;
            }
            
            if(_tickets[mid].toId < boxId) {
                left = mid;
            } else {
                right = mid;
            }
        }
        
        return mid;
    }

    function _findIndex(uint256[] memory array, uint256 value) private pure returns (uint256) {
        for(uint256 i = 0; i < array.length; i++) {
            if(array[i] == value) {
                return i + 1;
            }
        }

        return 0;
    }

    function _removeValue(uint256[] storage array, uint256 index) private {
        uint256 lastIndex = array.length - 1;
        uint256 lastValue = array[lastIndex];
        array[lastIndex] = array[index];
        array[index] = lastValue;
        array.pop();
    }
}
