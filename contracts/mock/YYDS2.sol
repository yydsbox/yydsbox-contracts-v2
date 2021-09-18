// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract YYDS2 is ERC20, Ownable {
    address private constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    // 转入白名单
    mapping (address => bool) private _inWhiteList;
    // 转出白名单
    mapping (address => bool) private _outWhiteList;
    
    constructor() ERC20("YYDS2", "YYDS2") {
        address sender = _msgSender();
        _mint(sender, 1e34);

        _inWhiteList[sender] = true;
        _outWhiteList[sender] = true;

        // 燃烧地址添加到白名单
        _inWhiteList[BURN_ADDRESS] = true;
    }

    function addInWhiteList(address account) external onlyOwner {
        _inWhiteList[account] = true;
    }

    function addOutWhiteList(address account) external onlyOwner {
        _outWhiteList[account] = true;
    }

    function removeInWhiteList(address account) external onlyOwner {
        _inWhiteList[account] = false;
    }

    function removeOutWhiteList(address account) external onlyOwner {
        _outWhiteList[account] = false;
    }

    function isInWhiteList(address account) external view returns (bool) {
        return _inWhiteList[account];
    }

    function isOutWhiteList(address account) external view returns (bool) {
        return _outWhiteList[account];
    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _whiteTransfer(_msgSender(), recipient, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        _whiteTransfer(sender, recipient, amount);

        uint256 currentAllowance = allowance(sender, _msgSender());
        require(currentAllowance >= amount, "YYDS2: transfer amount exceeds allowance");
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }

        return true;
    }

    function _whiteTransfer(address sender, address recipient, uint256 amount) internal {
        if(_inWhiteList[sender] || _outWhiteList[recipient]) {
            _transfer(sender, recipient, amount);
        } else {
            _transfer(sender, BURN_ADDRESS, amount * 10 / 100);
            _transfer(sender, recipient, amount * 90 / 100);
        }
    }
}
