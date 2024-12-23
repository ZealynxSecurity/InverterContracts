// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import {PP_Queue_v1} from "@pp/PP_Queue_v1.sol";
import {IERC20PaymentClientBase_v1} from "@lm/interfaces/IERC20PaymentClientBase_v1.sol";
import {IPP_Queue_v1} from "@pp/interfaces/IPP_Queue_v1.sol";

contract PP_Queue_v1Mock is PP_Queue_v1 {
    // Override _msgSender para evitar problemas de autorización
    function _msgSender() internal view virtual override returns (address) {
        return msg.sender;
    }

    function exposed_addPaymentOrderToQueue(
        IERC20PaymentClientBase_v1.PaymentOrder memory order_,
        address client_
    ) external returns (uint) {
        return _addPaymentOrderToQueue(order_, client_);
    }

    function exposed_removeFromQueue(uint orderId_) external {
        _removeFromQueue(orderId_);
    }
}
