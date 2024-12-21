// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IPaymentProcessor_v1} from "@pp/IPaymentProcessor_v1.sol";
import {IERC20PaymentClientBase_v1} from
    "@lm/interfaces/IERC20PaymentClientBase_v1.sol";
import {IPP_Queue_v1} from "@pp/interfaces/IPP_Queue_v1.sol";
import {ERC165Upgradeable, Module_v1} from "src/modules/base/Module_v1.sol";
import {LinkedIdList} from "src/modules/lib/LinkedIdList.sol";

// External
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

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

    /// @dev    Role for queue operations.
    bytes32 public constant QUEUE_OPERATOR_ROLE = "QUEUE_OPERATOR";

    /// @dev    Flag positions in the flags byte.
    uint8 private constant FLAG_ORDER_ID = 0;
    uint8 private constant FLAG_START_TIME = 1;
    uint8 private constant FLAG_CLIFF_PERIOD = 2;
    uint8 private constant FLAG_END_TIME = 3;

    /// @dev    Timing skip reasons.
    uint8 private constant SKIP_NOT_STARTED = 1;
    uint8 private constant SKIP_IN_CLIFF = 2;
    uint8 private constant SKIP_EXPIRED = 3;

    // -------------------------------------------------------------------------
    // Storage

    /// @notice Maximum size of the queue.
    uint private _maxQueueSize;

    /// @notice Maximum lifetime of an order in seconds.
    uint private _maxOrderLifetime;

    /// @notice Queue of payment orders per client.
    mapping(address client => LinkedIdList.List queue) private _queue;

    /// @notice Tracks all payments that could not be made to the
    ///         paymentReceiver.
    /// @dev    client => token => receiver => unclaimable amount.
    mapping(
        address client
            => mapping(
                address token => mapping(address receiver => uint amount)
            )
    ) private _unclaimableAmountsForRecipient;

    /// @notice Tracks payment orders by their ID.
    /// @dev    orderId => order details.
    mapping(uint orderId => QueuedOrder order) private _orders;

    /// @dev    Next order ID to be assigned.
    uint private _nextOrderId;

    /// @dev    Gap for possible future upgrades.
    uint[50] private __gap;

    // -------------------------------------------------------------------------
    // Modifiers

    /// @dev    Checks that the client is calling for itself.
    modifier clientIsValid(address client_) {
        _ensureValidClient(client_);
        _;
    }

    // -------------------------------------------------------------------------
    // Initialize

    /// @inheritdoc Module_v1
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata_,
        bytes memory configData_
    ) external override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata_);

        (uint maxQueueSize_, uint maxOrderLifetime_) =
            abi.decode(configData_, (uint, uint));

        if (maxQueueSize_ == 0) revert Module__PP_Queue_InvalidConfig();
        if (maxOrderLifetime_ == 0) revert Module__PP_Queue_InvalidConfig();

        _maxQueueSize = maxQueueSize_;
        _maxOrderLifetime = maxOrderLifetime_;
    }

    //--------------------------------------------------------------------------
    // Public (Getters)

    /// @inheritdoc IPP_Queue_v1
    function getOrder(uint orderId_)
        external
        view
        returns (QueuedOrder memory order_)
    {
        if (!_orderExists(orderId_)) {
            revert Module__PP_Queue_InvalidOrderId(
                _orders[orderId_].client, orderId_
            );
        }
        order_ = _orders[orderId_];
    }

    /// @inheritdoc IPP_Queue_v1
    function getOrderQueue(address client_)
        external
        view
        returns (uint[] memory queue_)
    {
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
        head_ = _queue[client_].getNextId(LinkedIdList._SENTINEL);
    }

    /// @inheritdoc IPP_Queue_v1
    function getQueueTail(address client_) external view returns (uint tail_) {
        tail_ = _queue[client_].lastId();
    }

    /// @inheritdoc IPP_Queue_v1
    function getQueueSize(address client_)
        external
        view
        returns (uint size_, uint maxSize_)
    {
        size_ = _queue[client_].length();
        maxSize_ = _maxQueueSize;
    }

    /// @inheritdoc IPP_Queue_v1
    function getTotalOrders() external view returns (uint total_) {
        total_ = _nextOrderId;
    }

    /// @notice Gets the maximum size of the queue.
    /// @return maxSize_ Maximum queue size.
    function getMaxQueueSize() external view returns (uint maxSize_) {
        maxSize_ = _maxQueueSize;
    }

    /// @notice Gets the maximum lifetime of an order.
    /// @return maxLifetime_ Maximum order lifetime in seconds.
    function getMaxOrderLifetime() external view returns (uint maxLifetime_) {
        maxLifetime_ = _maxOrderLifetime;
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
    function unclaimable(address client, address token, address paymentReceiver)
        public
        view
        returns (uint amount_)
    {
        amount_ =
            _unclaimableAmountsForRecipient[client][token][paymentReceiver];
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
        // Extract queue ID from order data.
        (uint queueId_,,,) = _getPaymentQueueDetails(order_.flags, order_.data);

        // Validate payment receiver, amount and queue ID.
        isValid_ = _validPaymentReceiver(order_.recipient)
            && _validTotal(order_.amount) && _validQueueId(queueId_);
    }

    /// @inheritdoc IPP_Queue_v1
    function addPaymentOrderToQueue(
        address client_,
        address token_,
        address receiver_,
        uint amount_,
        bytes calldata data_
    ) external onlyModuleRole(QUEUE_OPERATOR_ROLE) returns (uint orderId_) {
        bytes32[] memory decodedData = new bytes32[](data_.length / 32);
        assembly {
            calldatacopy(
                add(decodedData, 32),
                add(data_.offset, 32),
                mul(mload(decodedData), 32)
            )
        }

        // Check token balance and allowance.
        if (!_validTokenBalance(token_, client_, amount_)) {
            revert Module__PP_Queue_QueueOperationFailed(client_);
        }

        // Create payment order.
        IERC20PaymentClientBase_v1.PaymentOrder memory order =
        IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: receiver_,
            paymentToken: token_,
            amount: amount_,
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: 0,
            data: decodedData
        });

        // Add to queue.
        orderId_ = _addPaymentOrderToQueue(order, client_);
    }

    /// @inheritdoc IPP_Queue_v1
    function cancelPaymentOrderThroughQueueId(uint orderId_)
        external
        onlyModuleRole(QUEUE_OPERATOR_ROLE)
        returns (bool success_)
    {
        // Validate queue ID.
        if (!_orderExists(orderId_)) {
            revert Module__PP_Queue_InvalidOrderId(
                _orders[orderId_].client, orderId_
            );
        }

        QueuedOrder storage order = _orders[orderId_];

        // Check if order can be cancelled
        if (order.state != RedemptionState.PROCESSING) {
            revert Module__PP_Queue_InvalidState();
        }

        // Update order state and emit event
        _updateOrderState(orderId_, RedemptionState.CANCELLED);

        // Add amount to unclaimable
        _setUnclaimableAmount(
            _msgSender(),
            order.order.paymentToken,
            order.order.recipient,
            order.order.amount
        );

        // Remove from queue if present
        _removeFromQueue(orderId_);

        success_ = true;
    }

    /// @inheritdoc IPP_Queue_v1
    function processNextOrder(address client_)
        external
        onlyModuleRole(QUEUE_OPERATOR_ROLE)
        returns (bool success_)
    {
        success_ = _processNextOrder(client_);
    }

    // -------------------------------------------------------------------------
    // Internal

    ///	@notice	Processes the next payment order in the queue.
    ///	@return	success_ True if a payment was processed.
    function _processNextOrder(address client_)
        internal
        returns (bool success_)
    {
        _ensureValidClient(client_);
        uint firstId = _queue[client_].getNextId(LinkedIdList._SENTINEL);
        if (firstId == LinkedIdList._SENTINEL) {
            return false;
        }

        QueuedOrder storage order = _orders[firstId];

        // Skip if order is not in PROCESSING state.
        if (order.state != RedemptionState.PROCESSING) {
            _removeFromQueue(firstId);
            return false;
        }

        // Extract timing parameters.
        (
            , // queueId not needed here.
            uint startTime,
            uint cliffPeriod,
            uint endTime
        ) = _getPaymentQueueDetails(order.order.flags, order.order.data);

        // Check timing constraints
        if (!_validPaymentTiming(firstId, startTime, cliffPeriod, endTime)) {
            return false;
        }

        // Check token balance and allowance.
        if (
            !_validTokenBalance(
                order.order.paymentToken, order.client, order.order.amount
            )
        ) {
            _updateOrderState(firstId, RedemptionState.CANCELLED);
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
        (bool success, bytes memory data) = order_.order.paymentToken.call(
            abi.encodeWithSelector(
                IERC20(order_.order.paymentToken).transferFrom.selector,
                order_.client,
                order_.order.recipient,
                order_.order.amount
            )
        );

        // If transfer was successful.
        if (
            success && (data.length == 0 || abi.decode(data, (bool)))
                && order_.order.paymentToken.code.length != 0
        ) {
            _updateOrderState(orderId_, RedemptionState.COMPLETED);
            _removeFromQueue(orderId_);

            // Notify client about successful payment.
            IERC20PaymentClientBase_v1(order_.client).amountPaid(
                order_.order.paymentToken, order_.order.amount
            );

            emit TokensReleased(
                order_.order.recipient,
                order_.order.paymentToken,
                order_.order.amount
            );

            return true;
        } else {
            // Store as unclaimable and update state.
            _unclaimableAmountsForRecipient[order_.client][order_
                .order
                .paymentToken][order_.order.recipient] += order_.order.amount;

            emit UnclaimableAmountAdded(
                order_.client,
                order_.order.paymentToken,
                order_.order.recipient,
                order_.order.amount
            );

            _updateOrderState(orderId_, RedemptionState.CANCELLED);
            _removeFromQueue(orderId_);

            return false;
        }
    }

    /// @notice	Executes all pending orders in the queue.
    function _executePaymentQueue(address client_) internal {
        _ensureValidClient(client_);
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
    /// @return	orderId_ The ID of the added order.
    function _addPaymentOrderToQueue(
        IERC20PaymentClientBase_v1.PaymentOrder memory order_,
        address client_
    ) internal returns (uint orderId_) {
        _ensureValidClient(client_);
        // Check queue size
        if (_queue[client_].length() >= _maxQueueSize) {
            revert Module__PP_Queue_QueueOperationFailed(client_);
        }

        // Create new order
        orderId_ = _nextOrderId++;
        _orders[orderId_] = QueuedOrder({
            order: order_,
            state: RedemptionState.PROCESSING,
            orderId: orderId_,
            timestamp: block.timestamp,
            client: client_
        });

        // Add to linked list
        _queue[client_].addId(orderId_);

        emit PaymentOrderQueued(
            orderId_,
            order_.recipient,
            client_,
            order_.paymentToken,
            order_.amount,
            uint(order_.flags),
            block.timestamp
        );
    }

    /// @notice	Removes an order from the queue.
    /// @param	orderId_ ID of the order to remove.
    function _removeFromQueue(uint orderId_) internal {
        require(orderId_ != 0, "Invalid order ID.");
        address client_ = _orders[orderId_].client;
        uint prevId = _queue[client_].getPreviousId(orderId_);
        _queue[client_].removeId(prevId, orderId_);
    }

    /// @dev    Validates token balance and allowance for a payment.
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
    /// paymentReceiver for a given payment client.
    /// @param	client Address of the payment client.
    /// @param	token Address of the payment token.
    /// @param	paymentReceiver Address of the paymentReceiver for which
    /// the unclaimable amount will be claimed.
    function _claimPreviouslyUnclaimable(
        address client,
        address token,
        address paymentReceiver
    ) internal {
        // Copy value over.
        uint amount =
            _unclaimableAmountsForRecipient[client][token][_msgSender()];
        // Delete the field.
        delete _unclaimableAmountsForRecipient[client][token][_msgSender()];

        // Make sure to let paymentClient know that amount doesnt have
        // to be stored anymore.
        IERC20PaymentClientBase_v1(client).amountPaid(token, amount);

        // Call has to succeed otherwise no state change.
        IERC20(token).safeTransferFrom(client, paymentReceiver, amount);

        emit TokensReleased(paymentReceiver, address(token), amount);
    }

    /// @dev    Validates if a queue ID is valid.
    /// @param  queueId_ The queue ID to validate.
    /// @return isValid_ True if the queue ID is valid.
    function _validQueueId(uint queueId_)
        internal
        view
        returns (bool isValid_)
    {
        // Queue ID must be less than or equal to total orders
        // and greater than 0 (we start from 1).
        return queueId_ > 0 && queueId_ <= _nextOrderId;
    }

    /// @dev    Gets payment queue details from flags and data.
    /// @param  flags_ The payment order flags.
    /// @param  data_ Additional payment order data.
    /// @return queueId_ The queue ID from the data.
    /// @return startTime_ Start time if specified.
    /// @return cliffPeriod_ Cliff period if specified.
    /// @return endTime_ End time if specified.
    function _getPaymentQueueDetails(bytes32 flags_, bytes32[] memory data_)
        internal
        pure
        returns (
            uint queueId_,
            uint startTime_,
            uint cliffPeriod_,
            uint endTime_
        )
    {
        uint dataIndex = 0;

        // Check if orderID flag is set (bit 0)
        if (uint(flags_) & (1 << FLAG_ORDER_ID) != 0) {
            if (dataIndex < data_.length) {
                queueId_ = uint(data_[dataIndex++]);
            }
        }

        // Check if start time flag is set (bit 1)
        if (uint(flags_) & (1 << FLAG_START_TIME) != 0) {
            if (dataIndex < data_.length) {
                startTime_ = uint(data_[dataIndex++]);
            }
        }

        // Check if cliff period flag is set (bit 2)
        if (uint(flags_) & (1 << FLAG_CLIFF_PERIOD) != 0) {
            if (dataIndex < data_.length) {
                cliffPeriod_ = uint(data_[dataIndex++]);
            }
        }

        // Check if end time flag is set (bit 3)
        if (uint(flags_) & (1 << FLAG_END_TIME) != 0) {
            if (dataIndex < data_.length) {
                endTime_ = uint(data_[dataIndex]);
            }
        }
    }

    /// @dev    Validates if a payment order can be processed based on
    /// its timing constraints.
    /// @param  orderId_ ID of the order being validated.
    /// @param  startTime_ Start time of the order.
    /// @param  cliffPeriod_ Cliff period of the order.
    /// @param  endTime_ End time of the order.
    /// @return valid_ True if the order can be processed.
    function _validPaymentTiming(
        uint orderId_,
        uint startTime_,
        uint cliffPeriod_,
        uint endTime_
    ) internal returns (bool valid_) {
        uint currentTime = block.timestamp;

        // If no timing constraints (all zeros), order is valid.
        if (startTime_ == 0 && cliffPeriod_ == 0 && endTime_ == 0) {
            return true;
        }

        uint cliffEnd = startTime_ + cliffPeriod_;

        // Check if order has started.
        if (startTime_ > 0 && currentTime < startTime_) {
            emit PaymentOrderTimingSkip(
                orderId_,
                _orders[orderId_].client,
                SKIP_NOT_STARTED,
                currentTime,
                startTime_,
                cliffEnd,
                endTime_
            );
            return false;
        }

        // Check if cliff period has passed.
        if (cliffPeriod_ > 0 && currentTime < cliffEnd) {
            emit PaymentOrderTimingSkip(
                orderId_,
                _orders[orderId_].client,
                SKIP_IN_CLIFF,
                currentTime,
                startTime_,
                cliffEnd,
                endTime_
            );
            return false;
        }

        // Check if order hasn't expired.
        if (endTime_ > 0 && currentTime > endTime_) {
            emit PaymentOrderTimingSkip(
                orderId_,
                _orders[orderId_].client,
                SKIP_EXPIRED,
                currentTime,
                startTime_,
                cliffEnd,
                endTime_
            );
            return false;
        }

        return true;
    }

    /// @dev    Validate uint total amount input.
    /// @param  amount_ Amount to validate.
    /// @return valid_ True if uint is valid.
    function _validTotal(uint amount_) internal pure returns (bool valid_) {
        return amount_ != 0;
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

    /// @dev    Validates a payment token.
    /// @param  token_ Token address to validate.
    /// @return valid_ True if token is valid.
    function _validPaymentToken(address token_)
        internal
        view
        returns (bool valid_)
    {
        if (token_ == address(0)) {
            revert Module__PP_Queue_InvalidToken(token_);
        }

        // Try to call balanceOf to verify it's an ERC20
        try IERC20(token_).balanceOf(address(this)) returns (uint) {
            return true;
        } catch {
            revert Module__PP_Queue_InvalidTokenImplementation(token_);
        }
    }

    /// @dev    Validates a payment order.
    /// @param  order_ The order to validate.
    /// @return valid_ True if the order is valid.
    function _validPaymentOrder(QueuedOrder memory order_)
        internal
        view
        returns (bool valid_)
    {
        // Validate recipient
        if (!_validPaymentReceiver(order_.order.recipient)) {
            revert Module__PP_Queue_InvalidRecipient(order_.order.recipient);
        }

        // Validate payment token
        if (!_validPaymentToken(order_.order.paymentToken)) {
            revert Module__PP_Queue_InvalidToken(order_.order.paymentToken);
        }

        // Validate amount
        if (!_validTotal(order_.order.amount)) {
            revert Module__PP_Queue_InvalidAmount(order_.order.amount);
        }

        // Validate chain IDs
        if (
            order_.order.originChainId != block.chainid
                || order_.order.targetChainId != block.chainid
        ) {
            revert Module__PP_Queue_InvalidChainId(
                order_.order.originChainId,
                order_.order.targetChainId,
                block.chainid
            );
        }

        // Validate flags and data consistency
        _validateFlagsAndData(order_.order.flags, order_.order.data);

        return true;
    }

    /// @dev    Validates a state transition.
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
            currentState_ == RedemptionState.COMPLETED
                || currentState_ == RedemptionState.CANCELLED
        ) {
            revert Module__PP_Queue_InvalidStateTransition(
                orderId_, currentState_, newState_
            );
        }

        // Can only transition to completed or cancelled from processing.
        if (
            newState_ == RedemptionState.COMPLETED
                || newState_ == RedemptionState.CANCELLED
        ) {
            if (currentState_ != RedemptionState.PROCESSING) {
                revert Module__PP_Queue_InvalidStateTransition(
                    orderId_, currentState_, newState_
                );
            }
        }

        return true;
    }

    /// @dev    Updates the state of a payment order.
    /// @param  orderId_ ID of the order to update.
    /// @param  state_ New state of the order.
    function _updateOrderState(uint orderId_, RedemptionState state_)
        internal
    {
        QueuedOrder storage order = _orders[orderId_];
        _validStateTransition(orderId_, order.state, state_);
        order.state = state_;
        emit PaymentOrderStateChanged(orderId_, state_, order.client);
    }

    /// @dev    Validates flags and corresponding data array.
    /// @param  flags_ The flags to validate.
    /// @param  data_ The data array to validate.
    function _validateFlagsAndData(bytes32 flags_, bytes32[] memory data_)
        internal
        view
    {
        uint flagsValue = uint(flags_);
        uint requiredDataLength = 0;

        // Count how many flags are set.
        for (uint8 i; i < 8; ++i) {
            if (flagsValue & (1 << i) != 0) {
                requiredDataLength++;
            }
        }

        // Verify data array length matches number of set flags.
        if (data_.length < requiredDataLength) {
            revert Module__PP_Queue_InvalidFlagsOrData(flags_, data_.length);
        }

        // Validate each flag's data based on type.
        uint dataIndex = 0;

        // Check orderID flag (bit 0).
        if (flagsValue & (1 << FLAG_ORDER_ID) != 0) {
            // orderID must be non-zero.
            if (uint(data_[dataIndex++]) == 0) {
                revert Module__PP_Queue_InvalidFlagsOrData(flags_, data_.length);
            }
        }

        // Check start time flag (bit 1).
        if (flagsValue & (1 << FLAG_START_TIME) != 0) {
            // start time must be in the future or 0.
            uint startTime = uint(data_[dataIndex++]);
            if (startTime != 0 && startTime < block.timestamp) {
                revert Module__PP_Queue_InvalidFlagsOrData(flags_, data_.length);
            }
        }

        // Check cliff period flag (bit 2).
        if (flagsValue & (1 << FLAG_CLIFF_PERIOD) != 0) {
            dataIndex++; // cliff period can be any value.
        }

        // Check end time flag (bit 3).
        if (flagsValue & (1 << FLAG_END_TIME) != 0) {
            // end time must be after start time if both are specified.
            if (flagsValue & (1 << FLAG_START_TIME) != 0) {
                uint endTime = uint(data_[dataIndex]);
                // start time is second element if present.
                uint startTime = uint(data_[1]);
                if (endTime <= startTime) {
                    revert Module__PP_Queue_InvalidFlagsOrData(
                        flags_, data_.length
                    );
                }
            }
        }
    }

    /// @dev    Internal function to check whether the client is valid.
    /// @param  client_ Address to validate.
    function _ensureValidClient(address client_) internal view {
        if (client_ == address(0)) {
            revert Module__PP_Queue_InvalidClientAddress(client_);
        }
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
        uint amount_
    ) internal {
        _unclaimableAmountsForRecipient[client_][token_][receiver_] = amount_;
    }

    /// @dev    Checks if an order exists.
    /// @param  orderId_ ID of the order to check.
    /// @return exists_ True if the order exists.
    function _orderExists(uint orderId_) internal view returns (bool exists_) {
        return orderId_ < _nextOrderId;
    }
}
