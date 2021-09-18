// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

import "./IBoxPrize.sol";

contract BoxPrize is IBoxPrize, Ownable, ERC721Enumerable {
    address public minter;

    uint256 private _prizeIdTracker = 1e4;
    mapping(uint256 => Prize) private _prizes;

    constructor() ERC721("YYDSBOX Prize", "YBP") {}

    modifier onlyMinter() {
        require(_msgSender() == minter, "BoxPrize: not the minter");
        _;
    }

    function setMinter(address minter_) external onlyOwner {
        require(minter_ != address(0), "BoxPrize: minter invalid");
        require(minter == address(0), "BoxPrize: minter already exists");

        minter = minter_;

        renounceOwnership();
    }

    function create(address owner, uint256 amount) external override onlyMinter returns (uint256) {
        uint256 prizeId = _prizeIdTracker++;

        _mint(owner, prizeId);

        Prize memory prize = Prize(
            prizeId,
            amount,
            owner,
            false
            // ,false
        );
        _prizes[prizeId] = prize;

        return prizeId;
    }

    function setClaimed(uint256 prizeId) external override onlyMinter {
        require(_exists(prizeId), "BoxPrize: prize not exists");

        _prizes[prizeId].claimed = true;
    }

    function exists(uint256 prizeId) external override view returns (bool) {
        return _exists(prizeId);
    }

    function isClaimed(uint256 prizeId) external override view returns (bool) {
        return _exists(prizeId) ? _prizes[prizeId].claimed : false;
    }

    // function isExpired(uint256 prizeId) external override view returns (bool) {
    //     return _exists(prizeId) ? _isExpired(prizeId) : false;
    // }

    function getPrize(uint256 prizeId) external override view returns (Prize memory result) {
        if(_exists(prizeId)) {
            Prize memory prize = _prizes[prizeId];

            result = Prize(
                prize.prizeId,
                prize.amount,
                prize.owner,
                prize.claimed
                // ,_isExpired(prizeId)
            );
        }
    }

    function _transfer(address from, address to, uint256 tokenId) internal override {
        super._transfer(from, to, tokenId);

        if(!_prizes[tokenId].claimed) {
            _prizes[tokenId].owner = to;
        }
    }
}