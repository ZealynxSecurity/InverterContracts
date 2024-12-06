// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Imports

// Internal
import {IOraclePrice_v1} from
    "src/modules/fundingManager/oracle/interfaces/IOraclePrice_v1.sol";

/**
 * @title   Manual External Price Oracle Interface
 *
 * @notice  Interface for the manual price feed mechanism that allows setting
 *          and updating prices for token issuance and redemption operations.
 *
 * @dev     This interface extends IOraclePrice_v1 and adds functionality for
 *          manually setting prices. Both prices (issuance and redemption) must
 *          be non-zero values and can only be set by the contract owner.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @custom:version   1.0.0
 *
 * @custom:standard-version  1.0.0
 *
 * @author  Zealynx Security
 */
interface ILM_ManualExternalPriceSetter_v1 is IOraclePrice_v1 {
    //--------------------------------------------------------------------------
    // Events

    /// @notice Emitted when an issuance price is set
    /// @param  price The new price that was set
    /// @param  timestamp The timestamp when the price was updated
    event IssuancePriceSet(uint indexed price, uint indexed timestamp);

    /// @notice Emitted when a redemption price is set
    /// @param  price The new price that was set
    /// @param  timestamp The timestamp when the price was updated
    event RedemptionPriceSet(uint indexed price, uint indexed timestamp);

    //--------------------------------------------------------------------------
    // Errors

    /// @notice Thrown when attempting to set a price to zero
    error Module__LM_ExternalPriceSetter__InvalidPrice();

    //--------------------------------------------------------------------------
    // External Functions

    /// @notice Sets the issuance price
    /// @dev Price must be non-zero
    /// @param price_ New issuance price (must be non-zero)
    function setIssuancePrice(uint price_) external;

    /// @notice Sets the redemption price
    /// @dev Price must be non-zero
    /// @param price_ New redemption price (must be non-zero)
    function setRedemptionPrice(uint price_) external;
}
