
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

contract FundingManagerPaymentProcessorE2E is E2ETest {
    IOrchestratorFactory_v1.ModuleConfig[] moduleConfigurations;

    // E2E Test Variables
    // Constants
    string internal constant NAME = "Issuance Token";
    string internal constant SYMBOL = "IST";
    uint8 internal constant DECIMALS = 18;
    uint internal constant MAX_SUPPLY = type(uint).max;
    bytes32 constant WHITELIST_ROLE = "WHITELIST_ROLE";
    bytes32 constant PRICE_SETTER_ROLE = "PRICE_SETTER_ROLE";
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
    FM_PC_ExternalPrice_Redeeming_v1 fundingManager;
    PP_Queue_v1 paymentProcessor;
    AUT_Roles_v1 authorizer;

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

        // First create issuance token
        issuanceToken = new ERC20Issuance_v1(
            NAME, SYMBOL, DECIMALS, MAX_SUPPLY, address(this)
        );

        // Additional Logic Modules
        setUpOracle();
        
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
            true                      // buyIsOpen flag
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

        // Finally add the oracle configuration
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                oracleMetadata, abi.encode(address(token), address(issuanceToken))
            )
        );
    }

    function test_e2e_FundingPayment_succeedsGivenValidBuyAmountAndInitialPrice() public {
        // Create orchestrator with configurations
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig = IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });

        IOrchestrator_v1 orchestrator = _create_E2E_Orchestrator(workflowConfig, moduleConfigurations);

        // Get funding manager
        fundingManager = FM_PC_ExternalPrice_Redeeming_v1(address(orchestrator.fundingManager()));

        // Setup oracle and set prices
        uint256 initialPrice = 1e18; // 1:1 ratio
        LM_ManualExternalPriceSetter_v1 oraclelm = _setupOracle(orchestrator, admin, initialPrice);

        // Log debug information
        _logDebugInfo(orchestrator, oraclelm, initialPrice);

        // Prepare buy conditions
        uint256 buyAmount = 1000e18;
        _prepareBuyConditions(orchestrator, admin, user, buyAmount);

        // Execute buy
        vm.startPrank(user);
        fundingManager.buy(buyAmount, 1);
        vm.stopPrank();

        // Verify user received issuance tokens
        assertTrue(issuanceToken.balanceOf(user) > 0, "User should have received issuance tokens");
    }

    function test_e2e_BuyAndSell_succeedsGivenValidBuyAndRedeemAmounts() public {
        // Create orchestrator with configurations
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig = IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });

        IOrchestrator_v1 orchestrator = _create_E2E_Orchestrator(workflowConfig, moduleConfigurations);

        // Get funding manager and payment processor
        fundingManager = FM_PC_ExternalPrice_Redeeming_v1(address(orchestrator.fundingManager()));
        paymentProcessor = PP_Queue_v1(address(orchestrator.paymentProcessor()));

        // Setup oracle and set prices
        uint256 initialPrice = 1e18; // 1:1 ratio
        LM_ManualExternalPriceSetter_v1 oraclelm = _setupOracle(orchestrator, admin, initialPrice);

        // Log initial state
        console.log("=== Initial Setup ===");
        _logDebugInfo(orchestrator, oraclelm, initialPrice);

        // Prepare for buying
        uint256 buyAmount = 1000e18;
        console.log("User initial token balance:", token.balanceOf(user));
        console.log("User initial issuance token balance:", issuanceToken.balanceOf(user));

        _prepareBuyConditions(orchestrator, admin, user, buyAmount);

        // Execute buy
        console.log("\n=== Executing Buy ===");
        vm.startPrank(user);
        uint256 expectedIssuedTokens = fundingManager.calculatePurchaseReturn(buyAmount);
        fundingManager.buy(buyAmount, expectedIssuedTokens);
        vm.stopPrank();

        // Log state after buy
        console.log("\n=== State After Buy ===");
        uint256 issuanceTokenBalance = issuanceToken.balanceOf(user);
        console.log("User token balance after buy:", token.balanceOf(user));
        console.log("User issuance token balance after buy:", issuanceTokenBalance);

        // Prepare for redeeming
        console.log("\n=== Preparing Redeem ===");
        uint256 redeemAmount = issuanceTokenBalance / 3; // Redeem one third of the tokens
        console.log("Amount to redeem:", redeemAmount);

        // Prepare sell conditions
        _prepareSellConditions(orchestrator, admin, user, redeemAmount);

        // Execute sell
        vm.startPrank(user);
        uint256 minTokensToReceive = 1; // Minimum amount to receive, can be calculated based on price
        fundingManager.sell(redeemAmount, minTokensToReceive);
        vm.stopPrank();

        // Log final state
        console.log("\n=== Final State ===");
        console.log("User token balance after redeem:", token.balanceOf(user));
        console.log("User issuance token balance after redeem:", issuanceToken.balanceOf(user));
    }
    function _setupOracle(
        IOrchestrator_v1 orchestrator,
        address admin,
        uint256 initialPrice
    ) internal returns (LM_ManualExternalPriceSetter_v1) {
        // Find oracle module
        LM_ManualExternalPriceSetter_v1 oraclelm;
        address[] memory modulesList = orchestrator.listModules();
        for (uint i; i < modulesList.length; ++i) {
            try LM_ManualExternalPriceSetter_v1(modulesList[i]).getPriceForIssuance()
            returns (uint256) {
                oraclelm = LM_ManualExternalPriceSetter_v1(modulesList[i]);
                break;
            } catch {
                continue;
            }
        }
        require(address(oraclelm) != address(0), "Oracle module not found");

        // Grant oracle role to admin
        vm.prank(address(this));
        orchestrator.authorizer().grantRole(
            orchestrator.authorizer().generateRoleId(address(oraclelm), "PRICE_SETTER_ROLE"),
            admin
        );

        // Set initial prices
        vm.startPrank(admin);
        oraclelm.setIssuancePrice(initialPrice);
        oraclelm.setRedemptionPrice(initialPrice);
        vm.stopPrank();

        // Set oracle in funding manager
        vm.prank(admin);
        fundingManager.setOracleAddress(address(oraclelm));

        return oraclelm;
    }

    function _logDebugInfo(
        IOrchestrator_v1 orchestrator,
        LM_ManualExternalPriceSetter_v1 oraclelm,
        uint256 initialPrice
    ) internal {
  
        address[] memory modules = orchestrator.listModules();
        for (uint i = 0; i < modules.length; i++) {
            console.log("Module %s: %s", i, modules[i]);
        }

        console.log("Issuance Price:", oraclelm.getPriceForIssuance());
        console.log("Redemption Price:", oraclelm.getPriceForRedemption());
        console.log("Oracle address:", address(oraclelm));


        vm.prank(address(fundingManager));
        uint256 price = oraclelm.getPriceForIssuance();
        console.log("Price when called from funding manager:", price);
        require(price == initialPrice, "Price not set correctly");

        console.log("Expected module order from configurations:");
        console.log("Config[0] title: ", moduleConfigurations[0].metadata.title);
        console.log("Config[1] title: ", moduleConfigurations[1].metadata.title);
        console.log("Config[2] title: ", moduleConfigurations[2].metadata.title);
        console.log("Config[3] title: ", moduleConfigurations[3].metadata.title);
    }

    function _prepareBuyConditions(
        IOrchestrator_v1 orchestrator,
        address admin,
        address buyer,
        uint256 buyAmount
    ) internal {
        // Give minting rights to funding manager
        vm.startPrank(admin);
        issuanceToken.setMinter(address(fundingManager), true);
        vm.stopPrank();

        // Give test user some tokens
        token.mint(buyer, buyAmount);

        // Grant whitelist role to user
        vm.prank(address(this));
        orchestrator.authorizer().grantRole(
            orchestrator.authorizer().generateRoleId(address(fundingManager), "WHITELIST_ROLE"),
            buyer
        );

        // Approve tokens for spending
        vm.startPrank(buyer);
        token.approve(address(fundingManager), buyAmount);
        vm.stopPrank();

        // Ensure buying is enabled
        vm.prank(admin);
        fundingManager.openBuy();
    }

    function _prepareSellConditions(
        IOrchestrator_v1 orchestrator,
        address admin,
        address seller,
        uint256 amount
    ) internal {
        // Enable selling functionality
        vm.startPrank(admin);
        fundingManager.openSell();
        
        // Ensure funding manager has enough tokens for redemption
        uint256 requiredAmount = amount * 2; // Double to account for fees
        token.mint(address(fundingManager), requiredAmount);
        
        // Approve payment processor to spend tokens
        vm.stopPrank();
        
        // Approve funding manager to spend issuance tokens
        vm.startPrank(seller);
        issuanceToken.approve(address(fundingManager), amount);
        vm.stopPrank();
    }

    function _preparePaymentProcessor(
        IOrchestrator_v1 orchestrator,
        address admin
    ) internal {
        // Get payment processor
        paymentProcessor = PP_Queue_v1(address(orchestrator.paymentProcessor()));
    }

}
