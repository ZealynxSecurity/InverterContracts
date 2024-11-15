// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import { IERC20Issuance_v1 } from "@ex/token/IERC20Issuance_v1.sol";

/**
 * @title   Blacklist-enabled ERC20 Issuance Token Interface
 * @notice  Extends ERC20 Issuance with blacklist functionality
 * @dev     Adds blacklist management to base token functionality
 * @author  Zealynx Security
 */
interface IERC20Issuance_blacklist_v1 is IERC20Issuance_v1 {
    
    function isBlacklisted(address account) external view returns (bool);
    function addToBlacklist(address account) external;
    function removeFromBlacklist(address account) external;
}