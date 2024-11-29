// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

//--------------------------------------------------------------------------
// Imports

// Internal
import { IFundingManager_v1 } from "@fm/IFundingManager_v1.sol";
import { IRedeemingBondingCurveBase_v1 } from "@fm/bondingCurve/interfaces/IRedeemingBondingCurveBase_v1.sol";

// External
import { IERC20PaymentClientBase_v1 } from "@lm/interfaces/IERC20PaymentClientBase_v1.sol";

/**
 * @title   Oracle Price Funding Manager Interface
 *
 * @notice  Interface for a funding manager that utilizes oracle-based pricing for
 *          token operations, integrating payment client functionality and supporting
 *          redemption mechanisms through a queue system.
 *
 * @dev     This interface inherits from:
 *              - IFundingManager_v1
 *              - IERC20PaymentClientBase_v1
 *              - IRedeemingBondingCurveBase_v1
 *          Key operations:
 *              - Token buying with collateral
 *              - Token selling with queue position
 *          All operations must respect oracle prices and access control
 *          mechanisms defined in the implementation.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @author  Zealynx Security
 */
interface IFM_PC_Oracle_Redeeming_v1 is
    IFundingManager_v1,
    IERC20PaymentClientBase_v1,
    IRedeemingBondingCurveBase_v1
{
    //--------------------------------------------------------------------------
    // External Functions

    /// @notice Buys tokens with provided collateral amount
    /// @param collateralAmount Amount of collateral to spend
    /// @return tokenAmount Amount of tokens received
    function buy(uint256 collateralAmount) external returns (uint256 tokenAmount);

    /// @notice Sells tokens through the redemption queue
    /// @param tokenAmount Amount of tokens to sell
    /// @return queuePosition Position in the redemption queue
    function sell(uint256 tokenAmount) external returns (uint256 queuePosition);
}
