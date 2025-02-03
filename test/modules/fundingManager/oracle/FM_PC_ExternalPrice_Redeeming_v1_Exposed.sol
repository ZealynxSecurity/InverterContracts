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

    // -------------------------------------------------------------------------
    // Helper function
}
