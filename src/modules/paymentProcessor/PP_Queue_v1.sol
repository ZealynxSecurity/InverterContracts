// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal
import {IOrchestrator_v1} from 
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IPaymentProcessor_v1} from "@pp/IPaymentProcessor_v1.sol";
import {IERC20PaymentClientBase_v1} from 
    "@lm/interfaces/IERC20PaymentClientBase_v1.sol";
import {IPP_Queue_v1} from "@pp/interfaces/IPP_Queue_v1.sol";
import {ERC165Upgradeable, Module_v1} from 
    "src/modules/base/Module_v1.sol";

// External
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

/**
 * @title   Inverter Queue Based Payment Processor.
 *
 * @notice  Payment Processor which implements a payment queue.
 *
 * @dev     @todo add dev information once all the features have been defined.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer
 *                          to our Security Policy at security.inverter.network
 *                          or email us directly!
 *
 * @custom:version 1.0.0
 *
 * @author  Inverter Network
 */
contract PP_Queue_v1 is IPP_Queue_v1, Module_v1 {
    // -------------------------------------------------------------------------
    // Libraries

    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // ERC165

    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override(Module_v1) returns (bool supported_) {
        return interfaceId_ == type(IPP_Queue_v1).interfaceId
            || interfaceId_ == type(IPaymentProcessor_v1).interfaceId
            || super.supportsInterface(interfaceId_);
    }

    // -------------------------------------------------------------------------
    // Constants

    /// @dev    Role identifier for queue management operations.
    bytes32 public constant QUEUE_MANAGER_ROLE = "QUEUE_MANAGER_ROLE";

    // -------------------------------------------------------------------------
    // Storage

    /// @dev    Role for queue operations.
    bytes32 public constant QUEUE_OPERATOR_ROLE = "QUEUE_OPERATOR";

    /// @notice Tracks all payments that could not be made to the paymentReceiver.
    /// @dev    client => token => receiver => unclaimable amount.
    mapping(
        address client => 
        mapping(address token => 
        mapping(address receiver => uint256 amount))
    ) private _unclaimableAmountsForRecipient;

    /// @notice Tracks payment orders by their ID.
    /// @dev    orderId => order details.
    mapping(uint256 orderId => PaymentOrder order) private _orders;

    /// @dev    Array to maintain the FIFO queue of order IDs.
    uint256[] private _orderQueue;

    /// @dev    Current position in queue for processing.
    uint256 private _queueHead;

    /// @dev    Next insertion position in queue.
    uint256 private _queueTail;

    /// @dev    Total number of orders created.
    uint256 private _totalOrders;

    /// @dev    Gap for possible future upgrades.
    uint[50] private __gap;

    // -------------------------------------------------------------------------
    // Modifiers

    /// @dev    Checks that the client is calling for itself.
    modifier clientIsValid(address client_) {
        // Modifier logic moved to internal function for contract size reduction.
        _ensureValidClient(client_);
        _;
    }

    /// @dev    Checks that the caller is an active module.
    modifier onlyModule() {
        if (!orchestrator().isModule(_msgSender())) {
            revert Module__PaymentProcessor__OnlyCallableByModule();
        }
        _;
    }

    // -------------------------------------------------------------------------
    // Constructor & Init

    /// @inheritdoc Module_v1
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata_,
        bytes memory configData_
    ) external override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata_);

        // @todo add init params if needed
        // () = abi.decode(configData_, (uint));
    }

    //--------------------------------------------------------------------------
    // Public (Getters)

    /// @inheritdoc IPP_Queue_v1
    function getOrder(
        uint256 orderId_
    ) external view returns (PaymentOrder memory order_) {
        order_ = _orders[orderId_];
        if (order_.orderId_ == 0) {
            revert Module__PP_Queue_InvalidOrderId();
        }
    }

    /// @inheritdoc IPP_Queue_v1
    function getOrderQueue() external view returns (uint256[] memory queue_) {
        queue_ = _orderQueue;
    }

    /// @inheritdoc IPP_Queue_v1
    function getQueueHead() external view returns (uint256 head_) {
        head_ = _queueHead;
    }

    /// @inheritdoc IPP_Queue_v1
    function getQueueTail() external view returns (uint256 tail_) {
        tail_ = _queueTail;
    }

    /// @inheritdoc IPP_Queue_v1
    function getTotalOrders() external view returns (uint256 total_) {
        total_ = _totalOrders;
    }

    //--------------------------------------------------------------------------
    // Public (Mutating)

    /// @inheritdoc IPaymentProcessor_v1
    function processPayments(IERC20PaymentClientBase_v1 client_)
        external
        virtual
        clientIsValid(address(client_))
    {
        // Collect outstanding orders and their total token amount.
        IERC20PaymentClientBase_v1.PaymentOrder[] memory orders;

        (orders,,) = client_.collectPaymentOrders();

        uint orderLength = orders.length;
        for (uint i; i < orderLength; ++i) {
            // Add order to order queue
            _addPaymentOrderToQueue(orders[i]);
        }
        // Execute Order Queue
        _executePaymentQueue();
    }

    /// @inheritdoc IPaymentProcessor_v1
    function cancelRunningPayments(IERC20PaymentClientBase_v1 client_)
        external
        view
        clientIsValid(address(client_))
    {
        return;
    }

    /// @inheritdoc IPaymentProcessor_v1
    function unclaimable(
        address client,
        address token,
        address paymentReceiver
    ) public view returns (uint256 amount_) {
        return _unclaimableAmountsForRecipient[client][token][paymentReceiver];
    }

    /// @inheritdoc IPaymentProcessor_v1
    function claimPreviouslyUnclaimable(
        address client,
        address token,
        address receiver
    ) external {
        if (unclaimable(client, token, _msgSender()) == 0) {
            revert Module__PaymentProcessor__NothingToClaim(
                client, _msgSender()
            );
        }

        _claimPreviouslyUnclaimable(client, token, receiver);
    }

    /// @inheritdoc IPaymentProcessor_v1
    function validPaymentOrder(
        IERC20PaymentClientBase_v1.PaymentOrder memory order_
    ) external view returns (bool isValid_) {
        // This function is used to validate the payment order created on the
        // client side (in our case FM_PC_ManualExternal...) with the input required by the Payment Processor
        // (PP). The function should return true if the payment order is valid
        // and false if it is not.

        // // @todo call about the new payment order struct
        // (uint queueId, /* Something else? */ ) =
        //     _getPaymentQueueDetails(order_.flags, order_.data);

        // // // @todo add calls to internal validation functions. Example can be seen in PP_Streaming -> validPaymentOrde() function
        // return _validPaymentReceiver(order_.recipient)
        //     && _validTotal(order_.amount) && _validQueueId(queueId);
        return true;
    }

    /// @inheritdoc IPP_Queue_v1
    function addPaymentOrderToQueue(
        address client_,
        address token_,
        address receiver_,
        uint256 amount_,
        bytes calldata data_
    ) external onlyModuleRole(QUEUE_OPERATOR_ROLE) returns (uint256 orderId_) {
        // Increment total orders to get new ID
        orderId_ = ++_totalOrders;

        // Create new payment order
        PaymentOrder memory newOrder = PaymentOrder({
            recipient_: receiver_,
            token_: token_,
            amount_: amount_,
            flags_: 0, // No flags needed for basic queue
            state_: RedemptionState.PROCESSING,
            orderId_: orderId_,
            timestamp_: block.timestamp
        });

        // Store order and add to queue
        _orders[orderId_] = newOrder;
        _orderQueue.push(orderId_);
        _queueTail = _orderQueue.length;

        emit PaymentOrderQueued(
            orderId_,
            newOrder.recipient_,
            newOrder.token_,
            newOrder.amount_,
            newOrder.flags_,
            newOrder.timestamp_
        );
    }

    /// @inheritdoc IPP_Queue_v1
    function cancelPaymentOrderThroughQueueId(uint256 orderId_)
        external
        onlyModuleRole(QUEUE_OPERATOR_ROLE)
        returns (bool success_)
    {
        // Validate queue ID
        if (!_validQueueId(orderId_)) {
            revert Module__PP_Queue_InvalidOrderId();
        }

        PaymentOrder storage order = _orders[orderId_];
        
        // Check if order can be cancelled
        if (order.state_ != RedemptionState.PROCESSING) {
            revert Module__PP_Queue_InvalidState();
        }

        // Update order state
        _updateOrderState(orderId_, RedemptionState.CANCELLED);

        // Add amount to unclaimable
        _setUnclaimableAmount(
            _msgSender(),
            order.token_,
            order.recipient_,
            order.amount_
        );
        return true;
    }

    /// @inheritdoc IPP_Queue_v1
    function processNextOrder()
        external
        onlyModuleRole(QUEUE_OPERATOR_ROLE)
        returns (bool success_)
    {
        if (_queueHead >= _queueTail) {
            return false;
        }

        uint256 orderId = _orderQueue[_queueHead++];
        PaymentOrder storage order = _orders[orderId];

        // Skip if order is not in PROCESSING state
        if (order.state_ != RedemptionState.PROCESSING) {
            return false;
        }

        IERC20(order.token_).safeTransfer(order.recipient_, order.amount_);
        _updateOrderState(orderId, RedemptionState.COMPLETED);
        return true;
    }

    // -------------------------------------------------------------------------
    // Internal

    /// @notice used to claim the unclaimable amount of a particular `paymentReceiver` for a given payment client.
    /// @param  client address of the payment client.
    /// @param  token address of the payment token.
    /// @param  paymentReceiver address of the paymentReceiver for which the unclaimable amount will be claimed.
    function _claimPreviouslyUnclaimable(
        address client,
        address token,
        address paymentReceiver
    ) internal {
        // get amount

        address sender = _msgSender();
        // copy value over
        uint amount = _unclaimableAmountsForRecipient[client][token][sender];
        // Delete the field
        delete _unclaimableAmountsForRecipient[client][token][sender];

        // Make sure to let paymentClient know that amount doesnt have to be stored anymore
        IERC20PaymentClientBase_v1(client).amountPaid(token, amount);

        // Call has to succeed otherwise no state change
        IERC20(token).safeTransferFrom(client, paymentReceiver, amount);

        emit TokensReleased(paymentReceiver, address(token), amount);
    }

    /// @dev    Adds a new payment order to the queue.
    /// @param  order_ The payment order to add.
    /// @return orderId_ The ID of the newly added order.
    function _addPaymentOrderToQueue(
        IERC20PaymentClientBase_v1.PaymentOrder memory order_
    ) internal returns (uint256 orderId_) {
        // Increment total orders to get new ID
        orderId_ = ++_totalOrders;

        // Create new payment order
        PaymentOrder memory newOrder = PaymentOrder({
            recipient_: order_.recipient,
            token_: order_.paymentToken,
            amount_: order_.amount,
            flags_: 0, // No flags needed for basic queue
            state_: RedemptionState.PROCESSING,
            orderId_: orderId_,
            timestamp_: block.timestamp
        });

        // Store order and add to queue
        _orders[orderId_] = newOrder;
        _orderQueue.push(orderId_);
        _queueTail = _orderQueue.length;

        emit PaymentOrderQueued(
            orderId_,
            newOrder.recipient_,
            newOrder.token_,
            newOrder.amount_,
            newOrder.flags_,
            newOrder.timestamp_
        );
    }

    /// @dev    Updates the state of a payment order.
    /// @param  orderId_ The ID of the order to update.
    /// @param  state_ The new state to set.
    function _updateOrderState(
        uint256 orderId_,
        RedemptionState state_
    ) internal {
        PaymentOrder storage order = _orders[orderId_];
        if (order.orderId_ == 0) {
            revert Module__PP_Queue_InvalidOrderId();
        }
        
        order.state_ = state_;
        emit PaymentOrderStateChanged(orderId_, state_);
    }

    /// @dev    Processes the next order in the queue.
    /// @return processed_ True if an order was processed successfully.
    function _processNextOrder() internal returns (bool processed_) {
        if (_queueHead >= _queueTail) {
            return false;
        }

        uint256 orderId = _orderQueue[_queueHead++];
        PaymentOrder storage order = _orders[orderId];

        // Skip if order is not in PROCESSING state
        if (order.state_ != RedemptionState.PROCESSING) {
            return false;
        }

        IERC20(order.token_).safeTransfer(order.recipient_, order.amount_);
        _updateOrderState(orderId, RedemptionState.COMPLETED);
        return true;
    }

    /// @dev    Executes all pending orders in the queue.
    function _executePaymentQueue() internal {
        uint256 remainingGas = gasleft();
        uint256 gasBuffer = 50000; // Buffer for remaining operations

        while (
            remainingGas > gasBuffer && 
            _queueHead < _queueTail
        ) {
            _processNextOrder();
            remainingGas = gasleft();
        }
    }

    /// @dev    Validates if a queue ID is valid.
    /// @param  queueId_ The queue ID to validate.
    /// @return isValid_ True if the queue ID is valid.
    function _validQueueId(uint256 queueId_) internal view returns (bool isValid_) {
        // Queue ID must be less than or equal to total orders
        // and greater than 0 (we start from 1)
        return queueId_ > 0 && queueId_ <= _totalOrders;
    }

    /// @dev    Gets payment queue details from flags and data.
    /// @param  flags_ The payment order flags.
    /// @param  data_ Additional payment order data.
    /// @return queueId_ The queue ID from the data.
    function _getPaymentQueueDetails(
        bytes32 flags_,
        bytes32[] memory data_
    ) internal pure returns (uint256 queueId_) {
        // Extract queue ID from first data element if available
        if (data_.length > 0) {
            queueId_ = uint256(data_[0]);
        }
    }

    /// @notice Validate uint total amount input.
    /// @param  amount_ Amount to validate.
    /// @return valid_ True if uint is valid.
    function _validTotal(uint256 amount_) internal pure returns (bool valid_) {
        return !(amount_ == 0);
    }

    /// @dev    Validate whether the address is a valid payment receiver.
    /// @param  receiver_ Address to validate.
    /// @return validPaymentReceiver_ True if address is valid.
    function _validPaymentReceiver(address receiver_)
        internal
        view
        returns (bool validPaymentReceiver_)
    {
        return !(
            receiver_ == address(0) || receiver_ == _msgSender()
                || receiver_ == address(this)
                || receiver_ == address(orchestrator())
                || receiver_ == address(orchestrator().fundingManager().token())
        );
    }

    /// @dev    Internal function to check whether the client is valid.
    /// @param  client_ Address to validate.
    function _ensureValidClient(address client_) internal view {
        if (client_ != _msgSender()) {
            revert Module__PP_Queue_OnlyCallableByClient();
        }
    }

    /// @dev    Sets the unclaimable amount for a specific payment.
    /// @param  client_ The client address.
    /// @param  token_ The token address.
    /// @param  receiver_ The receiver address.
    /// @param  amount_ The amount to set.
    function _setUnclaimableAmount(
        address client_,
        address token_,
        address receiver_,
        uint256 amount_
    ) internal {
        _unclaimableAmountsForRecipient[client_][token_][receiver_] = amount_;
    }

    // -------------------------------------------------------------------------
    // Internal override
}
