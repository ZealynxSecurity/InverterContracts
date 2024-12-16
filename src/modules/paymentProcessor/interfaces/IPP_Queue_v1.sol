// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal
import {IPaymentProcessor_v1} from "@pp/IPaymentProcessor_v1.sol";

/**
 * @title   Inverter Queue Based Payment Processor
 *
 * @notice  Payment Processor which implements a payment queue.
 *
 * @dev     TODO
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
interface IPP_Queue_v1 is IPaymentProcessor_v1 {
    // -------------------------------------------------------------------------
    // Type Declarations

    // Enum for redemption order states
    enum RedemptionState {
        COMPLETED,
        CANCELLED,
        PROCESSING
    }

    //--------------------------------------------------------------------------
    // Structs

    //--------------------------------------------------------------------------
    // Events

    // @todo add event which is emitted when  Queue element is processed successfully.
    // It should emit the state COMPLETED, which will be picked up by the indexer and
    // displayed in the UI

    //--------------------------------------------------------------------------
    // Errors

    /// @notice Amount can not be zero.
    error Module__PP_Template_InvalidAmount();

    /// @notice Client is not valid.
    error Module__PP_Template__ClientNotValid();

    //--------------------------------------------------------------------------
    // Public (Getter)

    //--------------------------------------------------------------------------
    // Public (Mutating)

    // @todo natspec, also needs better name xD
    function cancelPaymentOrderThroughQueueId(uint queueId_) external;
}
