// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

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
 *              - Token selling through redemption queue
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
        PENDING,
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

    /// @notice Emitted when an address is added to the whitelist
    /// @param account_ The whitelisted address
    event AddressWhitelisted(address indexed account_);

    /// @notice Emitted when an address is removed from the whitelist
    /// @param account_ The removed address
    event AddressRemovedFromWhitelist(address indexed account_);

    /// @notice Emitted when multiple addresses are added/removed from whitelist
    /// @param accounts_ Array of affected addresses
    /// @param isAdd_ True if adding to whitelist, false if removing
    event BatchWhitelistUpdated(address[] accounts_, bool isAdd_);

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

    /// @notice Emitted when a redemption order's state changes
    /// @param orderId Order identifier
    /// @param newState New state of the order
    event RedemptionOrderStateUpdated(
        uint indexed orderId, RedemptionState newState
    );

    //--------------------------------------------------------------------------
    // Errors

    /// @notice Thrown when batch operation exceeds size limit
    /// @param size_ Size of the batch attempted
    error FM_ExternalPrice__BatchSizeExceeded(uint size_);

    /// @notice Thrown when attempting to interact with zero address
    error FM_ExternalPrice__ZeroAddress();

    /// @notice Thrown when an invalid amount is provided
    error FM_ExternalPrice__InvalidAmount();

    /// @notice Thrown when interacting with a blacklisted address
    /// @param account_ The blacklisted address
    error FM_ExternalPrice__AddressBlacklisted(address account_);

    /// @notice Thrown when non-whitelisted address attempts restricted operation
    /// @param account_ The non-whitelisted address
    error FM_ExternalPrice__NotWhitelisted(address account_);

    //--------------------------------------------------------------------------
    // View Functions

    /// @notice Gets the maximum number of addresses that can be whitelisted in a batch
    /// @return maxBatchSize_ The maximum batch size
    function getMaxBatchSize() external view returns (uint maxBatchSize_);

    /// @notice Gets the current open redemption amount
    /// @return amount_ The total amount of open redemptions
    function getOpenRedemptionAmount() external view returns (uint amount_);

    /// @notice Gets the next available order ID
    /// @return orderId_ The next order ID
    function getNextOrderId() external view returns (uint orderId_);

    /// @notice Gets the current order ID
    /// @return orderId_ The current order ID
    function getOrderId() external view returns (uint orderId_);

    /// @notice Buys tokens with provided collateral
    /// @param collateralAmount_ The amount of collateral to spend
    function buy(uint collateralAmount_, uint minAmountOut_) external;

    /// @notice Sells tokens for collateral through redemption queue
    /// @param receiver_ Address to receive collateral
    /// @param depositAmount_ Amount of tokens to sell
    /// @param minAmountOut_ Minimum collateral to receive
    function sell(address receiver_, uint depositAmount_, uint minAmountOut_)
        external;
}
