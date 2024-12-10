// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Imports

// Internal
import {ERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol";
import {IERC20Issuance_Blacklist_v1} from
    "@ex/token/interfaces/IERC20Issuance_Blacklist_v1.sol";

// External
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {ERC20} from "@oz/token/ERC20/ERC20.sol";
import {ERC20Capped} from "@oz/token/ERC20/extensions/ERC20Capped.sol";

/**
 * @title   ERC20 Issuance Token with Blacklist Functionality
 *
 * @notice  An ERC20 token implementation that extends ERC20Issuance_v1 with
 *          blacklisting capabilities. This allows the owner to restrict specific
 *          addresses from participating in token operations.
 *
 * @dev     This contract inherits from:
 *              - IERC20Issuance_Blacklist_v1
 *              - ERC20Issuance_v1
 *          Key features:
 *              - Individual address blacklisting
 *              - Batch blacklisting operations
 *              - Owner-controlled manager role assignment
 *              - Blacklist manager controlled blacklist management
 *          All blacklist operations can only be performed by the contract owner.
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
contract ERC20Issuance_Blacklist_v1 is
    IERC20Issuance_Blacklist_v1,
    ERC20Issuance_v1
{
    // --------------------------------------------------------------------------
    // Storage

    /// @notice	Mapping of blacklisted addresses
    mapping(address => bool) private _blacklist;

    /// @notice	Mapping of blacklist manager addresses
    mapping(address => bool) private _isBlacklistManager;

    // --------------------------------------------------------------------------
    // Constants

    /// @notice	Maximum number of addresses that can be blacklisted in a batch
    uint public constant BATCH_LIMIT = 200;

    // --------------------------------------------------------------------------
    // Constructor

    /// @param	name_ Token name
    /// @param	symbol_ Token symbol
    /// @param	decimals_ Token decimals
    /// @param	initialSupply_ Initial token supply
    /// @param	initialAdmin_ Initial admin address
    /// @param	initialBlacklistManager_ Initial blacklist manager (typically an EOA)
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint initialSupply_,
        address initialAdmin_,
        address initialBlacklistManager_
    )
        ERC20Issuance_v1(name_, symbol_, decimals_, initialSupply_, initialAdmin_)
    {
        _setBlacklistManager(initialBlacklistManager_, true);
    }

    // --------------------------------------------------------------------------
    // View Functions

    /// @inheritdoc	IERC20Issuance_Blacklist_v1
    /// @param	account_ The account to check
    /// @return	True if the account is blacklisted
    function isBlacklisted(address account_) public view returns (bool) {
        return _blacklist[account_];
    }

    /// @inheritdoc	IERC20Issuance_Blacklist_v1
    /// @param	account_ The account to check
    /// @return	True if the account is a blacklist manager
    function isBlacklistManager(address account_) public view returns (bool) {
        return _isBlacklistManager[account_];
    }

    // --------------------------------------------------------------------------
    // External Functions

    /// @notice Modifier to check if the caller is a blacklist manager
    /// @dev    May revert with ERC20Issuance_Blacklist_NotBlacklistManager
    modifier onlyBlacklistManager() {
        if (!_isBlacklistManager[_msgSender()]) {
            revert ERC20Issuance_Blacklist_NotBlacklistManager();
        }
        _;
    }

    /// @inheritdoc IERC20Issuance_Blacklist_v1
    function addToBlacklist(address account_) public onlyBlacklistManager {
        if (account_ == address(0)) {
            revert ERC20Issuance_Blacklist_ZeroAddress();
        }
        if (!isBlacklisted(account_)) {
            _blacklist[account_] = true;
            emit AddedToBlacklist(account_);
        }
    }

    /// @inheritdoc IERC20Issuance_Blacklist_v1
    function removeFromBlacklist(address account_)
        public
        onlyBlacklistManager
    {
        if (account_ == address(0)) {
            revert ERC20Issuance_Blacklist_ZeroAddress();
        }
        if (isBlacklisted(account_)) {
            _blacklist[account_] = false;
            emit RemovedFromBlacklist(account_);
        }
    }

    /// @inheritdoc IERC20Issuance_Blacklist_v1
    function addToBlacklistBatchAddresses(address[] memory accounts_)
        external
        onlyBlacklistManager
    {
        uint totalAccount_ = accounts_.length;
        if (totalAccount_ > BATCH_LIMIT) {
            revert ERC20Issuance_Blacklist_BatchLimitExceeded(
                totalAccount_, BATCH_LIMIT
            );
        }
        for (uint i_; i_ < totalAccount_; ++i_) {
            addToBlacklist(accounts_[i_]);
        }
    }

    /// @inheritdoc IERC20Issuance_Blacklist_v1
    function removeFromBlacklistBatchAddresses(address[] calldata accounts_)
        external
        onlyBlacklistManager
    {
        uint totalAccount_ = accounts_.length;
        if (totalAccount_ > BATCH_LIMIT) {
            revert ERC20Issuance_Blacklist_BatchLimitExceeded(
                totalAccount_, BATCH_LIMIT
            );
        }
        for (uint i_; i_ < totalAccount_; ++i_) {
            removeFromBlacklist(accounts_[i_]);
        }
    }

    /// @inheritdoc IERC20Issuance_Blacklist_v1
    function setBlacklistManager(address manager_, bool allowed_)
        external
        onlyOwner
    {
        _setBlacklistManager(manager_, allowed_);
    }

    // --------------------------------------------------------------------------
    // Internal Functions

    /// @notice Internal hook to enforce blacklist restrictions on token transfers
    /// @dev    Overrides ERC20Capped._update to add blacklist checks
    /// @param  from Address tokens are transferred from
    /// @param  to Address tokens are transferred to
    /// @param  amount Number of tokens to transfer
    /// @inheritdoc ERC20Capped
    function _update(address from, address to, uint amount)
        internal
        override(ERC20Capped)
    {
        if (isBlacklisted(from)) {
            revert ERC20Issuance_Blacklist_BlacklistedAddress(from);
        }
        if (isBlacklisted(to)) {
            revert ERC20Issuance_Blacklist_BlacklistedAddress(to);
        }
        super._update(from, to, amount);
    }

    /// @notice Internal function to set a blacklist manager
    /// @param  manager_ Address to set as blacklist manager
    /// @param  allowed_ Whether to grant or revoke blacklist manager role
    function _setBlacklistManager(address manager_, bool allowed_) internal {
        if (manager_ == address(0)) {
            revert ERC20Issuance_Blacklist_ZeroAddress();
        }
        _isBlacklistManager[manager_] = allowed_;
        emit BlacklistManagerUpdated(manager_, allowed_);
    }
}
