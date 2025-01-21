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

import {ERC20DecimalsMock} from "test/utils/mocks/ERC20DecimalsMock.sol";

import {IERC20PaymentClientBase_v1} from "@lm/interfaces/IERC20PaymentClientBase_v1.sol";

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

    IOrchestrator_v1 public orchestrator;

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
        
        _setupOrchestratorFundingManagerPaymentProcessor();

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

        _setupOrchestratorFundingManagerPaymentProcessor();

        uint256 initialPrice = 1e18; // 1:1 ratio
        LM_ManualExternalPriceSetter_v1 oraclelm = _setupOracle(orchestrator, admin, initialPrice);


        // Prepare for buying
        uint256 buyAmount = 1000e18;
        console.log("User initial token balance:", token.balanceOf(user));
        console.log("User initial issuance token balance:", issuanceToken.balanceOf(user));

        _prepareBuyConditions(orchestrator, admin, user, buyAmount);

        // Execute buy
        vm.startPrank(user);
        uint256 expectedIssuedTokens = fundingManager.calculatePurchaseReturn(buyAmount);
        fundingManager.buy(buyAmount, expectedIssuedTokens);
        vm.stopPrank();
        console.log("buyAmount:", buyAmount);

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
        fundingManager.sell(buyAmount /4, minTokensToReceive);
        vm.stopPrank();

        // Log final state
        console.log("\n=== Final State ===");
        console.log("User token balance after redeem:", token.balanceOf(user));
        console.log("User issuance token balance after redeem:", issuanceToken.balanceOf(user));
    }

    function test_e2e_TwoUsers_BuyAndSell() public {
        _setupOrchestratorFundingManagerPaymentProcessor();

        // Setup initial price
        uint256 initialPrice = 1e17; 
        uint8 collateralDecimals = token.decimals();
        if (collateralDecimals != 18) {
            initialPrice = initialPrice * (10 ** (18 - collateralDecimals));
        }

        LM_ManualExternalPriceSetter_v1 oraclelm = _setupOracle(orchestrator, admin, initialPrice);
        vm.prank(admin);
        oraclelm.setRedemptionPrice(initialPrice);

        address user2 = makeAddr("user2");
        
        // Buy tokens
        uint256 buyAmount = 1e6; // 1 token colateral
        _prepareBuyConditions(orchestrator, admin, user2, buyAmount);
        vm.prank(user2);
        fundingManager.buy(buyAmount, 1);

        uint256 issuanceBalance = issuanceToken.balanceOf(user2);
        assertGt(issuanceBalance, 0, "User2 should have received issuance tokens");

        // Sell tokens
        _prepareSellConditions(orchestrator, admin, user2, issuanceBalance);
        vm.prank(user2);
        fundingManager.sell(issuanceBalance, 1);

        assertEq(
            issuanceToken.balanceOf(user2), 
            0, 
            "User2 should have 0 issuance tokens after selling all"
        );
    }

    function test_e2e_MultiUserSell_validatesQueueIdCorrectly() public {
        _setupOrchestratorFundingManagerPaymentProcessor();

        // Setup users
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        uint256 initialPrice = 1e18; // 1:1 ratio
        uint256 buyAmount = 1e18;

        // Setup oracle price
        LM_ManualExternalPriceSetter_v1 oraclelm = _setupOracle(orchestrator, admin, initialPrice);
        vm.prank(admin);
        oraclelm.setRedemptionPrice(initialPrice);

        // User 1 buys tokens
        console.log("\n=== User 1 buying tokens ===");
        _prepareBuyConditions(orchestrator, admin, user1, buyAmount);
        vm.prank(user1);
        fundingManager.buy(buyAmount, 1);
        uint256 user1Balance = issuanceToken.balanceOf(user1);
        assertGt(user1Balance, 0, "User1 should have received issuance tokens");

        // User 2 buys tokens
        console.log("\n=== User 2 buying tokens ===");
        _prepareBuyConditions(orchestrator, admin, user2, buyAmount);
        vm.prank(user2);
        fundingManager.buy(buyAmount, 1);
        uint256 user2Balance = issuanceToken.balanceOf(user2);
        assertGt(user2Balance, 0, "User2 should have received issuance tokens");

        // Prepare sell conditions for both users
        _prepareSellConditions(orchestrator, admin, user1, user1Balance);
        _prepareSellConditions(orchestrator, admin, user2, user2Balance);

        // User 1 sells tokens
        console.log("\n=== User 1 selling tokens ===");
        vm.prank(user1);
        fundingManager.sell(user1Balance, 1);

        // User 2 sells tokens
        console.log("\n=== User 2 selling tokens ===");
        vm.prank(user2);
        fundingManager.sell(user2Balance, 2);

        // Verify both users have sold their tokens
        assertEq(issuanceToken.balanceOf(user1), 0, "User1 should have 0 issuance tokens after selling");
        assertEq(issuanceToken.balanceOf(user2), 0, "User2 should have 0 issuance tokens after selling");
    }

    function test_e2e_FundPaymentProcessor() public {
        _setupOrchestratorFundingManagerPaymentProcessor();

        // Setup oracle and set prices
        uint256 initialPrice = 1e18; // 1:1 ratio
        LM_ManualExternalPriceSetter_v1 oraclelm = _setupOracle(orchestrator, admin, initialPrice);
        vm.prank(admin);
        oraclelm.setRedemptionPrice(initialPrice);

        // Setup user and initial conditions
        address user = makeAddr("user");
        uint256 buyAmount = 1e18;

        // User buys tokens first
        console.log("\n=== User buying tokens ===");
        _prepareBuyConditions(orchestrator, admin, user, buyAmount);
        vm.prank(user);
        fundingManager.buy(buyAmount, 1);
        uint256 userBalance = issuanceToken.balanceOf(user);
        assertGt(userBalance, 0, "User should have received issuance tokens");

        // User creates a sell order which adds a payment order to the queue
        console.log("\n=== Creating sell order (adds payment to queue) ===");
        _prepareSellConditions(orchestrator, admin, user, userBalance);
        vm.prank(user);
        fundingManager.sell(userBalance, 1);

        // Get the payment processor's balance before funding
        uint256 balanceBefore = token.balanceOf(address(paymentProcessor));

        // Fund the payment processor with tokens to process payments
        console.log("\n=== Funding payment processor ===");
        vm.startPrank(admin);
        token.mint(admin, userBalance);
        token.transfer(address(paymentProcessor), userBalance);
        vm.stopPrank();

        // Verify the funding
        uint256 balanceAfter = token.balanceOf(address(paymentProcessor));
        assertEq(balanceAfter, balanceBefore + userBalance, "Payment processor should have received the tokens for processing payments");
    }

    function test_e2e_ProcessPaymentQueue() public {
        _setupOrchestratorFundingManagerPaymentProcessor();

        // Setup oracle and set prices
        uint256 initialPrice = 1e18; // 1:1 ratio
        LM_ManualExternalPriceSetter_v1 oraclelm = _setupOracle(orchestrator, admin, initialPrice);
        vm.prank(admin);
        oraclelm.setRedemptionPrice(initialPrice);

        // Setup user and initial conditions
        address user = makeAddr("user");
        uint256 buyAmount = 1e18;

        // User buys tokens first
        console.log("\n=== User buying tokens ===");
        _prepareBuyConditions(orchestrator, admin, user, buyAmount);
        vm.prank(user);
        fundingManager.buy(buyAmount, 1);
        uint256 userBalance = issuanceToken.balanceOf(user);
        assertGt(userBalance, 0, "User should have received issuance tokens");

        // Fund the payment processor with tokens to process payments
        console.log("\n=== Funding payment processor ===");
        vm.startPrank(admin);
        token.mint(admin, userBalance);
        token.transfer(address(paymentProcessor), userBalance);
        vm.stopPrank();

        // Get user's balance before selling
        uint256 userBalanceBefore = token.balanceOf(user);

        // User sells tokens which triggers payment processing
        console.log("\n=== User selling tokens ===");
        _prepareSellConditions(orchestrator, admin, user, userBalance);
        vm.prank(user);
        fundingManager.sell(userBalance, 1);

        // Verify payment was processed correctly
        uint256 userBalanceAfter = token.balanceOf(user);
        
        assertGt(userBalanceAfter, userBalanceBefore, "User should have received payment");
        assertEq(issuanceToken.balanceOf(user), 0, "User should have 0 issuance tokens after sell");

        // Verify queue is empty by checking its size
        uint256 queueSize = IPP_Queue_v1(address(paymentProcessor)).getQueueSizeForClient(address(fundingManager));
        assertEq(queueSize, 0, "Queue should be empty after payment processing");
    }

    function test_e2e_ProcessMultiplePayments() public {
        _setupOrchestratorFundingManagerPaymentProcessor();

        // Setup oracle and set prices
        uint256 initialPrice = 1e18;
        LM_ManualExternalPriceSetter_v1 oraclelm = _setupOracle(orchestrator, admin, initialPrice);
        vm.prank(admin);
        oraclelm.setRedemptionPrice(initialPrice);

        // Setup users
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        uint256 buyAmount = 1e18;

        // Fund payment processor
        vm.startPrank(admin);
        token.mint(admin, buyAmount * 2);
        token.transfer(address(paymentProcessor), buyAmount * 2);
        vm.stopPrank();

        // User 1 buys and sells
        console.log("\n=== User 1 buying and selling ===");
        _prepareBuyConditions(orchestrator, admin, user1, buyAmount);
        vm.prank(user1);
        fundingManager.buy(buyAmount, 1);
        uint256 user1Balance = issuanceToken.balanceOf(user1);
        
        uint256 user1TokensBefore = token.balanceOf(user1);
        _prepareSellConditions(orchestrator, admin, user1, user1Balance);
        vm.prank(user1);
        fundingManager.sell(user1Balance, 1);

        // User 2 buys and sells
        console.log("\n=== User 2 buying and selling ===");
        _prepareBuyConditions(orchestrator, admin, user2, buyAmount);
        vm.prank(user2);
        fundingManager.buy(buyAmount, 1);
        uint256 user2Balance = issuanceToken.balanceOf(user2);
        
        uint256 user2TokensBefore = token.balanceOf(user2);
        _prepareSellConditions(orchestrator, admin, user2, user2Balance);
        vm.prank(user2);
        fundingManager.sell(user2Balance, 1);

        // Verify both users received their payments
        assertGt(token.balanceOf(user1), user1TokensBefore, "User 1 should have received payment");
        assertGt(token.balanceOf(user2), user2TokensBefore, "User 2 should have received payment");
        assertEq(issuanceToken.balanceOf(user1), 0, "User 1 should have 0 issuance tokens");
        assertEq(issuanceToken.balanceOf(user2), 0, "User 2 should have 0 issuance tokens");

        // Verify queue is empty
        uint256 queueSize = IPP_Queue_v1(address(paymentProcessor)).getQueueSizeForClient(address(fundingManager));
        assertEq(queueSize, 0, "Queue should be empty after processing all payments");
    }

    function test_e2e_ProcessPaymentsWithInsufficientBalance() public {
        _setupOrchestratorFundingManagerPaymentProcessor();

        // Setup oracle and set prices
        uint256 initialPrice = 1e18;
        LM_ManualExternalPriceSetter_v1 oraclelm = _setupOracle(orchestrator, admin, initialPrice);
        vm.prank(admin);
        oraclelm.setRedemptionPrice(initialPrice);

        // Setup user
        address user = makeAddr("user");
        uint256 buyAmount = 1e18;

        // User buys tokens first
        console.log("\n=== User buying tokens ===");
        _prepareBuyConditions(orchestrator, admin, user, buyAmount);
        vm.prank(user);
        fundingManager.buy(buyAmount, 1);
        uint256 userBalance = issuanceToken.balanceOf(user);

        // Prepare sell conditions without funding the payment processor
        _prepareSellConditionsWithoutFunding(orchestrator, admin, user, userBalance);

        // User tries to sell - should revert due to queue operation failure
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("Module__PP_Queue_QueueOperationFailed(address)", address(fundingManager)));
        fundingManager.sell(userBalance, 1);

        // Verify user still has their issuance tokens
        assertEq(issuanceToken.balanceOf(user), userBalance, "User should still have their issuance tokens");
    }

    //@audit => TODO
    function test_e2e_UnclaimablePayments() public {
        _setupOrchestratorFundingManagerPaymentProcessor();

        // Setup oracle and set prices
        uint256 initialPrice = 1e18;
        LM_ManualExternalPriceSetter_v1 oraclelm = _setupOracle(orchestrator, admin, initialPrice);
        vm.prank(admin);
        oraclelm.setRedemptionPrice(initialPrice);

        // Setup user
        address user = makeAddr("user");
        uint256 buyAmount = 1e18;

        // User buys tokens
        _prepareBuyConditions(orchestrator, admin, user, buyAmount);
        vm.prank(user);
        fundingManager.buy(buyAmount, 1);
        uint256 userBalance = issuanceToken.balanceOf(user);

        // Prepare sell conditions and fund the fundingManager
        _prepareSellConditionsWithoutFunding(orchestrator, admin, user, userBalance);
        vm.startPrank(admin);
        token.mint(address(fundingManager), userBalance * 2); // Fund with extra tokens to ensure enough balance
        vm.stopPrank();
        
        // Attempt sell - this should fail because payment processor has no funds
        vm.prank(user);
        fundingManager.sell(userBalance, 1);

        // Check unclaimable amount
        uint256 unclaimableAmount = paymentProcessor.unclaimable(
            address(fundingManager),
            address(token),
            user
        );
        assertGt(unclaimableAmount, 0, "Should have unclaimable amount");

        // Fund payment processor
        vm.startPrank(admin);
        token.mint(admin, unclaimableAmount);
        token.transfer(address(paymentProcessor), unclaimableAmount);
        vm.stopPrank();

        // Claim unclaimable amount
        vm.prank(user);
        paymentProcessor.claimPreviouslyUnclaimable(
            address(fundingManager),
            address(token),
            user
        );

        // Verify claim was successful
        assertEq(
            paymentProcessor.unclaimable(address(fundingManager), address(token), user),
            0,
            "Unclaimable amount should be 0 after claim"
        );
    }
    //@audit => TODO
    function test_e2e_QueueOperations() public {
        _setupOrchestratorFundingManagerPaymentProcessor();

        // Setup oracle and set prices
        uint256 initialPrice = 1e18;
        LM_ManualExternalPriceSetter_v1 oraclelm = _setupOracle(orchestrator, admin, initialPrice);
        vm.prank(admin);
        oraclelm.setRedemptionPrice(initialPrice);

        // Setup multiple users
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        uint256 buyAmount = 1e18;

        // Users buy tokens
        _prepareBuyConditions(orchestrator, admin, user1, buyAmount);
        vm.prank(user1);
        fundingManager.buy(buyAmount, 1);
        uint256 user1Balance = issuanceToken.balanceOf(user1);

        _prepareBuyConditions(orchestrator, admin, user2, buyAmount);
        vm.prank(user2);
        fundingManager.buy(buyAmount, 1);
        uint256 user2Balance = issuanceToken.balanceOf(user2);

        // Calculate total payment amount needed
        uint256 totalPaymentAmount = user1Balance + user2Balance;

        // Fund the fundingManager with tokens BEFORE sells
        vm.startPrank(admin);
        token.mint(address(fundingManager), totalPaymentAmount);
        vm.stopPrank();

        // Create sell orders without funding payment processor
        _prepareSellConditionsWithoutFunding(orchestrator, admin, user1, user1Balance);
        
        // Approve payment processor to spend tokens from funding manager for first sell
        vm.prank(address(fundingManager));
        token.approve(address(paymentProcessor), user1Balance);
        
        vm.prank(user1);
        fundingManager.sell(user1Balance, 1);

        _prepareSellConditionsWithoutFunding(orchestrator, admin, user2, user2Balance);
        
        // Approve payment processor to spend tokens from funding manager for second sell
        vm.prank(address(fundingManager));
        token.approve(address(paymentProcessor), user2Balance);
        
        vm.prank(user2);
        fundingManager.sell(user2Balance, 1);

        // Check queue operations before processing
        uint256 queueHead = IPP_Queue_v1(address(paymentProcessor)).getQueueHead(address(fundingManager));
        uint256 queueTail = IPP_Queue_v1(address(paymentProcessor)).getQueueTail(address(fundingManager));
        uint256 queueSize = IPP_Queue_v1(address(paymentProcessor)).getQueueSizeForClient(address(fundingManager));

        assertGt(queueHead, 0, "Queue head should be set");
        assertGt(queueTail, 0, "Queue tail should be set");
        assertEq(queueSize, 2, "Queue should have 2 items");
        assertGt(queueTail, queueHead, "Tail ID should be greater than head ID");

        // Process the queue - call must come from fundingManager
        vm.prank(address(fundingManager));
        paymentProcessor.processPayments(IERC20PaymentClientBase_v1(address(fundingManager)));

        // Verify queue is empty after processing
        queueSize = IPP_Queue_v1(address(paymentProcessor)).getQueueSizeForClient(address(fundingManager));
        assertEq(queueSize, 0, "Queue should be empty after processing");

        // Verify users received their tokens
        assertGt(token.balanceOf(user1), 0, "User1 should have received tokens");
        assertGt(token.balanceOf(user2), 0, "User2 should have received tokens");
    }

    function _setupOrchestratorFundingManagerPaymentProcessor() internal {

        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig = IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });

        orchestrator = _create_E2E_Orchestrator(workflowConfig, moduleConfigurations);

        fundingManager = FM_PC_ExternalPrice_Redeeming_v1(address(orchestrator.fundingManager()));
        paymentProcessor = PP_Queue_v1(address(orchestrator.paymentProcessor()));
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

    function _prepareSellConditionsWithoutFunding(
        IOrchestrator_v1 orchestrator,
        address admin,
        address seller,
        uint256 amount
    ) internal {
        // Enable selling functionality
        vm.startPrank(admin);
        fundingManager.openSell();
        vm.stopPrank();
        
        // Approve funding manager to spend issuance tokens
        vm.startPrank(seller);
        issuanceToken.approve(address(fundingManager), amount);
        vm.stopPrank();
    }

}
