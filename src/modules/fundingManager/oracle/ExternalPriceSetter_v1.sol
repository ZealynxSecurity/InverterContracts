// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import { IOraclePrice_v1 } from "./interfaces/IOraclePrice_v1.sol";
import { Ownable2StepUpgradeable } from "@oz-up/access/Ownable2StepUpgradeable.sol";

/**
* @title   Oracle Price Implementation for USP Token
* @notice  Manages and provides daily price data for USP token operations
* @dev     Maintains separate prices for issuance (buying) and redemption (selling)
* @custom:security-contact security@inverter.network
* @author  Inverter Network
*/

// @audit-info  change name to ExternalPrice 
contract ExternalPriceSetter_v1 is IOraclePrice_v1, Ownable2StepUpgradeable { 
    // State variables
    uint256 private _issuancePrice;
    uint256 private _redemptionPrice;

    // Storage gap for upgradeable contracts
    uint256[50] private __gap;

    // Events
    event IssuancePriceSet(uint256 price);
    event RedemptionPriceSet(uint256 price);

    // Errors
    error InvalidPrice();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize function
    function initialize() external initializer {
        __Ownable2Step_init();
    }

    /// @notice Sets the issuance price
    /// @param price_ New issuance price
    function setIssuancePrice(uint256 price_) external onlyOwner {
        if (price_ == 0) revert InvalidPrice();
        _issuancePrice = price_;
        emit IssuancePriceSet(price_);
    }

    /// @notice Sets the redemption price
    /// @param price_ New redemption price
    function setRedemptionPrice(uint256 price_) external onlyOwner {
        if (price_ == 0) revert InvalidPrice();
        _redemptionPrice = price_;
        emit RedemptionPriceSet(price_);
    }

    /// @inheritdoc IOraclePrice_v1
    function getPriceForIssuance() external view returns (uint256) {
        return _issuancePrice;
    }

    /// @inheritdoc IOraclePrice_v1
    function getPriceForRedemption() external view returns (uint256) {
        return _redemptionPrice;
    }
}