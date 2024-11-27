// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

/**
* @title   Oracle Price Interface
* @notice  Interface for oracle price feed calculations
* @dev     Designed to facilitate various oracle price implementations
* @custom:security-contact security@inverter.network
* @author  Zealynx Security
*/
interface IOraclePrice_v1 {
   //--------------------------------------------------------------------------
   // Functions

   /// @notice Gets current price for token issuance
   /// @return price_ Current price for buying tokens
   function getPriceForIssuance() external view returns (uint256 price_);

   /// @notice Gets current price for token redemption
   /// @return price_ Current price for selling tokens
   function getPriceForRedemption() external view returns (uint256 price_);
}