// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IPaymentProcessor_v1} from
    "src/modules/paymentProcessor/IPaymentProcessor_v1.sol";
import {IERC20PaymentClientBase_v1} from
    "@lm/interfaces/IERC20PaymentClientBase_v1.sol";
import {IPP_Queue_v1} from "@pp/interfaces/IPP_Queue_v1.sol";
import {IPP_Queue_ManualExecution_v1} from
    "@pp/interfaces/IPP_Queue_ManualExecution_v1.sol";
import {ERC165Upgradeable, Module_v1} from
    "src/modules/base/Module_v1.sol";
import {PP_Queue_v1} from "@pp/PP_Queue_v1.sol";

// External
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

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
contract PP_Queue_ManualExecution_v1 is
    IPP_Queue_ManualExecution_v1,
    PP_Queue_v1
{
    //--------------------------------------------------------------------------
    // ERC165

    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId_)
        public
        view
        virtual
        override(PP_Queue_v1)
        returns (bool)
    {
        return interfaceId_ == type(IPP_Queue_ManualExecution_v1).interfaceId
            || interfaceId_ == type(IPaymentProcessor_v1).interfaceId
            || super.supportsInterface(interfaceId_);
    }

    /// @dev    Gap for possible future upgrades.
    uint[50] private __gap;

    //--------------------------------------------------------------------------
    // Public (Getters)

    //--------------------------------------------------------------------------
    // Public (Mutating)

    /// @inheritdoc IPaymentProcessor_v1
    function processPayments(IERC20PaymentClientBase_v1 client_)
        external
        virtual
        override(PP_Queue_v1, IPaymentProcessor_v1)
        onlyModule
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
    }

    /// @inheritdoc IPP_Queue_ManualExecution_v1
    function executePaymentQueue() external onlyModuleRole(QUEUE_OPERATOR_ROLE) {
        _executePaymentQueue();
    }

    //--------------------------------------------------------------------------
    // Internal override
}
