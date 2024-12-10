// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Imports

// Internal
import {IFM_PC_ExternalPrice_Redeeming_v1} from
    "src/modules/fundingManager/oracle/interfaces/IFM_PC_ExternalPrice_Redeeming_v1.sol";
import {IERC20Issuance_Blacklist_v1} from
    "@ex/token/interfaces/IERC20Issuance_Blacklist_v1.sol";
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
import {IERC20PaymentClientBase_v1} from
    "@lm/interfaces/IERC20PaymentClientBase_v1.sol";

// External
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@oz/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol";
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

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
 *          The contract uses external price feeds for both issuance and redemption
 *          operations, ensuring market-aligned token pricing.
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
contract FM_PC_ExternalPrice_Redeeming_v1 is
    IFM_PC_ExternalPrice_Redeeming_v1,
    ERC20PaymentClientBase_v1,
    RedeemingBondingCurveBase_v1
{
    /// @inheritdoc ERC165Upgradeable
    /// @param  interfaceId_ The interface identifier to check support for.
    /// @return True if the interface is supported.
    function supportsInterface(bytes4 interfaceId_)
        public
        view
        override(ERC20PaymentClientBase_v1, RedeemingBondingCurveBase_v1)
        returns (bool)
    {
        return interfaceId_
            == type(IFM_PC_ExternalPrice_Redeeming_v1).interfaceId
            || super.supportsInterface(interfaceId_);
    }

    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // Constants

    /// @dev    Value is used to convert deposit amount to 18 decimals.
    uint8 private constant EIGHTEEN_DECIMALS = 18;

    /// @notice Role for whitelisted addresses.
    bytes32 public constant WHITELIST_ROLE = "WHITELIST_ROLE";

    /// @notice Role for payment queue.
    bytes32 public constant QUEUE_MANAGER_ROLE = "QUEUE_MANAGER_ROLE";

    // -------------------------------------------------------------------------
    // State Variables

    /// @dev    Oracle price feed contract used for price discovery.
    /// @notice Contract that provides external price information for token valuation.
    IOraclePrice_v1 private _oracle;

    /// @dev    Token that is accepted by this funding manager for deposits.
    /// @notice The ERC20 token contract used for collateral in this funding manager.
    IERC20 private _token;

    /// @dev    Token decimals of the issuance token.
    /// @notice Number of decimal places used by the issuance token for proper decimal handling.
    uint8 private _issuanceTokenDecimals;

    /// @dev    Token decimals of the Orchestrator token.
    /// @notice Number of decimal places used by the collateral token for proper decimal handling.
    uint8 private _collateralTokenDecimals;

    /// @dev    Maximum fee that can be charged for sell operations, in basis points.
    /// @notice Maximum allowed project fee percentage for selling tokens.
    uint private _maxSellFee;

    /// @dev    Maximum fee that can be charged for buy operations, in basis points.
    /// @notice Maximum allowed project fee percentage for buying tokens.
    uint private _maxBuyFee;

    /// @dev    Order ID counter for tracking individual orders.
    /// @notice Unique identifier for the current order being processed.
    uint private _orderId;

    /// @dev    Counter for generating unique order IDs.
    /// @notice Keeps track of the next available order ID to ensure uniqueness.
    uint private _nextOrderId;

    /// @dev    Total amount of collateral tokens currently in redemption process.
    /// @notice Tracks the sum of all pending redemption orders.
    uint private _openRedemptionAmount;

    /// @dev    Flag indicating if direct operations are only allowed.
    bool private _isDirectOperationsOnly;

    /// @notice Address of the project treasury which will receive the collateral tokens
    address private _projectTreasury;

    /// @dev    Storage gap for future upgrades.
    uint[50] private __gap;

    // -------------------------------------------------------------------------
    // Modifiers

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
            address projectTreasury_,
            address issuanceToken_,
            address acceptedToken_,
            uint buyFee_,
            uint sellFee_,
            uint maxSellFee_,
            uint maxBuyFee_,
            bool isDirectOperationsOnly_
        ) = abi.decode(
            configData_,
            (address, address, address, uint, uint, uint, uint, bool)
        );

        // Set accepted token
        _token = IERC20(acceptedToken_);

        // Cache token decimals for collateral
        _collateralTokenDecimals = IERC20Metadata(address(_token)).decimals();

        // Initialize base functionality (should handle token settings)
        _setIssuanceToken(issuanceToken_);

        // Set fees (checking max fees)
        if (buyFee_ > maxBuyFee_) {
            revert Module__FM_PC_ExternalPrice_Redeeming_FeeExceedsMaximum(
                buyFee_, maxBuyFee_
            );
        }
        if (sellFee_ > maxSellFee_) {
            revert Module__FM_PC_ExternalPrice_Redeeming_FeeExceedsMaximum(
                sellFee_, maxSellFee_
            );
        }
        // Set project treasury
        _setProjectTreasury(projectTreasury_);

        // Set fees
        _setBuyFee(buyFee_);
        _setSellFee(sellFee_);

        _setMaxBuyFee(maxBuyFee_);
        _setMaxSellFee(maxSellFee_);

        // Set direct operations only flag
        setIsDirectOperationsOnly(isDirectOperationsOnly_);
    }

    // --------------------------------------------------------------------------
    // Modifiers

    /// @notice Modifier to check if direct operations are only allowed
    modifier onlyDirectOperations() {
        if (_isDirectOperationsOnly) {
            revert
                Module__FM_PC_ExternalPrice_Redeeming_ThirdPartyOperationsDisabled();
        }
        _;
    }

    // --------------------------------------------------------------------------
    // View Functions

    /// @inheritdoc IFundingManager_v1
    /// @return token_ The token address.
    function token() public view override returns (IERC20) {
        return _token;
    }

    /// @inheritdoc IBondingCurveBase_v1
    /// @return uint The static price for buying the issuance token.
    function getStaticPriceForBuying()
        public
        view
        override(BondingCurveBase_v1)
        returns (uint)
    {
        return _oracle.getPriceForIssuance();
    }

    /// @inheritdoc IRedeemingBondingCurveBase_v1
    /// @return uint The static price for selling the issuance token.
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

    /// @inheritdoc IFM_PC_ExternalPrice_Redeeming_v1
    function getProjectTreasury() external view returns (address) {
        return _projectTreasury;
    }

    // -------------------------------------------------------------------------
    // External Functions

    /// @inheritdoc IFM_PC_ExternalPrice_Redeeming_v1
    function depositReserve(uint amount_) external {
        if (amount_ == 0) {
            revert Module__FM_PC_ExternalPrice_Redeeming_InvalidAmount();
        }

        // Transfer collateral from sender to FM
        IERC20(token()).safeTransferFrom(_msgSender(), address(this), amount_);

        emit ReserveDeposited(_msgSender(), amount_);
    }

    /// @inheritdoc IFM_PC_ExternalPrice_Redeeming_v1
    function executeRedemptionQueue()
        external
        override(IFM_PC_ExternalPrice_Redeeming_v1)
        onlyModuleRole(QUEUE_MANAGER_ROLE)
    {
        // NOTE: This function expects a Queue-based Payment Processor to be connected.
        // The call will intentionally revert if a non-Queue PP is used, as this FM
        // is designed to work only with Payment Processors that support queue-based redemptions.
        (bool success,) = address(__Module_orchestrator.paymentProcessor()).call(
            abi.encodeWithSignature("executeRedemptionQueue()")
        );

        if (!success) {
            revert Module__FM_PC_ExternalPrice_Redeeming_QueueExecutionFailed();
        }
    }

    // -------------------------------------------------------------------------
    // Public Functions

    /// @inheritdoc BondingCurveBase_v1
    /// @dev    Only whitelisted addresses can buy.
    /// @param  collateralAmount_ The amount of collateral to spend.
    function buy(uint collateralAmount_, uint minAmountOut_)
        public
        override(BondingCurveBase_v1)
        onlyModuleRole(WHITELIST_ROLE)
    {
        super.buyFor(_msgSender(), collateralAmount_, minAmountOut_);
    }

    /// @inheritdoc BondingCurveBase_v1
    /// @dev    Only whitelisted addresses can buy.
    /// @param  receiver_ Address to receive tokens.
    /// @param  depositAmount_ The amount of collateral to spend.
    /// @param  minAmountOut_ The minimum amount of tokens to receive.
    function buyFor(address receiver_, uint depositAmount_, uint minAmountOut_)
        public
        override(BondingCurveBase_v1)
        onlyModuleRole(WHITELIST_ROLE)
        onlyDirectOperations
    {
        super.buyFor(receiver_, depositAmount_, minAmountOut_);
    }

    /// @inheritdoc RedeemingBondingCurveBase_v1
    /// @dev    Only whitelisted addresses can sell.
    /// @param  depositAmount_ Amount of tokens to sell.
    /// @param  minAmountOut_ Minimum collateral to receive.
    function sell(uint depositAmount_, uint minAmountOut_)
        public
        override(RedeemingBondingCurveBase_v1, IRedeemingBondingCurveBase_v1)
        onlyModuleRole(WHITELIST_ROLE)
    {
        _sellOrder(_msgSender(), depositAmount_, minAmountOut_);
    }

    /// @inheritdoc RedeemingBondingCurveBase_v1
    /// @dev    Only whitelisted addresses can sell.
    /// @param  receiver_ Address to receive tokens.
    /// @param  depositAmount_ Amount of tokens to sell.
    /// @param  minAmountOut_ Minimum collateral to receive.
    function sellTo(address receiver_, uint depositAmount_, uint minAmountOut_)
        public
        override(RedeemingBondingCurveBase_v1, IRedeemingBondingCurveBase_v1)
        onlyModuleRole(WHITELIST_ROLE)
        onlyDirectOperations
    {
        _sellOrder(receiver_, depositAmount_, minAmountOut_);
    }

    /// @inheritdoc IFundingManager_v1
    /// @dev    Only payment clients can transfer orchestrator tokens.
    /// @param  to_ The recipient address.
    /// @param  amount_ The amount to transfer.
    function transferOrchestratorToken(address to_, uint amount_)
        external
        onlyPaymentClient
    {
        token().safeTransfer(to_, amount_);

        emit TransferOrchestratorToken(to_, amount_);
    }

    /// @notice Sets fee for sell operations.
    /// @dev    Only orchestrator admin can call.
    /// @param  fee_ New fee amount.
    function setSellFee(uint fee_)
        public
        override(RedeemingBondingCurveBase_v1, IRedeemingBondingCurveBase_v1)
        onlyOrchestratorAdmin
    {
        // Check that fee doesn't exceed maximum allowed
        if (fee_ > _maxSellFee) {
            revert Module__FM_PC_ExternalPrice_Redeeming_FeeExceedsMaximum(
                fee_, _maxSellFee
            );
        }

        super._setSellFee(fee_);
    }

    /// @notice Gets current sell fee.
    /// @return sellFee_ The current sell fee.
    function getSellFee() public pure returns (uint sellFee_) {
        return sellFee_;
    }

    /// @notice Sets fee for buy operations.
    /// @dev    Only orchestrator admin can call.
    /// @param  fee_ New fee amount.
    function setBuyFee(uint fee_)
        external
        override(BondingCurveBase_v1)
        onlyOrchestratorAdmin
    {
        // Check that fee doesn't exceed maximum allowed
        if (fee_ > _maxBuyFee) {
            revert Module__FM_PC_ExternalPrice_Redeeming_FeeExceedsMaximum(
                fee_, _maxBuyFee
            );
        }

        super._setBuyFee(fee_);
    }

    /// @inheritdoc IFM_PC_ExternalPrice_Redeeming_v1
    function setProjectTreasury(address projectTreasury_)
        external
        onlyOrchestratorAdmin
    {
        _setProjectTreasury(projectTreasury_);
    }

    /// @inheritdoc IFM_PC_ExternalPrice_Redeeming_v1
    function setOracleAddress(address oracle_) external onlyOrchestratorAdmin {
        _setOracleAddress(oracle_);
    }

    /// @notice Gets current buy fee.
    /// @return buyFee_ The current buy fee.
    function getBuyFee() public pure returns (uint buyFee_) {
        return buyFee_;
    }

    /// @notice Gets the maximum fee that can be charged for buy operations.
    /// @return maxBuyFee_ The maximum fee percentage.
    function getMaxBuyFee() public view returns (uint maxBuyFee_) {
        return _maxBuyFee;
    }

    /// @notice Gets the maximum fee that can be charged for sell operations.
    /// @return maxSellFee_ The maximum fee percentage.
    function getMaxSellFee() public view returns (uint maxSellFee_) {
        return _maxSellFee;
    }

    /// @notice Sets the direct operations only flag.
    /// @dev    Only orchestrator admin can call.
    /// @param isDirectOperationsOnly_ The new value for the flag.
    function setIsDirectOperationsOnly(bool isDirectOperationsOnly_)
        public
        onlyOrchestratorAdmin
    {
        _isDirectOperationsOnly = isDirectOperationsOnly_;
    }

    /// @notice Gets the direct operations only flag.
    /// @return isDirectOperationsOnly_ The current value of the flag.
    function isDirectOperationsOnly() public view returns (bool) {
        return _isDirectOperationsOnly;
    }

    // -------------------------------------------------------------------------
    // Internal Functions

    /// @notice Creates and emits a new redemption order.
    /// @dev    This function wraps the `_createAndEmitOrder` internal function with specified parameters to handle
    ///         the transaction and direct the proceeds.
    /// @param  receiver_ The address that will receive the redeemed tokens.
    /// @param  depositAmount_ The amount of tokens to be sold.
    /// @param  collateralRedeemAmount_ The amount of collateral to redeem.
    /// @param  issuanceFeeAmount_ The amount of issuance fee to charge.
    function _createAndEmitOrder(
        address receiver_,
        uint depositAmount_,
        uint collateralRedeemAmount_,
        uint issuanceFeeAmount_
    ) internal {
        // Generate new order ID
        _orderId = _nextOrderId++;

        // Update open redemption amount
        _openRedemptionAmount += collateralRedeemAmount_;

        // Calculate redemption amount
        uint redemptionAmount_ = collateralRedeemAmount_ - issuanceFeeAmount_;

        // Create and add payment order
        PaymentOrder memory order = PaymentOrder({
            recipient: _msgSender(),
            paymentToken: address(token()),
            amount: collateralRedeemAmount_,
            start: block.timestamp,
            cliff: 0,
            end: block.timestamp
        });
        _addPaymentOrder(order);

        // Process payments through the payment processor
        __Module_orchestrator.paymentProcessor().processPayments(
            IERC20PaymentClientBase_v1(address(this))
        );

        // Emit event with all order details
        emit RedemptionOrderCreated(
            _orderId,
            _msgSender(),
            receiver_,
            depositAmount_,
            _oracle.getPriceForRedemption(),
            collateralRedeemAmount_,
            sellFee,
            issuanceFeeAmount_,
            redemptionAmount_,
            address(token()),
            block.timestamp,
            RedemptionState.PROCESSING
        );

        // Emit event
        emit TokensSold(
            receiver_, depositAmount_, collateralRedeemAmount_, _msgSender()
        );
    }

    /// @notice Executes a sell order, with the proceeds being sent directly to the _receiver's address.
    /// @dev    This function wraps the `_sellOrder` internal function with specified parameters to handle
    ///         the transaction and direct the proceeds.
    /// @param  _receiver The address that will receive the redeemed tokens.
    /// @param  _depositAmount The amount of tokens to be sold.
    /// @param  _minAmountOut The minimum acceptable amount of proceeds that the receiver should receive from the sale.
    function _sellOrder(
        address _receiver,
        uint _depositAmount,
        uint _minAmountOut
    )
        internal
        override(RedeemingBondingCurveBase_v1)
        returns (uint totalCollateralTokenMovedOut, uint issuanceFeeAmount)
    {
        _ensureNonZeroTradeParameters(_depositAmount, _minAmountOut);
        // Get protocol fee percentages and treasury addresses
        (
            address collateralTreasury,
            address issuanceTreasury,
            uint collateralSellFeePercentage,
            uint issuanceSellFeePercentage
        ) = _getFunctionFeesAndTreasuryAddresses(
            bytes4(keccak256(bytes("_sellOrder(address,uint,uint)")))
        );

        uint protocolFeeAmount;
        uint projectFeeAmount;
        uint netDeposit;

        // Get net amount, protocol and project fee amounts. Currently there is no issuance project
        // fee enabled
        (netDeposit, protocolFeeAmount, /* projectFee */ ) =
        _calculateNetAndSplitFees(_depositAmount, issuanceSellFeePercentage, 0);

        issuanceFeeAmount = protocolFeeAmount;

        // Calculate redeem amount based on upstream formula
        uint collateralRedeemAmount = _redeemTokensFormulaWrapper(netDeposit);

        totalCollateralTokenMovedOut = collateralRedeemAmount;

        // Burn issued token from user
        _burn(_msgSender(), _depositAmount);

        // Process the protocol fee. We can re-mint some of the burned tokens, since we aren't paying out
        // the backing collateral
        _processProtocolFeeViaMinting(issuanceTreasury, protocolFeeAmount);

        // Cache Collateral Token
        IERC20 collateralToken = __Module_orchestrator.fundingManager().token();

        // Require that enough collateral token is held to be redeemable
        if (
            (projectCollateralFeeCollected)
                > collateralToken.balanceOf(address(this))
        ) {
            revert
                Module__RedeemingBondingCurveBase__InsufficientCollateralForRedemption(
            );
        }

        // Get net amount, protocol and project fee amounts
        (collateralRedeemAmount, protocolFeeAmount, projectFeeAmount) =
        _calculateNetAndSplitFees(
            collateralRedeemAmount, collateralSellFeePercentage, sellFee
        );
        // Process the protocol fee
        // Protocol fee is not charged for redemption in this implementation
        _processProtocolFeeViaTransfer(
            collateralTreasury, collateralToken, protocolFeeAmount
        );

        // Add project fee if applicable
        if (projectFeeAmount > 0) {
            _projectFeeCollected(projectFeeAmount);
        }

        // Revert when the redeem amount is lower than minimum amount the user expects
        if (collateralRedeemAmount < _minAmountOut) {
            revert Module__BondingCurveBase__InsufficientOutputAmount();
        }

        // Use virtual function to handle collateral tokens
        _handleCollateralTokensAfterSell(_receiver, collateralRedeemAmount);

        // Create and emit the order
        _createAndEmitOrder(
            _receiver, _depositAmount, collateralRedeemAmount, issuanceFeeAmount
        );

        return (totalCollateralTokenMovedOut, issuanceFeeAmount);
    }

    /// @dev    Internal function which only emits the event for amount of project fee collected. The contract
    ///         does not hold collateral as the payout is managed through a redemption queue.
    /// @param  _projectFeeAmount The amount of fee collected.
    function _projectFeeCollected(uint _projectFeeAmount)
        internal
        override(BondingCurveBase_v1)
    {
        emit ProjectCollateralFeeAdded(_projectFeeAmount);
    }

    /// @notice Sets the maximum fee that can be charged for buy operations.
    /// @param  fee_ The maximum fee percentage to set.
    function _setMaxBuyFee(uint fee_) internal {
        _maxBuyFee = fee_;
    }

    /// @notice Sets the maximum fee that can be charged for sell operations.
    /// @param fee_ The maximum fee percentage to set.
    function _setMaxSellFee(uint fee_) internal {
        _maxSellFee = fee_;
    }

    /// @param  depositAmount_ The amount being deposited.
    /// @return mintAmount_ The calculated token amount.
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

    /// @param  depositAmount_ The amount being redeemed.
    /// @return redeemAmount_ The calculated collateral amount.
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

    /// @notice Sets the oracle address
    /// @dev May revert with Module__FM_PC_ExternalPrice_Redeeming_InvalidOracleInterface
    /// @param oracleAddress_ The address of the oracle
    function _setOracleAddress(address oracleAddress_) internal {
        if (
            !ERC165Upgradeable(address(oracleAddress_)).supportsInterface(
                type(IOraclePrice_v1).interfaceId
            )
        ) {
            revert Module__FM_PC_ExternalPrice_Redeeming_InvalidOracleInterface(
            );
        }
        _oracle = IOraclePrice_v1(oracleAddress_);
    }

    /// @notice Sets the project treasury address
    /// @dev May revert with Module__FM_PC_ExternalPrice_Redeeming_InvalidProjectTreasury
    /// @param projectTreasury_ The address of the project treasury
    function _setProjectTreasury(address projectTreasury_) internal {
        if (_projectTreasury == address(0)) {
            revert Module__FM_PC_ExternalPrice_Redeeming_InvalidProjectTreasury(
            );
        }
        _projectTreasury = projectTreasury_;
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

    /// @inheritdoc BondingCurveBase_v1
    /// @dev        Implementation transfer collateral tokens to the project treasury
    function _handleCollateralTokensBeforeBuy(address _provider, uint _amount)
        internal
        virtual
        override
    {
        IERC20(token()).safeTransferFrom(_provider, _projectTreasury, _amount);
    }

    /// @inheritdoc RedeemingBondingCurveBase_v1
    /// @dev    Implementation does not transfer collateral tokens to recipient as the
    ///         payout is managed through a redemption queue.
    function _handleCollateralTokensAfterSell(address recipient_, uint amount_)
        internal
        virtual
        override
    {
        // This function is not used in this implementation
    }
}
