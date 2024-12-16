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

// External
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

/**
 * @title   Inverter Queue Based Payment Processor
 *
 * @notice  Payment Processor which implements a payment queue.
 *
 * @dev     @todo add dev information once all the features have been defined
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
    //--------------------------------------------------------------------------
    // Libraries

    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------
    // ERC165

    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId_)
        public
        view
        virtual
        override(Module_v1)
        returns (bool)
    {
        return interfaceId_ == type(IPP_Queue_v1).interfaceId
            || interfaceId_ == type(IPaymentProcessor_v1).interfaceId
            || super.supportsInterface(interfaceId_);
    }

    //--------------------------------------------------------------------------
    // Constants

    bytes32 public constant QUEUE_MANAGER_ROLE = "QUEUE_MANAGER_ROLE";

    //--------------------------------------------------------------------------
    // State

    /// @dev    Tracks all payments that could not be made to the paymentReceiver due to any reason.
    /// @dev	paymentClient => token address => paymentReceiver => unclaimable Amount.
    mapping(address => mapping(address => mapping(address => uint))) internal
        unclaimableAmountsForRecipient;

    // @todo define storage type for the queue. One option could be to use the LinkedList
    // Library within the repo, in case you want to go that route

    /// @dev    Gap for possible future upgrades.
    uint[50] private __gap;

    //--------------------------------------------------------------------------
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

    //--------------------------------------------------------------------------
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
    function unclaimable(address client, address token, address paymentReceiver)
        public
        view
        returns (uint amount_)
    {
        return unclaimableAmountsForRecipient[client][token][paymentReceiver];
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
    ) external view returns (bool) {
        // This function is used to validate the payment order created on the
        // client side (in our case FM_PC_ManualExternal...) with the input required by the Payment Processor
        // (PP). The function should return true if the payment order is valid
        // and false if it is not.

        // @todo call about the new payment order struct
        (uint queueId, /* Something else? */ ) =
            _getPaymentQueueDetails(order_.flags, order_.data);

        // // @todo add calls to internal validation functions. Example can be seen in PP_Streaming -> validPaymentOrde() function
        return _validPaymentReceiver(order_.recipient)
            && _validTotal(order_.amount) && _validQueueId(queueId);
        return true;
    }

    function cancelPaymentOrderThroughQueueId(uint queueId_)
        external
        onlyModuleRole(QUEUE_MANAGER_ROLE)
    {
        // @todo remove the payment order from the queue. We also need to emit an event here with the
        // queue ID and the state CANCELLED so the indexer can pick it up
    }

    //--------------------------------------------------------------------------
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
        uint amount = unclaimableAmountsForRecipient[client][token][sender];
        // Delete the field
        delete unclaimableAmountsForRecipient[client][token][sender];

        // Make sure to let paymentClient know that amount doesnt have to be stored anymore
        IERC20PaymentClientBase_v1(client).amountPaid(token, amount);

        // Call has to succeed otherwise no state change
        IERC20(token).safeTransferFrom(client, paymentReceiver, amount);

        emit TokensReleased(paymentReceiver, address(token), amount);
    }

    function _addPaymentOrderToQueue(
        IERC20PaymentClientBase_v1.PaymentOrder memory order_
    ) internal {
        // @todo add payment order to payment order queue. First need to define
        // the right data type for the payment order queue, see todo tag at the state
        // variables
    }

    // @todo natspec
    function _executePaymentQueue() internal returns (bool queueCompleted_) {
        // @todo Not sure about the precies way to do this. Main point is that we go through
        // the queue and process all of the queue until the collateral in the PC is empty
        // The flow could look something like this
        // 1. go through each queue ID, first in first out
        // 3. try and catch to transfer the amount
        //      a. when tranfer successfull
        //          I. call to client to update amountPaid
        //          II. emit PaymentOrderProcessed event
        //          III. emit queue element processed event
        //          IV. delete the queue element
        //      b. when failed stop the execution of the redemption queue
        // 4. return true if the queue is completed, otherwise false

        // Note: we need to figure out how to handle previous unclaimable amounts
        return true;
    }
    // @todo natspec

    function _getPaymentQueueDetails(bytes32 flags, bytes32[] memory data)
        internal
        returns (uint)
    {
        // @todo Function which reads the data based on the flags defined. Needs to be discussed during call
        // as it involves the new payment order struct
        return 0;
    }

    // @todo natspec
    function _validQueueId(uint queueId) internal returns (bool) {
        // @todo Implement check that a created payment order has the correct queue ID
        // Update return value
        return true;
    }

    // @todo natspec
    function _validChainId(uint chainId_) internal returns (bool) {
        //@todo validate that chainId == chain ID of chain the contract is deployed on. This
        // PP does not have crosschain sending functionality
        return true;
    }

    /// @notice Validate uint total amount input.
    /// @param  _total uint to validate.
    /// @return True if uint is valid.
    function _validTotal(uint _total) internal pure returns (bool) {
        return !(_total == 0);
    }

    /// @dev    Validate whether the address is a valid payment receiver.
    /// @param  receiver_ Address to validate.
    /// @return validPaymentReceiver_ True if address is valid.
    function _validPaymentReceiver(address receiver_)
        internal
        view
        returns (bool)
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
        if (_msgSender() != client_) {
            revert Module__PP_Template__ClientNotValid();
        }
    }

    //--------------------------------------------------------------------------
    // Internal override
}
