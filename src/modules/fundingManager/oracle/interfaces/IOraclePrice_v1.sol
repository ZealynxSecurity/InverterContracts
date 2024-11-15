// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

/**
* @title   Oracle Price Interface
* @notice  Interface for oracle price feed calculations
* @dev     Designed to facilitate various oracle price implementations
* @author  Zealynx Security
*/
interface IOraclePrice_v1 {

   function getPurchaseReturn() external view returns (uint256);
   function getSaleReturn() external view returns (uint256);
   function updatePrice(uint256 newPrice) external;
}