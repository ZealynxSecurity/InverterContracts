// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// SuT
import {AUT_Roles_v1} from "@aut/role/AUT_Roles_v1.sol";

// Internal Dependencies
import {
    E2ETest, IOrchestratorFactory_v1, IOrchestrator_v1
} from "test/e2e/E2ETest.sol";

// Import modules that are used in this E2E test
import {PP_Queue_v1Mock} from "test/utils/mocks/modules/paymentProcessor/PP_Queue_v1Mock.sol";
import {IPP_Queue_v1} from "@pp/interfaces/IPP_Queue_v1.sol";
import {PP_Queue_v1} from "@pp/PP_Queue_v1.sol";

import {LinkedIdList} from "src/modules/lib/LinkedIdList.sol";
//
import {FM_PC_ExternalPrice_Redeeming_v1} from "src/modules/fundingManager/oracle/FM_PC_ExternalPrice_Redeeming_v1.sol";
import {IFM_PC_ExternalPrice_Redeeming_v1} from "@fm/oracle/interfaces/IFM_PC_ExternalPrice_Redeeming_v1.sol";

import {LM_ManualExternalPriceSetter_v1} from "src/modules/logicModule/LM_ManualExternalPriceSetter_v1.sol";
import {LM_ManualExternalPriceSetter_v1_Exposed} from "test/modules/fundingManager/oracle/utils/mocks/LM_ManualExternalPriceSetter_v1_exposed.sol";
import {ILM_ManualExternalPriceSetter_v1} from "@lm/interfaces/ILM_ManualExternalPriceSetter_v1.sol";

import {ERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol";

// import {IModule_v1} from "src/modules/base/IModule_v1.sol";

import {
    InverterBeacon_v1,
    IInverterBeacon_v1
} from "src/proxies/InverterBeacon_v1.sol";

contract E2E_Funding_Payment is E2ETest {
    IOrchestratorFactory_v1.ModuleConfig[] moduleConfigurations;

    // E2E Test Variables
    // Constants
    string internal constant NAME = "Issuance Token";
    string internal constant SYMBOL = "IST";
    uint8 internal constant DECIMALS = 18;
    uint internal constant MAX_SUPPLY = type(uint).max;
    bytes32 constant WHITELIST_ROLE = "WHITELIST_ROLE";
    bytes32 constant ORACLE_ROLE = "ORACLE_ROLE";
    bytes32 constant QUEUE_MANAGER_ROLE = "QUEUE_MANAGER_ROLE";
    uint8 constant INTERNAL_DECIMALS = 18;
    uint constant BPS = 10000; // Basis points (100%)

    // Fee settings
    uint constant DEFAULT_BUY_FEE = 100;     // 1%
    uint constant DEFAULT_SELL_FEE = 100;    // 1%
    uint constant MAX_BUY_FEE = 500;         // 5%
    uint constant MAX_SELL_FEE = 500;        // 5%
    bool constant DIRECT_OPERATIONS_ONLY = false;

    // Module metadata


    // Module beacons


    // Test addresses
    address admin = address(this);
    address user = makeAddr("user");
    address whitelisted = makeAddr("whitelisted");
    address queueManager = makeAddr("queueManager");

    // Contracts
    ERC20Issuance_v1 issuanceToken;
    // LM_ManualExternalPriceSetter_v1 oracle;
    // FM_PC_ExternalPrice_Redeeming_v1 fundingManager;
    // PP_Queue_v1 paymentProcessor;

    function setUp() public override {
        // Setup common E2E framework
        super.setUp();

        // Set Up individual Modules the E2E test is going to use and store their configurations:
        // NOTE: It's important to store the module configurations in order, since _create_E2E_Orchestrator() will copy from the array.
        // The order should be:
        //      moduleConfigurations[0]  => FundingManager
        //      moduleConfigurations[1]  => Authorizer
        //      moduleConfigurations[2]  => PaymentProcessor
        //      moduleConfigurations[3:] => Additional Logic Modules


        // Additional Logic Modules
        setUpOracle();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                oracleMetadata, abi.encode(address(token), address(issuanceToken))
            )
        );

        // FundingManager
        setUpFundingManager();
        bytes memory configData = abi.encode(
            address(oracle),           // oracle address
            address(issuanceToken),    // issuance token
            address(token),           // accepted token
            DEFAULT_BUY_FEE,          // buy fee
            DEFAULT_SELL_FEE,         // sell fee
            MAX_SELL_FEE,             // max sell fee
            MAX_BUY_FEE,              // max buy fee
            DIRECT_OPERATIONS_ONLY     // direct operations only flag
        );
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                fundingManagerMetadata, configData
            )
        );
        // Authorizer
        setUpRoleAuthorizer();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                roleAuthorizerMetadata, abi.encode(address(this))
            )
        );

        // PaymentProcessor
        setUpPaymentProcessor();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                paymentProcessorMetadata, bytes("")
            )
        );
    }


    function test_e2e_RoleAuthorizer() public {

        assert(true);
    }

}
