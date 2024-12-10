// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Imports

// Internal
import {IERC20Issuance_v1} from "@ex/token/IERC20Issuance_v1.sol";

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
 * @custom:version   1.0.0
 *
 * @custom:standard-version  1.0.0
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

    /// @notice Emitted when a blacklist manager role is granted or revoked
    /// @param account_ The address that was granted or revoked the role
    /// @param allowed_ Whether the role was granted (true) or revoked (false)
    event BlacklistManagerUpdated(address indexed account_, bool allowed_);

    //--------------------------------------------------------------------------
    // Errors

    /// @notice Thrown when attempting to blacklist the zero address
    error ERC20Issuance_Blacklist_ZeroAddress();

    /// @notice Thrown when caller does not have blacklist manager role
    error ERC20Issuance_Blacklist_NotBlacklistManager();

    /// @notice Thrown when attempting to mint tokens to a blacklisted address
    error ERC20Issuance_Blacklist_BlacklistedAddress(address account);

    /// @notice Thrown when batch operation exceeds the maximum allowed size
    error ERC20Issuance_Blacklist_BatchLimitExceeded(uint provided, uint limit);

    //--------------------------------------------------------------------------
    // External Functions

    /// @notice Checks if an address is blacklisted
    /// @param account_ The address to check
    /// @return isBlacklisted_ True if address is blacklisted
    function isBlacklisted(address account_)
        external
        view
        returns (bool isBlacklisted_);

    /// @notice Checks if an address is a blacklist manager
    /// @param account_ The address to check
    /// @return isBlacklistManager_ True if address is a blacklist manager
    function isBlacklistManager(address account_)
        external
        view
        returns (bool isBlacklistManager_);

    /// @notice Adds an address to blacklist
    /// @param account_ The address to blacklist
    /// @dev May revert with ERC20Issuance_Blacklist_ZeroAddress
    function addToBlacklist(address account_) external;

    /// @notice Removes an address from blacklist
    /// @param account_ The address to remove
    /// @dev May revert with ERC20Issuance_Blacklist_ZeroAddress
    function removeFromBlacklist(address account_) external;

    /// @notice Adds multiple addresses to blacklist
    /// @param accounts_ Array of addresses to blacklist
    /// @dev May revert with ERC20Issuance_Blacklist_ZeroAddress
    ///      The array size should not exceed the block gas limit. Consider using
    ///      smaller batches (e.g., 100-200 addresses) to ensure transaction success.
    function addToBlacklistBatchAddresses(address[] memory accounts_)
        external;

    /// @notice Removes multiple addresses from blacklist
    /// @param accounts_ Array of addresses to remove
    /// @dev May revert with ERC20Issuance_Blacklist_ZeroAddress
    ///      The array size should not exceed the block gas limit. Consider using
    ///      smaller batches (e.g., 100-200 addresses) to ensure transaction success.
    function removeFromBlacklistBatchAddresses(address[] calldata accounts_)
        external;

    /// @notice Sets or revokes blacklist manager role for an address
    /// @param manager_ The address to grant or revoke the role from
    /// @param allowed_ Whether to grant (true) or revoke (false) the role
    /// @dev May revert with ERC20Issuance_Blacklist_ZeroAddress
    function setBlacklistManager(address manager_, bool allowed_) external;
}
