// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import { IERC20Issuance_v1 } from "@ex/token/IERC20Issuance_v1.sol";

/**
* @title   Blacklist-enabled ERC20 Issuance Token Interface
* @notice  Extends ERC20 Issuance with blacklist functionality
* @dev     Adds blacklist management to base token functionality
* @custom:security-contact security@inverter.network
* @author  Zealynx Security
*/
interface IERC20Issuance_blacklist_v1 is IERC20Issuance_v1 {
    
   /// @notice Checks if an address is blacklisted
   /// @param account_ The address to check
   /// @return isBlacklisted_ True if address is blacklisted
   function isBlacklisted(
       address account_
   ) external view returns (bool isBlacklisted_);

   /// @notice Adds an address to blacklist
   /// @param account_ The address to blacklist
   function addToBlacklist(address account_) external;

   /// @notice Removes an address from blacklist
   /// @param account_ The address to remove
   function removeFromBlacklist(address account_) external;

   /// @notice Adds multiple addresses to blacklist
   /// @param accounts_ Array of addresses to blacklist
   function addToBlacklistBatchAddresses(
       address[] memory accounts_
   ) external;

   /// @notice Removes multiple addresses from blacklist
   /// @param accounts_ Array of addresses to remove
   function removeFromBlacklistBatchAddresses(
       address[] calldata accounts_
   ) external;
}