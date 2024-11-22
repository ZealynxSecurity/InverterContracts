// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import { IFundingManager_v1 } from "@fm/IFundingManager_v1.sol";
import { IERC20PaymentClientBase_v1 } from "@lm/interfaces/IERC20PaymentClientBase_v1.sol";
import { IRedeemingBondingCurveBase_v1 } from "@fm/bondingCurve/interfaces/IRedeemingBondingCurveBase_v1.sol";

/**
 * @title   Oracle Price Funding Manager Interface
 * @notice  Manages token operations using oracle-based pricing
 * @dev     Combines funding management and payment client capabilities
 * @author  Zealynx Security
 */
interface IFM_PC_Oracle_Redeeming_v1 is
    IFundingManager_v1,
    IERC20PaymentClientBase_v1,
    IRedeemingBondingCurveBase_v1
{

    function buy(uint256 collateralAmount) external returns (uint256 tokenAmount);
    function sell(uint256 tokenAmount) external returns (uint256 queuePosition);
}
