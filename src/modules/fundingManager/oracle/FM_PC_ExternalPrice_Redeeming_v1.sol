// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import { IFM_PC_ExternalPrice_Redeeming_v1 } from "./interfaces/IFM_PC_ExternalPrice_Redeeming_v1.sol";
import { IERC20Issuance_blacklist_v1 } from "../token/interfaces/IERC20Issuance_blacklist_v1.sol";
import { IOraclePrice_v1 } from "./interfaces/IOraclePrice_v1.sol";
import { ERC20PaymentClientBase_v1 } from "@lm/abstracts/ERC20PaymentClientBase_v1.sol";
import { IERC20 } from "@oz/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@oz/token/ERC20/utils/SafeERC20.sol";
import { IOrchestrator_v1 } from "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import { IFundingManager_v1 } from "@fm/IFundingManager_v1.sol";
import { IBondingCurveBase_v1 } from "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
import { BondingCurveBase_v1 } from "@fm/bondingCurve/abstracts/BondingCurveBase_v1.sol";
import {
    RedeemingBondingCurveBase_v1
} from "@fm/bondingCurve/abstracts/RedeemingBondingCurveBase_v1.sol";
import { IRedeemingBondingCurveBase_v1 } from "@fm/bondingCurve/interfaces/IRedeemingBondingCurveBase_v1.sol";
import { Module_v1 } from "src/modules/base/Module_v1.sol";
import { FM_BC_Tools } from "@fm/bondingCurve/FM_BC_Tools.sol";
import { IERC20Metadata } from "@oz/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20Issuance_v1 } from "@ex/token/ERC20Issuance_v1.sol";

