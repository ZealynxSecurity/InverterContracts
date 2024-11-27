// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import { IFundingManager_v1 } from "@fm/IFundingManager_v1.sol";
import { IERC20PaymentClientBase_v1 } from "@lm/interfaces/IERC20PaymentClientBase_v1.sol";
import { IRedeemingBondingCurveBase_v1 } from "@fm/bondingCurve/interfaces/IRedeemingBondingCurveBase_v1.sol";

/**
 * @title   Oracle Price Funding Manager Interface
 * @notice  Manages token operations using oracle-based pricing
 * @dev     Combines funding management and payment client capabilities
 * @custom:security-contact security@inverter.network
 * @author  Zealynx Security
 */
interface IFM_PC_ExternalPrice_Redeeming_v1 is 
    IFundingManager_v1, 
    IERC20PaymentClientBase_v1,
    IRedeemingBondingCurveBase_v1
{
    /// @notice Buys tokens with provided collateral
    /// @param collateralAmount_ The amount of collateral to spend
    function buy(uint256 collateralAmount_, uint256 minAmountOut_) external;

    /// @notice Sells tokens for collateral through redemption queue
    /// @param receiver_ Address to receive collateral
    /// @param depositAmount_ Amount of tokens to sell  
    /// @param minAmountOut_ Minimum collateral to receive
    function sell(
        address receiver_,
        uint256 depositAmount_,
        uint256 minAmountOut_
    ) external;

    /// @notice Calculates expected token return for collateral amount
    /// @param collateralAmount_ Amount of collateral to spend
    /// @return tokenAmount_ Expected amount of tokens to receive
    function calculateExpectedReturn(
        uint256 collateralAmount_
    ) external view returns (uint256);

    /// @notice Calculates expected collateral return for a given amount of USP tokens
    /// @param tokenAmount_ The amount of USP tokens to sell
    /// @return collateralAmount_ Expected amount of collateral to receive
    function calculateExpectedCollateralReturn(
        uint256 tokenAmount_
    ) external view returns (uint256);
}