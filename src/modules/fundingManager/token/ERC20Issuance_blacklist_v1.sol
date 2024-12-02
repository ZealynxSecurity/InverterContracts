// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

//--------------------------------------------------------------------------
// Imports

// Internal
import {ERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol";
import {IERC20Issuance_Blacklist_v1} from
    "./interfaces/IERC20Issuance_Blacklist_v1.sol";

// External
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {ERC20} from "@oz/token/ERC20/ERC20.sol";

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
 *              - Owner-controlled blacklist management
 *          All blacklist operations can only be performed by the contract owner.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @author  Zealynx Security
 */
contract ERC20Issuance_Blacklist_v1 is
    IERC20Issuance_Blacklist_v1,
    ERC20Issuance_v1
{
    //--------------------------------------------------------------------------
    // Storage

    /// @dev Mapping of blacklisted addresses
    mapping(address => bool) private _blacklist;

    //--------------------------------------------------------------------------
    // Constants

    /// @dev Maximum number of addresses that can be blacklisted in a batch
    uint public constant BATCH_LIMIT = 200;

    //--------------------------------------------------------------------------
    // Constructor

    /// @param name_ Token name
    /// @param symbol_ Token symbol
    /// @param decimals_ Token decimals
    /// @param initialSupply_ Initial token supply
    /// @param initialAdmin_ Initial admin address
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint initialSupply_,
        address initialAdmin_
    )
        ERC20Issuance_v1(name_, symbol_, decimals_, initialSupply_, initialAdmin_)
    {}

    //--------------------------------------------------------------------------
    // Modifiers

    modifier onlyAllowed(address account_) {
        require(!isBlacklisted(account_), "Address is blacklisted");
        _;
    }

    //--------------------------------------------------------------------------
    // View Functions

    /// @inheritdoc IERC20Issuance_Blacklist_v1
    function isBlacklisted(address account_)
        public
        view
        override
        returns (bool isBlacklisted_)
    {
        return _blacklist[account_];
    }

    //--------------------------------------------------------------------------
    // External Functions

    /// @inheritdoc IERC20Issuance_Blacklist_v1
    function addToBlacklist(address account_) public onlyOwner {
        if (isBlacklisted(account_)) {
            revert ERC20Issuance__AddressAlreadyBlacklisted(account_);
        }
        _blacklist[account_] = true;
        emit AddedToBlacklist(account_);
    }

    /// @inheritdoc IERC20Issuance_Blacklist_v1
    function removeFromBlacklist(address account_) public onlyOwner {
        if (isBlacklisted(account_)) {
            _blacklist[account_] = false;
            emit RemovedFromBlacklist(account_);
        }
    }

    /// @inheritdoc IERC20Issuance_Blacklist_v1
    function addToBlacklistBatchAddresses(address[] memory accounts_)
        external
        onlyOwner
    {
        uint totalAccount_ = accounts_.length;
        if (totalAccount_ > BATCH_LIMIT) {
            revert ERC20Issuance__BatchLimitExceeded(totalAccount_, BATCH_LIMIT);
        }
        for (uint i_; i_ < totalAccount_; ++i_) {
            addToBlacklist(accounts_[i_]);
        }
    }

    /// @inheritdoc IERC20Issuance_Blacklist_v1
    function removeFromBlacklistBatchAddresses(address[] calldata accounts_)
        external
        onlyOwner
    {
        uint totalAccount_ = accounts_.length;
        if (totalAccount_ > BATCH_LIMIT) {
            revert ERC20Issuance__BatchLimitExceeded(totalAccount_, BATCH_LIMIT);
        }
        for (uint i_; i_ < totalAccount_; ++i_) {
            removeFromBlacklist(accounts_[i_]);
        }
    }

    /// @notice Mints tokens if account is not blacklisted
    /// @param account_ Address to mint to
    /// @param amount_ Amount to mint
    function mintAllowed(address account_, uint amount_) public onlyMinter {
        if (isBlacklisted(account_)) {
            revert ERC20Issuance__BlacklistedAddress(account_);
        }
        _mint(account_, amount_);
    }

    /// @notice Redeems tokens if account is not blacklisted
    /// @param account_ Address to redeem from
    /// @param amount_ Amount to redeem
    function redeem(address account_, uint amount_)
        public
        onlyAllowed(account_)
    {
        // To be implemented
    }

    // Internal function to enforce restrictions on transfers
    function _update(address from, address to, uint amount)
        internal
        virtual
        override
    {
        if (isBlacklisted(from) || isBlacklisted(to)) {
            revert ERC20Issuance__BlacklistedAddress(from);
        }
        super._update(from, to, amount);
    }
}
