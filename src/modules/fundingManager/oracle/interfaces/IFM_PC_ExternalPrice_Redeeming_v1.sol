// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Imports

// Internal
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
import {IERC20PaymentClientBase_v1} from
    "@lm/interfaces/IERC20PaymentClientBase_v1.sol";
import {IRedeemingBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IRedeemingBondingCurveBase_v1.sol";

/**
 * @title   External Price Funding Manager Interface
 *
 * @notice  Interface for a funding manager that uses external price feeds for token
 *          operations, integrating payment client functionality and supporting
 *          token redemption mechanisms.
 *
 * @dev     This interface inherits from:
 *              - IFundingManager_v1
 *              - IERC20PaymentClientBase_v1
 *              - IRedeemingBondingCurveBase_v1
 *          Key operations:
 *              - Token buying with collateral
 *              - Token selling through creation of payment orders
 *              - Price calculations for tokens and collateral
 *          All operations must respect external price feeds and access control
 *          mechanisms defined in the implementation.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @author  Zealynx Security
 */
interface IFM_PC_ExternalPrice_Redeeming_v1 is
    IFundingManager_v1,
    IERC20PaymentClientBase_v1,
    IRedeemingBondingCurveBase_v1
{
    //--------------------------------------------------------------------------
    // Type Declarations

    // Enum for redemption order states
    enum RedemptionState {
        COMPLETED,
        CANCELLED,
        PROCESSING
    }

    // Struct to store order details
    struct RedemptionOrder {
        address seller;
        uint sellAmount;
        uint exchangeRate;
        uint collateralAmount;
        uint feePercentage;
        uint feeAmount;
        uint redemptionAmount;
        address collateralToken;
        uint redemptionTime;
        RedemptionState state;
    }

    //--------------------------------------------------------------------------
    // Events

    /// @notice Emitted when reserve tokens are deposited
    /// @param depositor The address depositing tokens
    /// @param amount The amount deposited
    event ReserveDeposited(address indexed depositor, uint amount);

    /// @notice Emitted when a new redemption order is created
    /// @param orderId Order identifier
    /// @param seller Address selling tokens
    /// @param sellAmount Amount of tokens to sell
    /// @param exchangeRate Current exchange rate
    /// @param collateralAmount Amount of collateral
    /// @param feePercentage Fee percentage applied
    /// @param feeAmount Fee amount calculated
    /// @param redemptionAmount Final redemption amount
    /// @param collateralToken Address of collateral token
    /// @param redemptionTime Time of redemption
    /// @param state Initial state of the order
    event RedemptionOrderCreated(
        uint indexed orderId,
        address indexed seller,
        address indexed receiver,
        uint sellAmount,
        uint exchangeRate,
        uint collateralAmount,
        uint feePercentage,
        uint feeAmount,
        uint redemptionAmount,
        address collateralToken,
        uint redemptionTime,
        RedemptionState state
    );

    //--------------------------------------------------------------------------
    // Errors

    /// @notice Thrown when an invalid amount is provided
    error Module__FM_PC_ExternalPrice_Redeeming_InvalidAmount();

    /// @notice Fee exceeds maximum allowed value
    /// @param fee The fee that was attempted to be set
    /// @param maxFee The maximum allowed fee
    error Module__FM_PC_ExternalPrice_Redeeming_FeeExceedsMaximum(uint256 fee, uint256 maxFee);

    /// @notice Thrown when the oracle contract does not implement the required interface
    error Module__FM_PC_ExternalPrice_Redeeming_InvalidOracleInterface();

    /// @notice Thrown when third-party operations are disabled
    error Module__FM_PC_ExternalPrice_Redeeming_ThirdPartyOperationsDisabled();

    //--------------------------------------------------------------------------
    // View Functions

    /// @notice Gets the current open collateral redemption amount
    /// @return amount_ The total amount of open redemptions
    function getOpenRedemptionAmount() external view returns (uint amount_);

    /// @notice Gets the next available order ID
    /// @return orderId_ The next order ID
    function getNextOrderId() external view returns (uint orderId_);

    /// @notice Gets the current order ID
    /// @return orderId_ The current order ID
    function getOrderId() external view returns (uint orderId_);

    /// @notice Allows depositing collateral to provide reserves for redemptions
    /// @param amount_ The amount of collateral to deposit
    function depositReserve(uint amount_) external;
}
