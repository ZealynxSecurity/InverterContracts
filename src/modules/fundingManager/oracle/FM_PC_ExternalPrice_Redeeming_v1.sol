// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

//--------------------------------------------------------------------------
// Imports

// Internal
import {IFM_PC_ExternalPrice_Redeeming_v1} from
    "src/modules/fundingManager/oracle/interfaces/IFM_PC_ExternalPrice_Redeeming_v1.sol";
import {IERC20Issuance_Blacklist_v1} from
    "src/modules/fundingManager/token/interfaces/IERC20Issuance_Blacklist_v1.sol";
import {IOraclePrice_v1} from
    "src/modules/fundingManager/oracle/interfaces/IOraclePrice_v1.sol";
import {ERC20PaymentClientBase_v1} from
    "@lm/abstracts/ERC20PaymentClientBase_v1.sol";
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
import {BondingCurveBase_v1} from
    "@fm/bondingCurve/abstracts/BondingCurveBase_v1.sol";
import {RedeemingBondingCurveBase_v1} from
    "@fm/bondingCurve/abstracts/RedeemingBondingCurveBase_v1.sol";
import {IRedeemingBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IRedeemingBondingCurveBase_v1.sol";
import {Module_v1} from "src/modules/base/Module_v1.sol";
import {FM_BC_Tools} from "@fm/bondingCurve/FM_BC_Tools.sol";

// External
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@oz/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol";

/**
 * @title   External Price Oracle Funding Manager with Payment Client
 *
 * @notice  A funding manager implementation that uses external oracle price feeds
 *          for token operations. It integrates payment client functionality and
 *          supports token redemption through a bonding curve mechanism.
 *
 * @dev     This contract inherits from:
 *              - IFM_PC_ExternalPrice_Redeeming_v1
 *              - ERC20PaymentClientBase_v1
 *              - RedeemingBondingCurveBase_v1
 *          Key features:
 *              - External price integration
 *              - Payment client functionality
 *              - Blacklist enforcement
 *          Price feeds are managed through an external oracle contract that
 *          implements IOraclePrice_v1. The contract enforces blacklist
 *          restrictions through IERC20Issuance_Blacklist_v1.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @author  Zealynx Security
 */
contract FM_PC_ExternalPrice_Redeeming_v1 is
    IFM_PC_ExternalPrice_Redeeming_v1,
    ERC20PaymentClientBase_v1,
    RedeemingBondingCurveBase_v1
{
    /// @param interfaceId_ The interface identifier to check support for
    /// @return True if the interface is supported
    function supportsInterface(bytes4 interfaceId_)
        public
        view
        override(ERC20PaymentClientBase_v1, RedeemingBondingCurveBase_v1)
        returns (bool)
    {
        return interfaceId_ == type(IFM_PC_ExternalPrice_Redeeming_v1).interfaceId
            || super.supportsInterface(interfaceId_);
    }

    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------
    // Constants

    /// @dev Value is used to convert deposit amount to 18 decimals
    uint8 private constant EIGHTEEN_DECIMALS = 18;

    /// @notice Role for whitelisted addresses
    bytes32 public constant WHITELIST_ROLE = "WHITELIST_ROLE";

    /// @notice Maximum fee that can be charged for sell operations, expressed in basis points (10000 = 100%)
    /// @dev Set to 1000 basis points (10%)
    uint private constant MAX_SELL_FEE = 1000; // 10% in basis points

    //--------------------------------------------------------------------------
    // State Variables

    /// @dev Oracle price feed contract used for price discovery
    /// @notice Contract that provides external price information for token valuation
    IOraclePrice_v1 private _oracle;

    /// @dev Token that is accepted by this funding manager for deposits
    /// @notice The ERC20 token contract used for collateral in this funding manager
    IERC20 private _token;

    /// @dev Token decimals of the issuance token
    /// @notice Number of decimal places used by the issuance token for proper decimal handling
    uint8 private _issuanceTokenDecimals;

    /// @dev Token decimals of the Orchestrator token
    /// @notice Number of decimal places used by the collateral token for proper decimal handling
    uint8 private _collateralTokenDecimals;

    /// @dev Order ID counter for tracking individual orders
    /// @notice Unique identifier for the current order being processed
    uint private _orderId;

    /// @dev Counter for generating unique order IDs
    /// @notice Keeps track of the next available order ID to ensure uniqueness
    uint private _nextOrderId;

    /// @dev Total amount of tokens currently in redemption process
    /// @notice Tracks the sum of all pending redemption orders
    uint private _openRedemptionAmount;

    /// @dev Storage gap for future upgrades
    uint[50] private __gap;

    //--------------------------------------------------------------------------
    // Modifiers

    modifier notBlacklisted() {
        if (
            IERC20Issuance_Blacklist_v1(address(issuanceToken)).isBlacklisted(
                _msgSender()
            )
        ) {
            revert FM_ExternalPrice__AddressBlacklisted(_msgSender());
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
        (
            address _oracleAddress,
            address _issuanceToken,
            address _acceptedToken,
            uint _buyFee,
            uint _sellFee
        ) = abi.decode(configData_, (address, address, address, uint, uint));

        // Set accepted token
        _token = IERC20(_acceptedToken);

        // Cache token decimals for collateral
        _collateralTokenDecimals = IERC20Metadata(address(_token)).decimals();

        // Set oracle
        _oracle = IOraclePrice_v1(_oracleAddress);

        // Initialize base functionality (should handle token settings)
        _setIssuanceToken(_issuanceToken);

        // Set fees (checking max sell fee)
        if (_sellFee > MAX_SELL_FEE) {
            revert FM_ExternalPrice__FeeExceedsMaximum(_sellFee, MAX_SELL_FEE);
        }
        _setBuyFee(_buyFee);
        _setSellFee(_sellFee);
    }

    //--------------------------------------------------------------------------
    // View Functions

    /// @inheritdoc IFundingManager_v1
    /// @return token_ The token address
    function token() public view override returns (IERC20) {
        return _token;
    }

    /// @notice Gets current static price for buying tokens
    /// @return price_ The current buy price
    function getStaticPriceForBuying()
        public
        view
        override(BondingCurveBase_v1)
        returns (uint)
    {
        return _oracle.getPriceForIssuance();
    }

    /// @notice Gets current static price for selling tokens
    /// @return price_ The current sell price
    function getStaticPriceForSelling()
        public
        view
        override(RedeemingBondingCurveBase_v1, IRedeemingBondingCurveBase_v1)
        returns (uint)
    {
        return _oracle.getPriceForRedemption();
    }

    /// @inheritdoc IFM_PC_ExternalPrice_Redeeming_v1
    function getOpenRedemptionAmount() external view returns (uint amount_) {
        return _openRedemptionAmount;
    }

    /// @inheritdoc IFM_PC_ExternalPrice_Redeeming_v1
    function getNextOrderId() external view returns (uint orderId_) {
        return _nextOrderId;
    }

    /// @inheritdoc IFM_PC_ExternalPrice_Redeeming_v1
    function getOrderId() external view returns (uint orderId_) {
        return _orderId;
    }

    //--------------------------------------------------------------------------
    // External Functions

    // @audit-info Scenario: Project deposits collateral into the FM
    /// @notice Allows depositing collateral to provide reserves for redemptions
    /// @param amount_ The amount of collateral to deposit
    function depositReserve(uint amount_) external onlyOrchestratorAdmin {
        if (amount_ == 0) revert FM_ExternalPrice__InvalidAmount();

        // Transfer collateral from sender to FM
        IERC20(token()).safeTransferFrom(_msgSender(), address(this), amount_);

        emit ReserveDeposited(_msgSender(), amount_);
    }

    //--------------------------------------------------------------------------
    // Public Functions

    /// @inheritdoc BondingCurveBase_v1
    /// @param collateralAmount_ The amount of collateral to spend
    function buy(uint collateralAmount_, uint minAmountOut_)
        public
        override(BondingCurveBase_v1)
        onlyModuleRole(WHITELIST_ROLE)
        notBlacklisted
    {
        super.buyFor(_msgSender(), collateralAmount_, minAmountOut_);
    }

    /// @inheritdoc IFM_PC_ExternalPrice_Redeeming_v1
    /// @param receiver_ Address to receive collateral
    /// @param depositAmount_ Amount of tokens to sell
    /// @param minAmountOut_ Minimum collateral to receive
    function sell(address receiver_, uint depositAmount_, uint minAmountOut_)
        external
        override(IFM_PC_ExternalPrice_Redeeming_v1)
        onlyModuleRole(WHITELIST_ROLE)
        notBlacklisted
    {
        sellTo(receiver_, depositAmount_, minAmountOut_);

        // Get current exchange rate from oracle
        uint exchangeRate = _oracle.getPriceForRedemption();

        // Calculate amounts using parent functionality
        uint collateralAmount = calculateSaleReturn(depositAmount_);
        uint feeAmount = (collateralAmount * sellFee) / BPS;
        uint redemptionAmount = collateralAmount - feeAmount;

        // Generate new order ID
        _orderId = _nextOrderId++;

        // Update open redemption amount
        _openRedemptionAmount += redemptionAmount;

        // Create and add payment order
        PaymentOrder memory order = PaymentOrder({
            recipient: _msgSender(),
            paymentToken: address(token()),
            amount: redemptionAmount,
            start: block.timestamp,
            cliff: 0,
            end: block.timestamp
        });
        _addPaymentOrder(order);

        // Emit event with all order details
        emit RedemptionOrderCreated(
            _orderId,
            _msgSender(),
            depositAmount_,
            exchangeRate,
            collateralAmount,
            sellFee,
            feeAmount,
            redemptionAmount,
            address(token()),
            block.timestamp,
            RedemptionState.PROCESSING
        );
    }

    /// @inheritdoc IFundingManager_v1
    /// @param to_ The recipient address
    /// @param amount_ The amount to transfer
    function transferOrchestratorToken(address to_, uint amount_)
        external
        onlyPaymentClient
    {
        token().safeTransfer(to_, amount_);

        emit TransferOrchestratorToken(to_, amount_);
    }

    /// @notice Sets fee for sell operations
    /// @param fee_ New fee amount
    function setSellFee(uint fee_)
        public
        override(RedeemingBondingCurveBase_v1, IRedeemingBondingCurveBase_v1)
        onlyOrchestratorAdmin
    {
        // Check that fee doesn't exceed maximum allowed
        if (fee_ > MAX_SELL_FEE) {
            revert FM_ExternalPrice__FeeExceedsMaximum(fee_, MAX_SELL_FEE);
        }

        super._setSellFee(fee_);
    }

    function getSellFee() public pure returns (uint sellFee_) {
        return sellFee_;
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @param depositAmount_ The amount being deposited
    /// @return mintAmount_ The calculated token amount
    function _issueTokensFormulaWrapper(uint depositAmount_)
        internal
        view
        override(BondingCurveBase_v1)
        returns (uint mintAmount_)
    {
        // First convert deposit amount to required decimals
        uint normalizedAmount_ = FM_BC_Tools._convertAmountToRequiredDecimal(
            depositAmount_,
            IERC20Metadata(address(token())).decimals(),
            IERC20Metadata(address(issuanceToken)).decimals()
        );

        // Then calculate the token amount using the normalized amount
        mintAmount_ = _oracle.getPriceForIssuance() * normalizedAmount_;
    }

    /// @param depositAmount_ The amount being redeemed
    /// @return redeemAmount_ The calculated collateral amount
    function _redeemTokensFormulaWrapper(uint depositAmount_)
        internal
        view
        override(RedeemingBondingCurveBase_v1)
        returns (uint redeemAmount_)
    {
        // Calculate redeem amount through oracle price
        uint tokenAmount_ = _oracle.getPriceForRedemption() * depositAmount_;

        // Convert redeem amount to collateral decimals
        redeemAmount_ = FM_BC_Tools._convertAmountToRequiredDecimal(
            tokenAmount_, EIGHTEEN_DECIMALS, _collateralTokenDecimals
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

    /// @inheritdoc BondingCurveBase_v1
    function _handleIssuanceTokensAfterBuy(address recipient_, uint amount_)
        internal
        virtual
        override
    {
        // Transfer issuance tokens to recipient
        IERC20Issuance_v1(issuanceToken).mint(recipient_, amount_);
    }

    /// @inheritdoc RedeemingBondingCurveBase_v1
    function _handleCollateralTokensAfterSell(address recipient_, uint amount_)
        internal
        virtual
        override
    {
        // Transfer collateral tokens to recipient
        IERC20(token()).safeTransfer(recipient_, amount_);
    }

    /// @notice Helper function to generate a role ID for this module
    /// @param role The role to generate an ID for
    /// @return bytes32 The generated role ID
    function generateRoleId(bytes32 role) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), role));
    }
}
