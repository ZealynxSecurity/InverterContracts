// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import {LM_ManualExternalPriceSetter_v1} from
    "src/modules/logicModule/LM_ManualExternalPriceSetter_v1.sol";
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IAuthorizer_v1} from "@aut/IAuthorizer_v1.sol";

contract LM_ManualExternalPriceSetter_v1_Exposed is
    LM_ManualExternalPriceSetter_v1
{
    constructor() {}
}
