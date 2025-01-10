// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal
import {IOraclePrice_v1} from "@lm/interfaces/IOraclePrice_v1.sol";

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
 * @custom:version  v1.0.0
 *
 * @custom:standard-version v1.0.0
 *
 * @author  Zealynx Security
 */
interface ILM_ManualExternalPriceSetter_v1 is IOraclePrice_v1 {
    // -------------------------------------------------------------------------

    // Events

    /// @notice	Emitted when an issuance price is set.
    /// @param	price_ The price that was set.
    event IssuancePriceSet(uint indexed price_);

    /// @notice	Emitted when a redemption price is set.
    /// @param	price_ The price that was set.
    event RedemptionPriceSet(uint indexed price_);

    // -------------------------------------------------------------------------

    // Errors

    /// @notice Thrown when attempting to set a price to zero.
    error Module__LM_ExternalPriceSetter__InvalidPrice();

    // -------------------------------------------------------------------------

    // External Functions

    /// @notice	Sets the issuance price.
    /// @dev    The price_ parameter should be provided with the same number
    ///         of decimals as the collateral token. For example, if the
    ///         collateral token has 6 decimals and the price is 1.5, input
    ///         should be 1500000.
    /// @param	price_ The price to set.
    function setIssuancePrice(uint price_) external;

    /// @notice	Sets the redemption price.
    /// @dev    The price_ parameter should be provided with the same number of
    ///         decimals as the issuance token. For example, if the issuance
    ///         token has 18 decimals and the price is 1.5, input should be
    ///         1500000000000000000.
    /// @param	price_ The price to set.
    function setRedemptionPrice(uint price_) external;

    /// @notice	Sets both issuance and redemption prices atomically.
    /// @dev    Both prices must be non-zero. The issuancePrice_ should be in
    ///         collateral token decimals and redemptionPrice_ in issuance token
    ///         decimals.
    /// @param	issuancePrice_ The issuance price to set.
    /// @param	redemptionPrice_ The redemption price to set.
    function setIssuanceAndRedemptionPrice(
        uint issuancePrice_,
        uint redemptionPrice_
    ) external;
}
