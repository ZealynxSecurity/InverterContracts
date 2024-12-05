// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import {LM_ManualExternalPriceSetter_v1} from "src/modules/fundingManager/oracle/LM_ManualExternalPriceSetter_v1.sol";
import {IOrchestrator_v1} from "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IAuthorizer_v1} from "@aut/IAuthorizer_v1.sol";

contract LM_ManualExternalPriceSetter_v1_Exposed is LM_ManualExternalPriceSetter_v1 {
    constructor() {}

    function exposed_normalizePrice(uint256 price_, uint8 tokenDecimals_) external pure returns (uint256) {
        return _normalizePrice(price_, tokenDecimals_);
    }

    function exposed_denormalizePrice(uint256 price_, uint8 tokenDecimals_) external pure returns (uint256) {
        return _denormalizePrice(price_, tokenDecimals_);
    }

    function exposed_authorizer() external view returns (IAuthorizer_v1) {
        return __Module_orchestrator.authorizer();
    }
}
