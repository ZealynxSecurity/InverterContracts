// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import { ERC20Issuance_v1 } from "@ex/token/ERC20Issuance_v1.sol";
import { IERC20Issuance_blacklist_v1 } from "./interfaces/IERC20Issuance_blacklist_v1.sol";

/**
 * @title   Blacklist-enabled ERC20 Issuance Token
 * @notice  ERC20 token with minting and blacklist capabilities
 * @dev     Extends ERC20Issuance_v1 with blacklist functionality
 * @author  Zealynx Security
 */
contract ERC20Issuance_blacklist_v1 is 
    IERC20Issuance_blacklist_v1, 
    ERC20Issuance_v1 
{
    mapping(address => bool) public blacklist;

    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint256 initialSupply,
        address initialAdmin_
    ) ERC20Issuance_v1(name, symbol, decimals, initialSupply, initialAdmin_) {}

    function isBlacklisted(address account) external view override returns (bool) {
        return blacklist[account];
    }

    function addToBlacklist(address account) external override {
        blacklist[account] = true;
    }

    function removeFromBlacklist(address account) external override {
        blacklist[account] = false;
    }
}