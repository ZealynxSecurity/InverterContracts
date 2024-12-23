// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal
import {IPaymentProcessor_v1} from "@pp/IPaymentProcessor_v1.sol";
import {IERC20PaymentClientBase_v1} from
    "@lm/interfaces/IERC20PaymentClientBase_v1.sol";

/**
 * @title   Queue Based Payment Processor
 *
 * @notice  A payment processor implementation that manages payment orders through
 *          a FIFO queue system. It supports automated execution of payments
 *          within the processPayments function.
 *
 * @dev     This contract inherits from:
 *              - IPP_Queue_v1.
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

    // Enum for redemption order states.
    enum RedemptionState {
        COMPLETED,
        CANCELLED,
        PROCESSING
    }

    // -------------------------------------------------------------------------
    // Structs

    /// @notice	Queued payment order information.
    /// @param	order_ Original payment order from client.
    /// @param	state_ Current state of the payment order.
    /// @param	orderId_ Unique identifier of the payment order.
    /// @param	timestamp_ Creation timestamp of the payment order.
    /// @param  client_ Address of the client paying for the order.
    struct QueuedOrder {
        IERC20PaymentClientBase_v1.PaymentOrder order_;
        RedemptionState state_;
        uint orderId_;
        uint timestamp_;
        address client_;
    }

    // -------------------------------------------------------------------------
    // Events

    /// @notice	Emitted when a new payment order enters the queue.
    /// @param	orderId_ Unique identifier of the payment order.
    /// @param	recipient_ Address that will receive the payment.
    /// @param	token_ Address of the token to be transferred.
    /// @param  client_ Address of the client that queued the order.
    /// @param	amount_ Amount of tokens to be transferred.
    /// @param	flags_ Processing flags for the order.
    /// @param	timestamp_ Time when the order was created.
    event PaymentOrderQueued(
        uint indexed orderId_,
        address indexed recipient_,
        address indexed token_,
        address client_,
        uint amount_,
        uint flags_,
        uint timestamp_
    );

    /// @notice	Emitted when a payment order changes its state.
    /// @param	orderId_ Unique identifier of the payment order.
    /// @param	state_ New state of the payment order.
    /// @param  client_ Address of the client that owns the order.
    event PaymentOrderStateChanged(
        uint indexed orderId_,
        RedemptionState indexed state_,
        address indexed client_
    );

    /// @notice  Emitted when an order is skipped due to timing constraints.
    /// @param   orderId_ ID of the order.
    /// @param   client_ Address of the client that owns the order.
    /// @param   reason_ Reason for skipping:
    ///             1: not started,
    ///             2: in cliff,
    ///             3: expired.
    /// @param   currentTime_ Current block timestamp.
    event PaymentOrderTimingSkip(
        uint indexed orderId_,
        address indexed client_,
        uint8 reason_,
        uint currentTime_
    );

    /// @notice  Emitted when the payment queue is executed.
    /// @param   executor_ Address that executed the queue.
    /// @param   client_ Address of the client whose queue was executed.
    /// @param   count_ Number of orders processed.
    event PaymentQueueExecuted(
        address indexed executor_, address indexed client_, uint count_
    );

    // -------------------------------------------------------------------------
    // Errors

    /// @notice	Operation attempted with zero amount.
    error Module__PP_Queue_ZeroAmount();

    /// @notice	Payment order not found in queue.
    /// @param  client_ Address of the client.
    /// @param  orderId_ ID of the order that was not found.
    error Module__PP_Queue_InvalidOrderId(address client_, uint orderId_);

    /// @notice	Caller not authorized for operation.
    error Module__PP_Queue_Unauthorized();

    /// @notice	Order in invalid state for operation.
    error Module__PP_Queue_InvalidState();

    /// @notice	Queue operation failed.
    /// @param  client_ Address of the client whose queue failed.
    error Module__PP_Queue_QueueOperationFailed(address client_);

    /// @notice Only callable by a valid client.
    error Module__PP_Queue_OnlyCallableByClient();

    /// @notice	Invalid configuration parameters provided.
    error Module__PP_Queue_InvalidConfig();

    /// @notice	Invalid payment order recipient.
    /// @param  recipient_ The invalid recipient address.
    error Module__PP_Queue_InvalidRecipient(address recipient_);

    /// @notice	Invalid payment token.
    /// @param  token_ The invalid token address.
    error Module__PP_Queue_InvalidToken(address token_);

    /// @notice	Invalid payment amount.
    /// @param  amount_ The invalid amount.
    error Module__PP_Queue_InvalidAmount(uint amount_);

    /// @notice	Invalid chain ID in payment order.
    /// @param  originChainId_ The origin chain ID.
    /// @param  targetChainId_ The target chain ID.
    /// @param  currentChainId_ The current chain ID.
    error Module__PP_Queue_InvalidChainId(
        uint originChainId_, uint targetChainId_, uint currentChainId_
    );

    /// @notice Invalid flags or data format.
    /// @param  flags_ The flags provided.
    /// @param  dataLength_ The length of the data array.
    error Module__PP_Queue_InvalidFlagsOrData(bytes32 flags_, uint dataLength_);

    /// @notice Invalid token implementation.
    /// @param  token_ The invalid token address.
    error Module__PP_Queue_InvalidTokenImplementation(address token_);

    /// @notice	Invalid order state transition.
    /// @param  orderId_ The order ID.
    /// @param  currentState_ Current state of the order.
    /// @param  newState_ Attempted new state.
    error Module__PP_Queue_InvalidStateTransition(
        uint orderId_, RedemptionState currentState_, RedemptionState newState_
    );

    /// @notice	Queue is empty.
    error Module__PP_Queue_EmptyQueue();

    /// @notice	Invalid client address.
    /// @param  client_ The invalid client address.
    error Module__PP_Queue_InvalidClientAddress(address client_);

    // -------------------------------------------------------------------------
    // Functions

    /// @notice	Retrieves a payment order by its ID.
    /// @param  orderId_ The ID of the payment order.
    /// @return	order_ The payment order data.
    function getOrder(uint orderId_)
        external
        view
        returns (QueuedOrder memory order_);

    /// @notice	Gets the current queue of order IDs.
    /// @param  client_ Address of the client whose queue to get.
    /// @return	queue_ Array of order IDs in queue.
    function getOrderQueue(address client_)
        external
        view
        returns (uint[] memory queue_);

    /// @notice	Gets the current position in queue for processing.
    /// @param  client_ Address of the client whose queue head to get.
    /// @return	head_ Current queue head position.
    function getQueueHead(address client_) external view returns (uint head_);

    /// @notice	Gets the next insertion position in queue.
    /// @param  client_ Address of the client whose queue tail to get.
    /// @return	tail_ Current queue tail position.
    function getQueueTail(address client_) external view returns (uint tail_);

    /// @notice	Gets the size of the queue.
    /// @param  client_ Address of the client whose queue size to get.
    /// @return	size_ Current queue size.
    function getQueueSize(address client_) external view returns (uint size_);

    /// @notice	Gets total number of orders created.
    /// @return	total_ Total number of orders.
    function getTotalOrders() external view returns (uint total_);

    /// @notice  Gets the role identifier for queue operations.
    /// @dev     Role for queue operations.
    /// @return  role_ The queue operator role identifier.
    function getQueueOperatorRole() external pure returns (bytes32 role_);

    /// @notice	Cancels a payment order by its queue ID.
    /// @param	orderId_ The ID of the order to cancel.
    /// @return	success_ True if cancellation was successful.
    function cancelPaymentOrderThroughQueueId(uint orderId_)
        external
        returns (bool success_);
}
