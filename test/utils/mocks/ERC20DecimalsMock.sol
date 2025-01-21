// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "./ERC20Mock.sol";

contract ERC20DecimalsMock is ERC20Mock {
    uint8 private _decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) 
        ERC20Mock(name_, symbol_) 
    {
        _decimals = decimals_;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}
