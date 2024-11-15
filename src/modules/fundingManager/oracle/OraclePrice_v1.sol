// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import { IOraclePrice_v1 } from "./interfaces/IOraclePrice_v1.sol";

/**
 * @title   Oracle Price Implementation
 * @notice  Implements oracle price feed functionality
 * @dev     Provides price calculations for the Funding Manager
 * @author  Zealynx Security
 */
contract OraclePrice_v1 is IOraclePrice_v1 {

    uint256 public price;

    function getPurchaseReturn() external view override returns (uint256) {
        return price;
    }

    function getSaleReturn() external view override returns (uint256) {
        return price;
    }

    function updatePrice(uint256 newPrice) external override {
        price = newPrice;
    }
}