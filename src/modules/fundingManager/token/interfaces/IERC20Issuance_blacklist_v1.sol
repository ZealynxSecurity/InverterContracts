// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import { IERC20Issuance_v1 } from "@ex/token/IERC20Issuance_v1.sol";

/**
 * @title   ERC20 Issuance Token with Blacklist Interface
 *
 * @notice  Interface for an ERC20 token that extends standard issuance functionality
 *          with blacklisting capabilities, allowing for address-based access control
 *          to token operations.
 *
 * @dev     This interface inherits from:
 *              - IERC20Issuance_v1
 *          Key features:
 *              - Individual address blacklisting
 *              - Batch blacklist operations
 *              - Blacklist status queries
 *          All blacklist operations should be restricted to authorized roles
 *          (e.g., owner or admin) in the implementation.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @author  Zealynx Security
 */
interface IERC20Issuance_Blacklist_v1 is IERC20Issuance_v1 {
    //--------------------------------------------------------------------------
    // Events

    /// @notice Emitted when an address is added to the blacklist
    /// @param account_ The address that was blacklisted
    event AddedToBlacklist(address indexed account_);

    /// @notice Emitted when an address is removed from the blacklist
    /// @param account_ The address that was removed from blacklist
    event RemovedFromBlacklist(address indexed account_);

    /// @notice Emitted when an address is added to the blacklist
    /// @param account The address that was blacklisted
    event AddressBlacklisted(address indexed account);

    /// @notice Emitted when an address is removed from the blacklist
    /// @param account The address that was removed from the blacklist
    event AddressUnblacklisted(address indexed account);

    //--------------------------------------------------------------------------
    // Errors

    /// @notice Thrown when attempting to blacklist the zero address
    error ERC20Issuance__ZeroAddress();

    /// @notice Thrown when attempting to blacklist an already blacklisted address
    error ERC20Issuance__AlreadyBlacklisted();

    /// @notice Thrown when attempting to unblacklist an address that is not blacklisted
    error ERC20Issuance__NotBlacklisted();

    /// @notice Thrown when attempting to blacklist an address that is already blacklisted
    error ERC20Issuance__AddressAlreadyBlacklisted(address account);

    /// @notice Thrown when batch operation exceeds the maximum allowed size
    error ERC20Issuance__BatchLimitExceeded(uint256 provided, uint256 limit);

    /// @notice Thrown when attempting to mint tokens to a blacklisted address
    error ERC20Issuance__BlacklistedAddress(address account);

    //--------------------------------------------------------------------------
    // External Functions
    
    /// @notice Checks if an address is blacklisted
    /// @param account_ The address to check
    /// @return isBlacklisted_ True if address is blacklisted
    function isBlacklisted(
        address account_
    ) external view returns (bool isBlacklisted_);

    /// @notice Adds an address to blacklist
    /// @param account_ The address to blacklist
    /// @dev May revert with ERC20Issuance__ZeroAddress or ERC20Issuance__AlreadyBlacklisted
    function addToBlacklist(address account_) external;

    /// @notice Removes an address from blacklist
    /// @param account_ The address to remove
    /// @dev May revert with ERC20Issuance__ZeroAddress or ERC20Issuance__NotBlacklisted
    function removeFromBlacklist(address account_) external;

    /// @notice Adds multiple addresses to blacklist
    /// @param accounts_ Array of addresses to blacklist
    /// @dev May revert with ERC20Issuance__ZeroAddress or ERC20Issuance__AlreadyBlacklisted
    ///      The array size should not exceed the block gas limit. Consider using
    ///      smaller batches (e.g., 100-200 addresses) to ensure transaction success.
    function addToBlacklistBatchAddresses(
        address[] memory accounts_
    ) external;

    /// @notice Removes multiple addresses from blacklist
    /// @param accounts_ Array of addresses to remove
    /// @dev May revert with ERC20Issuance__ZeroAddress or ERC20Issuance__NotBlacklisted
    ///      The array size should not exceed the block gas limit. Consider using
    ///      smaller batches (e.g., 100-200 addresses) to ensure transaction success.
    function removeFromBlacklistBatchAddresses(
        address[] calldata accounts_
    ) external;
}