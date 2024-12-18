// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal
import {IPP_Queue_v1} from "@pp/interfaces/IPP_Queue_v1.sol";

/**
 * @title   Manual Execution Queue Based Payment Processor
 *
 * @notice  A payment processor implementation that extends the base queue system
 *          with manual execution capabilities. This allows for controlled,
 *          manual processing of payment orders in the queue.
 *
 * @dev     This contract inherits from:
 *              - IPP_Queue_v1.
 *          Key features:
 *              - Manual payment execution.
 *              - Inherits FIFO queue management.
 *              - Inherits payment order lifecycle management.
 *          The contract implements manual payment processing through the
 *          executePaymentQueue function.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @custom:version  v1.0.0
 *
 * @custom:standard-version v1.0.0
 */
interface IPP_Queue_ManualExecution_v1 is IPP_Queue_v1 {
    // -------------------------------------------------------------------------
    // Events

    /**
     * @notice	Emitted when a payment queue is manually executed.
     * @dev	    This event is emitted after the successful execution of the
     *          payment queue.
     */
    event PaymentQueueExecuted();

    // -------------------------------------------------------------------------
    // Errors

    /**
     * @notice	Thrown when attempting to execute an empty payment queue.
     * @dev	    This error is thrown when executePaymentQueue is called on an
     *          empty queue.
     */
    error Module__PP_Queue_EmptyQueue();

    // -------------------------------------------------------------------------
    // Functions

    /**
     * @notice	Manually executes all pending payment orders in the queue.
     * @dev	    This function processes all pending orders in the queue. It
     *          requires the QUEUE_OPERATOR_ROLE.
     */
    function executePaymentQueue() external;
}
