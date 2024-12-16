// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

/**
 * @title   Inverter Manual Executed Queue Based Payment Processor
 *
 * @notice  Payment Processor which implements a payment queue which is manually executed
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
interface IPP_Queue_ManualExecution_v1 {
    //--------------------------------------------------------------------------
    // Functions

    // @todo add natspec
    function executePaymentOrderQueue() external;
}
