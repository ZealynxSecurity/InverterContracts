// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import {FM_PC_ExternalPrice_Redeeming_v1} from
    "src/modules/fundingManager/oracle/FM_PC_ExternalPrice_Redeeming_v1.sol";

contract FM_PC_ExternalPrice_Redeeming_v1_Exposed is
    FM_PC_ExternalPrice_Redeeming_v1
{
    function exposed_setProjectTreasury(address projectTreasury_) public {
        _setProjectTreasury(projectTreasury_);
    }

    function exposed_deductFromOpenRedemptionAmount(uint amount_) public {
        _deductFromOpenRedemptionAmount(amount_);
    }

    function exposed_addToOpenRedemptionAmount(uint amount_) public {
        _addToOpenRedemptionAmount(amount_);
    }

    function exposed_setOracleAddress(address oracle_) public {
        _setOracleAddress(oracle_);
    }

    function exposed_setIssuanceToken(address issuanceToken_) public {
        _setIssuanceToken(issuanceToken_);
    }

    function exposed_handleIssuanceTokensAfterBuy(
        address recipient_,
        uint amount_
    ) public {
        _handleIssuanceTokensAfterBuy(recipient_, amount_);
    }

    function exposed_handleCollateralTokensBeforeBuy(
        address recipient_,
        uint amount_
    ) public {
        _handleCollateralTokensBeforeBuy(recipient_, amount_);
    }

    function exposed_setIsDirectOperationsOnly(bool isDirectional_) public {
        _setIsDirectOperationsOnly(isDirectional_);
    }

    function exposed_setMaxProjectBuyFee(uint fee_) public {
        _setMaxProjectBuyFee(fee_);
    }

    function exposed_setMaxProjectSellFee(uint fee_) public {
        _setMaxProjectSellFee(fee_);
    }

    function exposed_setBuyFee(uint fee_) public {
        _setBuyFee(fee_);
    }

    function exposed_setSellFee(uint fee_) public {
        _setSellFee(fee_);
    }

    function exposed_redeemTokensFormulaWrapper(uint amount_) public view returns (uint) {
        return _redeemTokensFormulaWrapper(amount_);
    }

    function exposed_issueTokensFormulaWrapper(uint amount_) public view returns (uint) {
        return _issueTokensFormulaWrapper(amount_);
    }

    function exposed_projectFeeCollected(uint amount_) public {
        _projectFeeCollected(amount_);
    }

    // -------------------------------------------------------------------------
    // Helper function
}
