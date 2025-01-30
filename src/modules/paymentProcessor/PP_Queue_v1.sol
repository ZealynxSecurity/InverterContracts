// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// -------------------------------------------------------------------------
// External Imports
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

// -------------------------------------------------------------------------
// Internal Imports
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IPaymentProcessor_v1} from "@pp/IPaymentProcessor_v1.sol";
import {IERC20PaymentClientBase_v1} from
    "@lm/interfaces/IERC20PaymentClientBase_v1.sol";
import {IPP_Queue_v1} from "@pp/interfaces/IPP_Queue_v1.sol";
import {ERC165Upgradeable, Module_v1} from "src/modules/base/Module_v1.sol";
import {LinkedIdList} from "src/modules/lib/LinkedIdList.sol";

/**
 * @title   Queue Based Payment Processor
 *
 * @notice  A payment processor implementation that manages payment orders through
 *          a FIFO queue system. It supports automated execution of payments
 *          within the processPayments function.
 *
 * @dev     This contract inherits from:
 *              - IPP_Queue_v1
 *              - Module_v1
 *
 *          Key features:
 *              - FIFO queue management
 *              - Automated payment execution
 *              - Payment order lifecycle management
 *
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
contract PP_Queue_v1 is IPP_Queue_v1, Module_v1 {
    // -------------------------------------------------------------------------
    // Libraries

    using SafeERC20 for IERC20;
    using LinkedIdList for LinkedIdList.List;

    // -------------------------------------------------------------------------
    // ERC165

    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId_)
        public
        view
        virtual
        override(Module_v1)
        returns (bool supported_)
    {
        return interfaceId_ == type(IPP_Queue_v1).interfaceId
            || interfaceId_ == type(IPaymentProcessor_v1).interfaceId
            || super.supportsInterface(interfaceId_);
    }

    // -------------------------------------------------------------------------
    // Constants

    /// @notice    Flag position in the flags byte.
    uint8 private constant FLAG_ORDER_ID = 0;

    /// @notice Role identifier for queue operations.
    /// @dev    This role cancels payments in the queue.
    bytes32 private constant QUEUE_OPERATOR_ROLE = "QUEUE_OPERATOR_ROLE";

    /// @notice Role identifier for the admin authorized to assign the queue
    ///         operator role.
    /// @dev    This role should be set as the role admin for the
    ///         QUEUE_OPERATOR_ROLE within the Authorizer module.
    bytes32 private constant QUEUE_OPERATOR_ROLE_ADMIN =
        "QUEUE_OPERATOR_ROLE_ADMIN";

    // -------------------------------------------------------------------------
    // Storage

    /// @notice Queue of payment orders per client.
    mapping(address client => LinkedIdList.List queue) private _queue;

    /// @notice Payment orders.
    mapping(uint orderId => QueuedOrder order) private _orders;

    /// @notice Current order ID per client.
    mapping(address client => uint currentOrderId) private _currentOrderId;

    /// @notice Tracks all payments that could not be made to the
    ///         paymentReceiver.
    mapping(
        address client
            => mapping(
                address token
                    => mapping(address receiver => uint unclaimableAmount)
            )
    ) private _unclaimableAmountsForRecipient;

    // -------------------------------------------------------------------------
    // Modifiers

    /// @dev    Checks that the calling client is valid.
    modifier clientIsValid(address client_) {
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
    // Initialize

    /// @inheritdoc Module_v1
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata_,
        bytes memory /*configData_*/
    ) external override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata_);
    }

    //--------------------------------------------------------------------------
    // Public View Functions

    /// @inheritdoc IPP_Queue_v1
    function getOrder(uint orderId_, IERC20PaymentClientBase_v1 client_)
        external
        view
        returns (QueuedOrder memory order_)
    {
        if (!_orderExists(orderId_, client_)) {
            revert Module__PP_Queue_InvalidOrderId(address(client_), orderId_);
        }
        order_ = _orders[orderId_];
    }

    /// @inheritdoc IPP_Queue_v1
    function getOrderQueue(address client_)
        external
        view
        returns (uint[] memory queue_)
    {
        // If queue is empty, return empty array.
        if (_queue[client_].length() == 0) {
            return new uint[](0);
        }

        uint[] memory queue = new uint[](_queue[client_].length());
        uint index_;

        for (
            uint id = _queue[client_].getNextId(LinkedIdList._SENTINEL);
            id != LinkedIdList._SENTINEL;
            id = _queue[client_].getNextId(id)
        ) {
            queue[index_++] = id;
        }

        queue_ = queue;
    }

    /// @inheritdoc IPP_Queue_v1
    function getQueueHead(address client_) external view returns (uint head_) {
        // Check if queue is initialized by checking if sentinel position exists
        if (_queue[client_].list[LinkedIdList._SENTINEL] == 0) {
            revert Module__PP_Queue_QueueOperationFailed(client_);
        }
        head_ = _queue[client_].getNextId(LinkedIdList._SENTINEL);
    }

    /// @inheritdoc IPP_Queue_v1
    function getQueueTail(address client_) external view returns (uint tail_) {
        tail_ = _queue[client_].lastId();
    }

    /// @inheritdoc IPP_Queue_v1
    function getQueueSizeForClient(address client_)
        external
        view
        returns (uint size_)
    {
        size_ = _queue[client_].length();
    }

    /// @inheritdoc IPP_Queue_v1
    function getQueueOperatorRole() external pure returns (bytes32 role_) {
        return QUEUE_OPERATOR_ROLE;
    }

    /// @inheritdoc IPP_Queue_v1
    function getQueueOperatorAdminRole()
        external
        pure
        returns (bytes32 role_)
    {
        return QUEUE_OPERATOR_ROLE_ADMIN;
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    /// @inheritdoc IPaymentProcessor_v1
    function processPayments(IERC20PaymentClientBase_v1 client_)
        external
        virtual
        clientIsValid(address(client_))
        onlyModule
    {
        // Collect outstanding orders and their total token amount.
        IERC20PaymentClientBase_v1.PaymentOrder[] memory orders;

        (orders,,) = client_.collectPaymentOrders();

        uint orderLength = orders.length;
        for (uint i; i < orderLength; ++i) {
            // Add order to order queue
            _addPaymentOrderToQueue(orders[i], address(client_));
        }
        // Execute Order Queue.
        _executePaymentQueue(address(client_));
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
        address client_,
        address token_,
        address paymentReceiver_
    ) public view returns (uint amount_) {
        amount_ =
            _unclaimableAmountsForRecipient[client_][token_][paymentReceiver_];
    }

    /// @inheritdoc IPaymentProcessor_v1
    function claimPreviouslyUnclaimable(
        address client_,
        address token_,
        address receiver_
    ) external {
        if (unclaimable(client_, token_, receiver_) == 0) {
            revert Module__PaymentProcessor__NothingToClaim(client_, receiver_);
        }

        _claimPreviouslyUnclaimable(client_, token_, receiver_);
    }

    /// @inheritdoc IPaymentProcessor_v1
    function validPaymentOrder(
        IERC20PaymentClientBase_v1.PaymentOrder memory order_
    ) external view returns (bool isValid_) {
        return _validPaymentOrder(order_);
    }

    /// @inheritdoc IPP_Queue_v1
    function cancelPaymentOrderThroughQueueId(
        uint orderId_,
        IERC20PaymentClientBase_v1 client_
    ) external onlyModuleRole(QUEUE_OPERATOR_ROLE) returns (bool success_) {
        // Validate queue ID.
        if (!_orderExists(orderId_, client_)) {
            revert Module__PP_Queue_InvalidOrderId(address(client_), orderId_);
        }

        QueuedOrder storage order = _orders[orderId_];

        // Check if the order has an invalid state.
        if (order.state_ != RedemptionState.PENDING) {
            revert Module__PP_Queue_InvalidState();
        }

        // Update order state and emit event.
        _updateOrderState(orderId_, RedemptionState.CANCELLED);

        // Add amount to unclaimable.
        _addToUnclaimableAmount(
            _msgSender(),
            order.order_.paymentToken,
            order.order_.recipient,
            order.order_.amount
        );

        // Remove from queue if present.
        _removeFromQueue(orderId_);

        success_ = true;
    }

    // -------------------------------------------------------------------------
    // Internal Functions

    ///	@notice	Processes the next payment order in the queue.
    ///	@return	success_ True if a payment was processed.
    function _processNextOrder(address client_)
        internal
        clientIsValid(client_)
        returns (bool success_)
    {
        uint firstId = _queue[client_].getNextId(LinkedIdList._SENTINEL);
        if (firstId == LinkedIdList._SENTINEL) {
            return false;
        }

        QueuedOrder storage order = _orders[firstId];

        // Skip if order is not in PENDING state.
        if (order.state_ != RedemptionState.PENDING) {
            _removeFromQueue(firstId);
            return false;
        }

        // Check token balance and allowance.
        if (
            !_validTokenBalance(
                order.order_.paymentToken, order.client_, order.order_.amount
            )
        ) {
            return false;
        }

        return _executePaymentTransfer(firstId, order);
    }

    /// @notice	Executes the actual payment transfer for an order.
    /// @param	orderId_ The ID of the order to process.
    /// @param	order_ The order to process.
    /// @return	success_ True if the payment was successful.
    function _executePaymentTransfer(uint orderId_, QueuedOrder storage order_)
        internal
        returns (bool success_)
    {
        // Process payment.
        (bool success, bytes memory data) = order_.order_.paymentToken.call(
            abi.encodeWithSelector(
                IERC20(order_.order_.paymentToken).transferFrom.selector,
                order_.client_,
                order_.order_.recipient,
                order_.order_.amount
            )
        );

        // If transfer was successful.
        if (
            success && (data.length == 0 || abi.decode(data, (bool)))
                && order_.order_.paymentToken.code.length != 0
        ) {
            _updateOrderState(orderId_, RedemptionState.PROCESSED);
            _removeFromQueue(orderId_);

            // Notify client about successful payment.
            IERC20PaymentClientBase_v1(order_.client_).amountPaid(
                order_.order_.paymentToken, order_.order_.amount
            );

            emit TokensReleased(
                order_.order_.recipient,
                order_.order_.paymentToken,
                order_.order_.amount
            );

            return true;
        } else {
            // Process payment.
            (bool success, bytes memory data) = order_.order_.paymentToken.call(
                abi.encodeWithSelector(
                    IERC20(order_.order_.paymentToken).transferFrom.selector,
                    order_.client_,
                    address(this),
                    order_.order_.amount
                )
            );
            if (!success) {
                revert Module_PP_Queue_PaymentFailed(
                    order_.client_,
                    order_.order_.recipient,
                    order_.order_.paymentToken,
                    order_.order_.amount
                );
            }
            // Notify client about successful payment.
            IERC20PaymentClientBase_v1(order_.client_).amountPaid(
                order_.order_.paymentToken, order_.order_.amount
            );
            // Store as unclaimable and update state.
            _unclaimableAmountsForRecipient[order_.client_][order_
                .order_
                .paymentToken][order_.order_.recipient] += order_.order_.amount;

            emit UnclaimableAmountAdded(
                order_.client_,
                order_.order_.paymentToken,
                order_.order_.recipient,
                order_.order_.amount
            );

            _updateOrderState(orderId_, RedemptionState.FAILED);
            _removeFromQueue(orderId_);

            return false;
        }
    }
    // @todo add a way for the admin to re-direct unclaimable amounts from blacklisted recipients to himself

    /// @notice	Executes all pending orders in the queue.
    function _executePaymentQueue(address client_)
        internal
        clientIsValid(client_)
    {
        uint firstId = _queue[client_].getNextId(LinkedIdList._SENTINEL);
        if (firstId == LinkedIdList._SENTINEL) {
            revert Module__PP_Queue_EmptyQueue();
        }

        uint processedCount;
        while (firstId != LinkedIdList._SENTINEL && _processNextOrder(client_))
        {
            ++processedCount;
            firstId = _queue[client_].getNextId(LinkedIdList._SENTINEL);
        }

        emit PaymentQueueExecuted(_msgSender(), client_, processedCount);
    }

    /// @notice	Adds a payment order to the queue.
    /// @param	order_ The payment order to add.
    /// @param  client_ The client paying for the order.
    /// @return	queueId_ The ID of the added order.
    function _addPaymentOrderToQueue(
        IERC20PaymentClientBase_v1.PaymentOrder memory order_,
        address client_
    ) internal returns (uint queueId_) {
        if (!_validPaymentOrder(order_)) {
            revert Module__PP_Queue_QueueOperationFailed(client_);
        }

        // Get queue ID from flags and data, or generate new one
        queueId_ = _getPaymentQueueId(order_.flags, order_.data);

        // Create new order
        _orders[queueId_] = QueuedOrder({
            order_: order_,
            state_: RedemptionState.PENDING,
            orderId_: queueId_,
            timestamp_: block.timestamp,
            client_: client_
        });

        // Initialize the queue if it's the first order
        if (_queue[client_].length() == 0) {
            _queue[client_].init();
        }

        // Add to linked list
        _queue[client_].addId(queueId_);

        // Update current order ID
        _currentOrderId[client_] = queueId_;

        emit PaymentOrderQueued(
            queueId_,
            order_.recipient,
            order_.paymentToken,
            client_,
            order_.amount,
            uint(order_.flags)
        );
    }

    /// @notice	Removes an order from the queue.
    /// @param	orderId_ ID of the order to remove.
    function _removeFromQueue(uint orderId_) internal {
        address client_ = _orders[orderId_].client_;
        uint prevId = _queue[client_].getPreviousId(orderId_);
        _queue[client_].removeId(prevId, orderId_);
    }

    /// @notice Validates token balance and allowance for a payment.
    /// @param  token_ Token to check.
    /// @param  client_ Client address.
    /// @param  amount_ Amount to check.
    /// @return valid_ True if balance and allowance are sufficient.
    function _validTokenBalance(address token_, address client_, uint amount_)
        internal
        view
        returns (bool valid_)
    {
        IERC20 token = IERC20(token_);
        return token.balanceOf(client_) >= amount_
            && token.allowance(client_, address(this)) >= amount_;
    }

    /// @notice	Used to claim the unclaimable amount of a particular
    ///         paymentReceiver for a given payment client.
    /// @param	client_ Address of the payment client.
    /// @param	token_ Address of the payment token.
    /// @param	paymentReceiver_ Address of the paymentReceiver for which
    ///         the unclaimable amount will be claimed.
    function _claimPreviouslyUnclaimable(
        address client_,
        address token_,
        address paymentReceiver_
    ) internal {
        // Copy value over.
        uint amount =
            _unclaimableAmountsForRecipient[client_][token_][paymentReceiver_];
        // Delete the field.
        delete _unclaimableAmountsForRecipient[client_][token_][paymentReceiver_];

        // Call has to succeed otherwise no state change.
        IERC20(token_).safeTransferFrom(address(this), paymentReceiver_, amount);

        emit TokensReleased(paymentReceiver_, address(token_), amount);
    }

    /// @notice Validates if a queue ID is valid.
    /// @dev    Queue ID must equal to the current order ID + 1 for the client
    ///         and greater than 0 (we start from 1).
    /// @param  queueId_ The queue ID to validate.
    /// @param  client_ The payment client address.
    /// @return isValid_ Returns true if the queue ID is valid.
    function _validQueueId(uint queueId_, address client_)
        internal
        view
        returns (bool isValid_)
    {
        // Queue ID must equal to the current order ID + 1 for the client
        // and greater than 0 (we start from 1).
        return queueId_ > 0 && queueId_ == _currentOrderId[client_] + 1;
    }

    /// @notice Gets payment queue ID from flags and data.
    /// @param  flags_ The payment order flags.
    /// @param  data_ Additional payment order data.
    /// @return queueId_ The queue ID from the data or a newly generated one.
    function _getPaymentQueueId(bytes32 flags_, bytes32[] memory data_)
        internal
        view
        returns (uint queueId_)
    {
        // Check if orderID flag is set (bit 0)
        bool hasOrderId = uint(flags_) & (1 << FLAG_ORDER_ID) != 0;

        // If flag is set and data is provided, use that ID
        if (hasOrderId && data_.length > FLAG_ORDER_ID) {
            queueId_ = uint(data_[FLAG_ORDER_ID]);
        }
    }

    /// @notice Validate total input amount.
    /// @dev    Amount must be greater than 0.
    /// @param  amount_ Amount to validate.
    /// @return valid_ True if uint is valid.
    function _validTotalAmount(uint amount_)
        internal
        pure
        returns (bool valid_)
    {
        return amount_ != 0;
    }

    /// @notice Validate whether the address is a valid payment receiver.
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

    /// @notice Validates the chain ID.
    /// @dev    The chain ID must match the current chain ID.
    /// @param  chainId_ The chain ID to validate.
    /// @return valid_ True if the chain ID matches the current chain ID.
    function _validChainId(uint chainId_) internal view returns (bool valid_) {
        return chainId_ == block.chainid;
    }

    /// @notice Validates the payment token.
    /// @param  token_ Token address to validate.
    /// @return valid_ True if token is valid.
    function _validPaymentToken(address token_)
        internal
        view
        returns (bool valid_)
    {
        if (token_ == address(0)) {
            return false;
        }

        // Try to call balanceOf to verify it's an ERC20
        try IERC20(token_).balanceOf(address(this)) returns (uint) {
            return true;
        } catch {
            return false;
        }
    }

    /// @notice Validates a payment order.
    /// @param  order_ The order to validate.
    /// @return valid_ True if the order is valid.
    function _validPaymentOrder(
        IERC20PaymentClientBase_v1.PaymentOrder memory order_
    ) internal view returns (bool valid_) {
        // Extract queue ID from order data.
        uint queueId_ = _getPaymentQueueId(order_.flags, order_.data);

        // Validate payment receiver, amount and queue ID.
        return _validPaymentReceiver(order_.recipient)
            && _validTotalAmount(order_.amount)
            && _validQueueId(queueId_, address(msg.sender))
            && _validPaymentToken(order_.paymentToken)
            && _validChainId(order_.originChainId)
            && _validChainId(order_.targetChainId)
            && _validateFlagsAndData(order_.flags, order_.data);
    }

    /// @notice Validates a state transition.
    /// @param  orderId_ ID of the order.
    /// @param  currentState_ Current state of the order.
    /// @param  newState_ New state to transition to.
    /// @return valid_ True if the transition is valid.
    function _validStateTransition(
        uint orderId_,
        RedemptionState currentState_,
        RedemptionState newState_
    ) internal pure returns (bool valid_) {
        // Can't transition from completed or cancelled.
        if (
            currentState_ == RedemptionState.PROCESSED
                || currentState_ == RedemptionState.CANCELLED
        ) {
            revert Module__PP_Queue_InvalidStateTransition(
                orderId_, currentState_, newState_
            );
        }

        // Can only transition to completed or cancelled from processing.
        if (
            newState_ == RedemptionState.PROCESSED
                || newState_ == RedemptionState.CANCELLED
        ) {
            if (currentState_ != RedemptionState.PENDING) {
                revert Module__PP_Queue_InvalidStateTransition(
                    orderId_, currentState_, newState_
                );
            }
        }

        return true;
    }

    /// @notice Updates the state of a payment order.
    /// @param  orderId_ ID of the order to update.
    /// @param  state_ New state of the order.
    function _updateOrderState(uint orderId_, RedemptionState state_)
        internal
    {
        QueuedOrder storage order = _orders[orderId_];
        _validStateTransition(orderId_, order.state_, state_);
        order.state_ = state_;
        emit PaymentOrderStateChanged(
            orderId_, state_, order.client_, _msgSender()
        );
    }

    /// @notice Validates flags and corresponding data array.
    /// @param  flags_ The flags to validate.
    /// @param  data_ The data array to validate.
    function _validateFlagsAndData(bytes32 flags_, bytes32[] memory data_)
        internal
        pure
        returns (bool valid_)
    {
        uint flagsValue = uint(flags_);
        uint requiredDataLength = 0;

        // Count how many flags are set.
        for (uint8 i; i < 8; ++i) {
            if (flagsValue & (1 << i) != 0) {
                requiredDataLength++;
            }
        }

        return data_.length == requiredDataLength
            && (flagsValue & (1 << FLAG_ORDER_ID)) != 0;
    }

    /// @notice Internal function to check whether the client is valid.
    /// @param  client_ Address to validate.
    function _ensureValidClient(address client_) internal view {
        if (client_ == address(0)) {
            revert Module__PP_Queue_InvalidClientAddress(client_);
        }
        if (client_ != _msgSender()) {
            revert Module__PP_Queue_OnlyCallableByClient();
        }
    }

    /// @notice Adds to the unclaimable amount for a specific payment.
    /// @param  client_ The client address.
    /// @param  token_ The token address.
    /// @param  receiver_ The receiver address.
    /// @param  amount_ The amount to add.
    function _addToUnclaimableAmount(
        address client_,
        address token_,
        address receiver_,
        uint amount_
    ) internal {
        _unclaimableAmountsForRecipient[client_][token_][receiver_] += amount_;
    }

    /// @notice Checks if an order exists.
    /// @param  orderId_ ID of the order to check.
    /// @param  client_ Address of the client.
    /// @return exists_ True if the order exists.
    function _orderExists(uint orderId_, IERC20PaymentClientBase_v1 client_)
        internal
        view
        returns (bool exists_)
    {
        QueuedOrder storage order = _orders[orderId_];
        return order.client_ == address(client_) && order.timestamp_ != 0;
    }

    /// @dev    Gap for possible future upgrades.
    uint[50] private __gap;
}
