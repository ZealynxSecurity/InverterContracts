// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

/**
 * @title   Oracle Price Interface
 *
 * @notice  Interface for oracle price feed calculations that provides a standardized
 *          way to query token prices for both issuance and redemption operations.
 *
 * @dev     Designed to facilitate various oracle price implementations. Each
 *          implementation must provide methods to get current prices for both
 *          buying (issuance) and selling (redemption) operations.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @author  Zealynx Security
 */
interface IOraclePrice_v1 {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Thrown when price retrieval fails
    error OraclePrice__PriceRetrievalFailed();

    /// @notice Thrown when price returned is zero
    error OraclePrice__ZeroPrice();

    //--------------------------------------------------------------------------
    // External Functions

    /// @notice Gets current price for token issuance
    /// @return price_ Current price for buying tokens
    /// @dev May revert with OraclePrice__PriceRetrievalFailed or OraclePrice__ZeroPrice
    function getPriceForIssuance() external view returns (uint256 price_);

    /// @notice Gets current price for token redemption
    /// @return price_ Current price for selling tokens
    /// @dev May revert with OraclePrice__PriceRetrievalFailed or OraclePrice__ZeroPrice
    function getPriceForRedemption() external view returns (uint256 price_);
}