/**
* @title   Oracle Price Funding Manager with Payment Client
* @notice  Manages token operations using oracle pricing and payment client functionality 
* @dev     Extends RedeemingBondingCurveBase_v1 with oracle price feed integration
* @custom:security-contact security@inverter.network
* @author  Zealynx Security
*/
contract FM_PC_ExternalPrice_Redeeming_v1 is 
   IFM_PC_ExternalPrice_Redeeming_v1,
   ERC20PaymentClientBase_v1,
   RedeemingBondingCurveBase_v1
{
    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------
    // Constants

    /// @dev Maximum number of addresses that can be whitelisted in a batch
    uint256 public constant MAX_BATCH_SIZE = 50;

    /// @dev    Value is used to convert deposit amount to 18 decimals, which is required by the {BancorFormula}.
    ///         which is required by the Bancor formula.
    uint8 private constant EIGHTEEN_DECIMALS = 18;

    //--------------------------------------------------------------------------
    // Storage

    /// @dev Oracle price feed contract
    IOraclePrice_v1 private _oracle;

    /// @dev Mapping of whitelisted addresses
    mapping(address => bool) private _whitelist;

    /// @dev Storage gap for future upgrades
    uint256[50] private __gap;

    /// @dev Token that is accepted by this funding manager for deposits.
    IERC20 private _token;

    /// @dev Token decimals of the issuance token, which is stored within the implementation for gas saving.
    uint8 internal _issuanceTokenDecimals;

    /// @dev Token decimals of the Orchestrator token, which is used as collateral and stores within
    /// implementation for gas saving.
    uint8 internal _collateralTokenDecimals;

    // For order IDs
    uint256 private _orderId;

    // For tracking order IDs
    uint256 private _nextOrderId;

    // For tracking total open redemption amount
    uint256 public openRedemptionAmount;

    // For storing order information
    mapping(uint256 => RedemptionOrder) private _redemptionOrders;

    // Struct to store order details
    struct RedemptionOrder {
        address seller;
        uint256 sellAmount;
        uint256 exchangeRate;
        uint256 collateralAmount;
        uint256 feePercentage;
        uint256 feeAmount;
        uint256 redemptionAmount;
        address collateralToken;
        uint256 redemptionTime;
        RedemptionState state;
    }

    //--------------------------------------------------------------------------
    // Events

    event AddressWhitelisted(address indexed account_);
    event AddressRemovedFromWhitelist(address indexed account_);
    event BatchWhitelistUpdated(address[] accounts_, bool isAdd_);
    event ReserveDeposited(address indexed depositor, uint256 amount);
    event RedemptionOrderCreated(
        uint256 indexed orderId,
        address indexed seller,
        uint256 sellAmount,
        uint256 exchangeRate,
        uint256 collateralAmount,
        uint256 feePercentage,
        uint256 feeAmount,
        uint256 redemptionAmount,
        address collateralToken,
        uint256 redemptionTime,
        RedemptionState state
    );
    event RedemptionOrderStateUpdated(
        uint256 indexed orderId,
        RedemptionState newState
    );

    //--------------------------------------------------------------------------
    // Errors

    error FM_ExternalPrice__BatchSizeExceeded(uint256 size_);
    error FM_ExternalPrice__ZeroAddress();
    error FM_ExternalPrice__InvalidAmount();
    error FM_ExternalPrice__AddressBlacklisted(address account_);
    error FM_ExternalPrice__NotWhitelisted(address account_);

    //--------------------------------------------------------------------------
    // Modifiers

    /// @dev Ensures caller is whitelisted
    modifier onlyWhitelisted() {
        if (!_whitelist[msg.sender]) {
            revert FM_ExternalPrice__NotWhitelisted(msg.sender);
        }
        _;
    }

    modifier notBlacklisted() {
        if (IERC20Issuance_blacklist_v1(address(issuanceToken)).isBlacklisted(msg.sender)) {
            revert FM_ExternalPrice__AddressBlacklisted(msg.sender);
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Initialization Function

    /// @inheritdoc Module_v1
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata_,
        bytes memory configData_
    ) external override(Module_v1) initializer {
        // Initialize parent contracts
        __Module_init(orchestrator_, metadata_);

        // Decode config data
        (address _oracleAddress, address _issuanceToken, address _acceptedToken) = 
            abi.decode(configData_, (address, address, address));

        // Set accepted token
        _token = IERC20(_acceptedToken);

        // Cache token decimals for collateral
        _collateralTokenDecimals = IERC20Metadata(address(_token)).decimals();

        // Set oracle
        _oracle = IOraclePrice_v1(_oracleAddress);

        // Initialize base functionality (should handle token settings)
        _setIssuanceToken(_issuanceToken);
    }

    //--------------------------------------------------------------------------
    // Whitelist Management Functions

    /// @notice Adds a single address to the whitelist
    /// @param account_ The address to whitelist
    function addToWhitelist(address account_) external onlyOrchestratorAdmin {
        if (account_ == address(0)) revert FM_ExternalPrice__ZeroAddress();
        
        if (!_whitelist[account_]) {
            _whitelist[account_] = true;
            emit AddressWhitelisted(account_);
        }
    }

    /// @notice Removes a single address from the whitelist
    /// @param account_ The address to remove from whitelist
    function removeFromWhitelist(address account_) external onlyOrchestratorAdmin {
        if (_whitelist[account_]) {
            _whitelist[account_] = false;
            emit AddressRemovedFromWhitelist(account_);
        }
    }

    /// @notice Adds multiple addresses to the whitelist
    /// @param accounts_ Array of addresses to whitelist
    function batchAddToWhitelist(
        address[] calldata accounts_
    ) external onlyOrchestratorAdmin {
        uint256 length_ = accounts_.length;
        if (length_ > MAX_BATCH_SIZE) revert FM_ExternalPrice__BatchSizeExceeded(length_);
        
        for (uint256 i_; i_ < length_; i_++) {
            if (accounts_[i_] == address(0)) revert FM_ExternalPrice__ZeroAddress();
            if (!_whitelist[accounts_[i_]]) {
                _whitelist[accounts_[i_]] = true;
                emit AddressWhitelisted(accounts_[i_]);
            }
        }
        emit BatchWhitelistUpdated(accounts_, true);
    }

    /// @notice Removes multiple addresses from the whitelist
    /// @param accounts_ Array of addresses to remove from whitelist
    function batchRemoveFromWhitelist(
        address[] calldata accounts_
    ) external onlyOrchestratorAdmin {
        uint256 length_ = accounts_.length;
        if (length_ > MAX_BATCH_SIZE) revert FM_ExternalPrice__BatchSizeExceeded(length_);
        
        for (uint256 i_; i_ < length_; i_++) {
            if (_whitelist[accounts_[i_]]) {
                _whitelist[accounts_[i_]] = false;
                emit AddressRemovedFromWhitelist(accounts_[i_]);
            }
        }
        emit BatchWhitelistUpdated(accounts_, false);
    }

    /// @notice Checks if an address is whitelisted
    /// @param account_ The address to check
    /// @return isWhitelisted_ True if address is whitelisted
    function isWhitelisted(
        address account_
    ) external view returns (bool isWhitelisted_) {
        return _whitelist[account_];
    }

    //--------------------------------------------------------------------------
    // View Functions

    /// @param interfaceId_ The interface identifier to check support for
    /// @return True if the interface is supported
    function supportsInterface(
        bytes4 interfaceId_
    ) public view override(ERC20PaymentClientBase_v1, RedeemingBondingCurveBase_v1) returns (bool) {
        return interfaceId_ == type(IRedeemingBondingCurveBase_v1).interfaceId
            || super.supportsInterface(interfaceId_);
    }

    /// @inheritdoc IFundingManager_v1
    /// @return token_ The token address
    function token() public view override returns (IERC20) {
        return _token;
    }

    /// @notice Gets current static price for buying tokens
    /// @return price_ The current buy price
    function getStaticPriceForBuying() public view override(BondingCurveBase_v1) returns (uint256) {
        return _oracle.getPriceForIssuance();
    }

    /// @notice Gets current static price for selling tokens
    /// @return price_ The current sell price
    function getStaticPriceForSelling() public view override(RedeemingBondingCurveBase_v1, IRedeemingBondingCurveBase_v1) returns (uint256) {
        return _oracle.getPriceForRedemption();
    }

    // @audit-info Scenario: Display expected token return amount to the buyer
    function calculateExpectedReturn(
        uint256 collateralAmount_
    ) external view override returns (uint256) {
        return calculatePurchaseReturn(collateralAmount_);
    }

    // @audit-info Scenario: Display expected collateral return amount to the seller
    /// @notice Calculates expected collateral return for a given amount of USP tokens
    /// @param tokenAmount_ The amount of USP tokens to sell
    /// @return collateralAmount_ Expected amount of collateral to receive
    function calculateExpectedCollateralReturn(
        uint256 tokenAmount_
    ) external view override returns (uint256) {
        return calculateSaleReturn(tokenAmount_);
    }

    // Add view function to get order details
    function getOrder(uint256 orderId_) external view returns (RedemptionOrder memory) {
        return _redemptionOrders[orderId_];
    }

    //--------------------------------------------------------------------------
    // External Functions

    // @audit-info Scenario: Project deposits collateral into the FM
    /// @notice Allows depositing collateral to provide reserves for redemptions
    /// @param amount_ The amount of collateral to deposit
    function depositReserve(uint256 amount_) external onlyOrchestratorAdmin {
        if (amount_ == 0) revert FM_ExternalPrice__InvalidAmount();
        
        // Transfer collateral from sender to FM
        IERC20(token()).safeTransferFrom(msg.sender, address(this), amount_);
        
        emit ReserveDeposited(msg.sender, amount_);
    }

    function getOpenRedemptionAmount() external view returns (uint256) {
        return openRedemptionAmount;
    }

    //--------------------------------------------------------------------------
    // Public Functions

    /// @inheritdoc IFM_PC_ExternalPrice_Redeeming_v1
    /// @param collateralAmount_ The amount of collateral to spend
    function buy(
        uint256 collateralAmount_,
        uint256 minAmountOut_
    ) public override(IFM_PC_ExternalPrice_Redeeming_v1, BondingCurveBase_v1) onlyWhitelisted notBlacklisted {
        buyFor(msg.sender, collateralAmount_, minAmountOut_);  
    }

    /// @inheritdoc IFM_PC_ExternalPrice_Redeeming_v1
    /// @param receiver_ Address to receive collateral
    /// @param depositAmount_ Amount of tokens to sell  
    /// @param minAmountOut_ Minimum collateral to receive
    function sell(
        address receiver_,
        uint256 depositAmount_,
        uint256 minAmountOut_
    ) external override(IFM_PC_ExternalPrice_Redeeming_v1) onlyWhitelisted notBlacklisted {
        sellTo(receiver_, depositAmount_, minAmountOut_);

        // Get current exchange rate from oracle
        uint256 exchangeRate = _oracle.getPriceForRedemption();
        
        // Calculate amounts using parent functionality
        uint256 collateralAmount = calculateSaleReturn(depositAmount_);
        uint256 feeAmount = (collateralAmount * sellFee) / BPS; // potentiallt wrong
        uint256 redemptionAmount = collateralAmount - feeAmount;

        // Generate new order ID
        _orderId = _nextOrderId++;

        // Create and store order
        _redemptionOrders[_orderId] = RedemptionOrder({
            seller: msg.sender,
            sellAmount: depositAmount_,
            exchangeRate: exchangeRate,
            collateralAmount: collateralAmount,
            feePercentage: sellFee,
            feeAmount: feeAmount,
            redemptionAmount: redemptionAmount,
            collateralToken: address(token()),
            redemptionTime: block.timestamp,
            state: RedemptionState.Processing
        });

        // Update open redemption amount
        openRedemptionAmount += redemptionAmount;


        // Emit event with all order details
        emit RedemptionOrderCreated(
            _orderId,
            msg.sender,
            depositAmount_,
            exchangeRate,
            collateralAmount,
            sellFee,
            feeAmount,
            redemptionAmount,
            address(token()),
            block.timestamp,
            RedemptionState.Processing
        );
    }

    /// @inheritdoc IFundingManager_v1
    /// @param to_ The recipient address
    /// @param amount_ The amount to transfer
    function transferOrchestratorToken(
        address to_,
        uint256 amount_
    ) external override(IFundingManager_v1) onlyPaymentClient {
        token().safeTransfer(to_, amount_);

        emit TransferOrchestratorToken(to_, amount_);
    }

    /// @notice Sets fee for sell operations
    /// @param fee_ New fee amount
    function setSellFee(
        uint256 fee_
    ) public override(RedeemingBondingCurveBase_v1, IRedeemingBondingCurveBase_v1) onlyOrchestratorAdmin {
        _setSellFee(fee_);
    }

    function getSellFee() public pure returns (uint256 sellFee_) {
        return sellFee_;
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @param depositAmount_ The amount being deposited
    /// @return mintAmount_ The calculated token amount
    function _issueTokensFormulaWrapper(
        uint256 depositAmount_
    ) internal view override(BondingCurveBase_v1) returns (uint256 mintAmount_) {
        // Calculate mint amount through oracle price
        uint256 tokenAmount_ = _oracle.getPriceForIssuance() * depositAmount_;

        // Convert mint amount to issuing token decimals
        mintAmount_ = FM_BC_Tools._convertAmountToRequiredDecimal(
            tokenAmount_, 
            EIGHTEEN_DECIMALS, 
            _issuanceTokenDecimals
        );
    }

    /// @param depositAmount_ The amount being redeemed
    /// @return redeemAmount_ The calculated collateral amount
    function _redeemTokensFormulaWrapper(
        uint256 depositAmount_
    ) internal view override(RedeemingBondingCurveBase_v1) returns (uint redeemAmount_) {
        // Calculate redeem amount through oracle price
        uint tokenAmount_ = _oracle.getPriceForRedemption() * depositAmount_;

        // Convert redeem amount to collateral decimals
        redeemAmount_ = FM_BC_Tools._convertAmountToRequiredDecimal(
            tokenAmount_,
            EIGHTEEN_DECIMALS,
            _collateralTokenDecimals
        );
    }

    /// @dev    Sets the issuance token.
    ///         This function overrides the internal function set in {BondingCurveBase_v1}, and
    ///         it updates the `issuanceToken` state variable and caches the decimals as `_issuanceTokenDecimals`.
    /// @param  issuanceToken_ The token which will be issued by the Bonding Curve.
    function _setIssuanceToken(address issuanceToken_)
        internal
        override(BondingCurveBase_v1)
    {
        uint8 decimals_ = IERC20Metadata(issuanceToken_).decimals();

        issuanceToken = IERC20Issuance_v1(issuanceToken_);
        _issuanceTokenDecimals = decimals_;
        emit IssuanceTokenSet(issuanceToken_, decimals_);
    }
}