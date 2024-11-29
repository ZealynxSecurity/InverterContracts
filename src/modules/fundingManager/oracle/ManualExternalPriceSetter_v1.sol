// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

//--------------------------------------------------------------------------
// Imports

// Internal
import { IOraclePrice_v1 } from "./interfaces/IOraclePrice_v1.sol";
import { IManualExternalPriceSetter_v1 } from "./interfaces/IManualExternalPriceSetter_v1.sol";

// External
import { Ownable2Step } from "@oz/access/Ownable2Step.sol";
import { Ownable } from "@oz/access/Ownable.sol";

/**
 * @title   Manual External Price Oracle Implementation
 *
 * @notice  This contract provides a manual price feed mechanism for token 
 *          operations, allowing authorized users to set and update prices for
 *          both issuance (buying) and redemption (selling) operations.
 *
 * @dev     This contract inherits functionalities from:
 *              - Ownable2Step
 *          The contract maintains two separate price feeds:
 *              1. Issuance price for token minting/buying
 *              2. Redemption price for token burning/selling
 *          Both prices are manually set by the contract owner and must be
 *          non-zero values.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @author  Zealynx Security
 */

contract ManualExternalPriceSetter_v1 is IManualExternalPriceSetter_v1, Ownable2Step, IOraclePrice_v1 { 
    //--------------------------------------------------------------------------
    // State Variables

    uint256 private _issuancePrice;
    uint256 private _redemptionPrice;

    // Storage gap for upgradeable contracts
    uint256[50] private __gap;

    //--------------------------------------------------------------------------
    // Constructor

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() Ownable(msg.sender) {}

    //--------------------------------------------------------------------------
    // External Functions

    /// @inheritdoc IManualExternalPriceSetter_v1
    function setIssuancePrice(uint256 price_) external onlyOwner {
        if (price_ == 0) revert ExternalPriceSetter__InvalidPrice();
        _issuancePrice = price_;
        emit PriceSet(price_);
    }

    /// @inheritdoc IManualExternalPriceSetter_v1
    function setRedemptionPrice(uint256 price_) external onlyOwner {
        if (price_ == 0) revert ExternalPriceSetter__InvalidPrice();
        _redemptionPrice = price_;
        emit PriceSet(price_);
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