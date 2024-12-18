// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal
import {IPaymentProcessor_v1} from "@pp/IPaymentProcessor_v1.sol";

/**
 * @title   Queue Based Payment Processor
 *
 * @notice  A payment processor implementation that manages payment orders through
 *          a FIFO queue system. It supports automated execution of payments
 *          within the processPayments function.
 *
 * @dev     This contract inherits from:
 *              - IPP_Queue_v1.
 *              - Module_v1.
 *          Key features:
 *              - FIFO queue management.
 *              - Automated payment execution.
 *              - Payment order lifecycle management.
 *          The contract implements automated payment processing by executing
 *          the queue within processPayments.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @custom:version  v1.0.0
 *
 * @custom:standard-version v1.0.0
 *
 * @author  Zealynx Security
 */
interface IPP_Queue_v1 is IPaymentProcessor_v1 {
    // -------------------------------------------------------------------------
    // Type Declarations

    // Enum for redemption order states
    enum RedemptionState {
        COMPLETED,
        CANCELLED,
        PROCESSING
    }

    // -------------------------------------------------------------------------
    // Structs

    /// @notice	Represents a payment order in the queue.
    /// @param	recipient_ Address to receive the payment.
    /// @param	token_ Address of the token to be transferred.
    /// @param	amount_ Amount of tokens to be transferred.
    /// @param	flags_ Processing flags for order handling.
    /// @param	state_ Current state of the payment order.
    /// @param	orderId_ Unique identifier for the payment order.
    /// @param	timestamp_ Creation time of the payment order.
    struct PaymentOrder {
        address recipient_;         // Payment recipient
        address token_;             // Token to be transferred
        uint256 amount_;            // Payment amount
        uint256 flags_;             // Processing flags
        RedemptionState state_;     // Current order state
        uint256 orderId_;           // Unique identifier
        uint256 timestamp_;         // Creation timestamp
    }

    // -------------------------------------------------------------------------
    // Events

    /// @notice	Emitted when a new payment order enters the queue.
    /// @param	orderId_ Unique identifier of the payment order.
    /// @param	recipient_ Address that will receive the payment.
    /// @param	token_ Address of the token to be transferred.
    /// @param	amount_ Amount of tokens to be transferred.
    /// @param	flags_ Processing flags for the order.
    /// @param	timestamp_ Time when the order was created.
    event PaymentOrderQueued(
        uint256 indexed orderId_,
        address indexed recipient_,
        address indexed token_,
        uint256 amount_,
        uint256 flags_,
        uint256 timestamp_
    );

    /// @notice	Emitted when a payment order changes its state.
    /// @param	orderId_ Unique identifier of the payment order.
    /// @param	state_ New state of the payment order.
    event PaymentOrderStateChanged(
        uint256 indexed orderId_,
        RedemptionState indexed state_
    );

    // -------------------------------------------------------------------------
    // Errors

    /// @notice	Operation attempted with zero amount.
    error Module__PP_Queue_ZeroAmount();

    /// @notice	Payment order not found in queue.
    error Module__PP_Queue_InvalidOrderId();

    /// @notice	Caller not authorized for operation.
    error Module__PP_Queue_Unauthorized();

    /// @notice	Order in invalid state for operation.
    error Module__PP_Queue_InvalidState();

    /// @notice	Queue operation failed.
    error Module__PP_Queue_QueueOperationFailed();

    /// @notice	Caller not authorized for operation.
    error Module__PP_Queue_OnlyCallableByClient();

    // -------------------------------------------------------------------------
    // Functions

    /// @notice	Retrieves a payment order by its ID.
    /// @param	orderId_ The ID of the payment order.
    /// @return	order_ The payment order data.
    function getOrder(uint256 orderId_) 
        external 
        view 
        returns (PaymentOrder memory order_);

    /// @notice	Gets the current queue of order IDs.
    /// @return	queue_ Array of order IDs in queue.
    function getOrderQueue() 
        external 
        view 
        returns (uint256[] memory queue_);

    /// @notice	Gets the current position in queue for processing.
    /// @return	head_ Current queue head position.
    function getQueueHead() 
        external 
        view 
        returns (uint256 head_);

    /// @notice	Gets the next insertion position in queue.
    /// @return	tail_ Current queue tail position.
    function getQueueTail() 
        external 
        view 
        returns (uint256 tail_);

    /// @notice	Gets total number of orders created.
    /// @return	total_ Total number of orders.
    function getTotalOrders() 
        external 
        view 
        returns (uint256 total_);

    /// @notice	Adds a new payment order to the queue.
    /// @param	client_ Address of the client requesting the payment.
    /// @param	token_ Address of the token to be transferred.
    /// @param	receiver_ Address that will receive the payment.
    /// @param	amount_ Amount of tokens to be transferred.
    /// @param	data_ Additional data for payment processing.
    /// @return	orderId_ Unique identifier of the created order.
    function addPaymentOrderToQueue(
        address client_,
        address token_,
        address receiver_,
        uint256 amount_,
        bytes calldata data_
    ) external returns (uint256 orderId_);

    /// @notice	Cancels a payment order by its queue ID.
    /// @param	orderId_ The ID of the order to cancel.
    /// @return	success_ True if cancellation was successful.
    function cancelPaymentOrderThroughQueueId(uint256 orderId_)
        external
        returns (bool success_);

    /// @notice	Processes the next order in the queue.
    /// @return	success_ True if processing was successful.
    function processNextOrder()
        external
        returns (bool success_);
}
