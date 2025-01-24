// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// SuT
import {AUT_Roles_v1} from "@aut/role/AUT_Roles_v1.sol";

// Internal Dependencies
import {
    E2ETest,
    IOrchestratorFactory_v1,
    IOrchestrator_v1
} from "test/e2e/E2ETest.sol";

// Import modules that are used in this E2E test
import {IPP_Queue_v1} from "@pp/interfaces/IPP_Queue_v1.sol";
import {PP_Queue_v1} from "@pp/PP_Queue_v1.sol";

import {LinkedIdList} from "src/modules/lib/LinkedIdList.sol";
//
import {FM_PC_ExternalPrice_Redeeming_v1} from
    "src/modules/fundingManager/oracle/FM_PC_ExternalPrice_Redeeming_v1.sol";
import {IFM_PC_ExternalPrice_Redeeming_v1} from
    "@fm/oracle/interfaces/IFM_PC_ExternalPrice_Redeeming_v1.sol";

import {LM_ManualExternalPriceSetter_v1} from
    "src/modules/logicModule/LM_ManualExternalPriceSetter_v1.sol";
import {LM_ManualExternalPriceSetter_v1_Exposed} from
    "test/modules/fundingManager/oracle/utils/mocks/LM_ManualExternalPriceSetter_v1_exposed.sol";
import {ILM_ManualExternalPriceSetter_v1} from
    "@lm/interfaces/ILM_ManualExternalPriceSetter_v1.sol";

import {ERC20Issuance_Blacklist_v1} from
    "@ex/token/ERC20Issuance_Blacklist_v1.sol";
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

// import {IModule_v1} from "src/modules/base/IModule_v1.sol";

import {
    InverterBeacon_v1,
    IInverterBeacon_v1
} from "src/proxies/InverterBeacon_v1.sol";

import {ERC20DecimalsMock} from "test/utils/mocks/ERC20DecimalsMock.sol";

import {IERC20PaymentClientBase_v1} from
    "@lm/interfaces/IERC20PaymentClientBase_v1.sol";

contract FundingManagerPaymentProcessorE2E is E2ETest {
    IOrchestratorFactory_v1.ModuleConfig[] moduleConfigurations;

    // E2E Test Variables
    // -------------------------------------------------------------------------
    // Constants
    uint constant BPS = 10_000; // Basis points (100%)

    // Issuance token constants
    string internal constant NAME = "Mock USDC";
    string internal constant SYMBOL = "M-USDC";
    uint8 internal constant DECIMALS = 6;
    uint internal constant MAX_SUPPLY = type(uint).max;

    // FM Fee settings
    uint constant DEFAULT_BUY_FEE = 0; // 1%
    uint constant DEFAULT_SELL_FEE = 20; // 0.2%
    uint constant MAX_BUY_FEE = 0; // 0%
    uint constant MAX_SELL_FEE = 100; // 1%
    bool constant DIRECT_OPERATIONS_ONLY = false;

    // Roles in the workflow
    bytes32 private constant WHITELIST_ROLE = "WHITELIST_ROLE";
    bytes32 private constant WHITELIST_ROLE_ADMIN = "WHITELIST_ROLE_ADMIN";
    bytes32 private constant QUEUE_EXECUTOR_ROLE = "QUEUE_EXECUTOR_ROLE";
    bytes32 private constant QUEUE_EXECUTOR_ROLE_ADMIN =
        "QUEUE_EXECUTOR_ROLE_ADMIN";
    bytes32 private constant QUEUE_OPERATOR_ROLE = "QUEUE_OPERATOR_ROLE";
    bytes32 private constant QUEUE_OPERATOR_ROLE_ADMIN =
        "QUEUE_OPERATOR_ROLE_ADMIN";
    bytes32 private constant PRICE_SETTER_ROLE = "PRICE_SETTER_ROLE";
    bytes32 private constant PRICE_SETTER_ROLE_ADMIN = "PRICE_SETTER_ROLE_ADMIN";
    // -------------------------------------------------------------------------
    // Test variables

    // Addresses
    address admin = address(this);
    address whitelistManager = makeAddr("whitelistManager");
    address whitelisted = makeAddr("whitelisted");
    address queueOperatorManager = makeAddr("queueOperatorManager");
    address queueOperator = makeAddr("queueOperator");
    address queueExecutorManager = makeAddr("queueExecutorManager");
    address queueExecutor = makeAddr("queueExecutor");
    address user = makeAddr("user");
    address queueManager = makeAddr("queueManager");

    // Contracts
    ERC20Issuance_Blacklist_v1 issuanceToken;
    FM_PC_ExternalPrice_Redeeming_v1 fundingManager;
    PP_Queue_v1 paymentProcessor;
    AUT_Roles_v1 authorizer;
    LM_ManualExternalPriceSetter_v1 permissionedOracle;
    IOrchestrator_v1 orchestrator;

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
        issuanceToken = new ERC20Issuance_Blacklist_v1(
            NAME, SYMBOL, DECIMALS, MAX_SUPPLY, address(this), address(this)
        );

        // FundingManager
        setUpPermissionedOracleRedeemingFundingManager();
        bytes memory configData = abi.encode(
            address(oracle), // oracle address
            address(issuanceToken), // issuance token
            address(token), // collateral token
            DEFAULT_BUY_FEE, // buy fee
            DEFAULT_SELL_FEE, // sell fee
            MAX_SELL_FEE, // max sell fee
            MAX_BUY_FEE, // max buy fee
            DIRECT_OPERATIONS_ONLY // direct operations only flag
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
        setUpQueuePaymentProcessor();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                paymentProcessorMetadata, bytes("")
            )
        );

        // Additional Logic Modules
        setUpPermissionedOracle();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                oracleMetadata,
                abi.encode(address(token), address(issuanceToken))
            )
        );
    }

    function _init() private {
        //--------------------------------------------------------------------------
        // Orchestrator_v1 Initialization
        //--------------------------------------------------------------------------
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig =
        IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });

        orchestrator =
            _create_E2E_Orchestrator(workflowConfig, moduleConfigurations);

        // Get funding manager
        fundingManager = FM_PC_ExternalPrice_Redeeming_v1(
            address(orchestrator.fundingManager())
        );

        // Get payment processor
        paymentProcessor = PP_Queue_v1(address(orchestrator.paymentProcessor()));

        // Get permissioned oracle
        address[] memory modulesList = orchestrator.listModules();
        for (uint i; i < modulesList.length; ++i) {
            if (
                ERC165Upgradeable(modulesList[i]).supportsInterface(
                    type(ILM_ManualExternalPriceSetter_v1).interfaceId
                )
            ) {
                permissionedOracle =
                    LM_ManualExternalPriceSetter_v1(modulesList[i]);
                break;
            }
        }
        fundingManager.setOracleAddress(address(permissionedOracle));
        issuanceToken.setMinter(address(fundingManager), true);
    }

    function test_e2e_QueueBaseFundingManagerAndPaymentProcessorLifecycle()
        public
    {
        _init();

        //--------------------------------------------------------------------------
        // Assign role admins for roles in the system

        bytes32 roleId;
        // Assign role admin for the permissioned oracle
        roleId = authorizer.generateRoleId(
            address(permissionedOracle), PRICE_SETTER_ROLE
        );
        authorizer.transferAdminRole(roleId, PRICE_SETTER_ROLE_ADMIN);

        // Assign role admin for the Queue Based Payment Processor
        roleId = authorizer.generateRoleId(
            address(paymentProcessor), QUEUE_OPERATOR_ROLE
        );
        authorizer.transferAdminRole(roleId, QUEUE_OPERATOR_ROLE_ADMIN);

        // Assign role admins for the Oracle Based Funding Manager
        roleId =
            authorizer.generateRoleId(address(fundingManager), WHITELIST_ROLE);
        authorizer.transferAdminRole(roleId, WHITELIST_ROLE_ADMIN);

        roleId = authorizer.generateRoleId(
            address(fundingManager), QUEUE_EXECUTOR_ROLE
        );
        authorizer.transferAdminRole(roleId, QUEUE_EXECUTOR_ROLE_ADMIN);

        //--------------------------------------------------------------------------
        // Assign role to addresses in the system

        // Setup oracle and set prices
        uint initialPrice = 1e18; // 1:1 ratio
        LM_ManualExternalPriceSetter_v1 oraclelm =
            _setupOracle(orchestrator, admin, initialPrice);

        // Log debug information
        _logDebugInfo(orchestrator, oraclelm, initialPrice);

        // Prepare buy conditions
        uint buyAmount = 1000e18;
        _prepareBuyConditions(orchestrator, admin, user, buyAmount);

        // Execute buy
        vm.startPrank(user);
        fundingManager.buy(buyAmount, 1);
        vm.stopPrank();

        // Verify user received issuance tokens
        assertTrue(
            issuanceToken.balanceOf(user) > 0,
            "User should have received issuance tokens"
        );
    }

    function test_e2e_BuyAndSell_WithQueueProcessing() public {
        _init();

        uint initialPrice = 1e18; // 1:1 ratio
        LM_ManualExternalPriceSetter_v1 oraclelm =
            _setupOracle(orchestrator, admin, initialPrice);

        // Prepare for buying
        uint buyAmount = 1000e18;
        console.log("User initial token balance:", token.balanceOf(user));
        console.log(
            "User initial issuance token balance:",
            issuanceToken.balanceOf(user)
        );

        _prepareBuyConditions(orchestrator, admin, user, buyAmount);

        // Execute buy
        vm.startPrank(user);
        uint expectedIssuedTokens =
            fundingManager.calculatePurchaseReturn(buyAmount);
        fundingManager.buy(buyAmount, expectedIssuedTokens);
        vm.stopPrank();
        console.log("buyAmount:", buyAmount);

        // Log state after buy
        console.log("\n=== State After Buy ===");
        uint issuanceTokenBalance = issuanceToken.balanceOf(user);
        console.log("User token balance after buy:", token.balanceOf(user));
        console.log(
            "User issuance token balance after buy:", issuanceTokenBalance
        );

        // Prepare for redeeming
        console.log("\n=== Preparing Redeem ===");
        uint redeemAmount = issuanceTokenBalance / 3; // Redeem one third of the tokens
        console.log("Amount to redeem:", redeemAmount);

        // Prepare sell conditions
        _prepareSellConditions(orchestrator, admin, user, redeemAmount);

        // Execute sell
        vm.startPrank(user);
        uint minTokensToReceive = 1; // Minimum amount to receive, can be calculated based on price
        fundingManager.sell(buyAmount / 4, minTokensToReceive);
        vm.stopPrank();

        // Log final state
        console.log("\n=== Final State ===");
        console.log("User token balance after redeem:", token.balanceOf(user));
        console.log(
            "User issuance token balance after redeem:",
            issuanceToken.balanceOf(user)
        );
    }

    function test_e2e_BuyAndSell_TwoUsers() public {
        _init();

        // Setup initial price
        uint initialPrice = 1e17;
        uint8 collateralDecimals = token.decimals();
        if (collateralDecimals != 18) {
            initialPrice = initialPrice * (10 ** (18 - collateralDecimals));
        }

        LM_ManualExternalPriceSetter_v1 oraclelm =
            _setupOracle(orchestrator, admin, initialPrice);
        vm.prank(admin);
        oraclelm.setRedemptionPrice(initialPrice);

        address user2 = makeAddr("user2");

        // Buy tokens
        uint buyAmount = 1e6; // 1 token colateral
        _prepareBuyConditions(orchestrator, admin, user2, buyAmount);
        vm.prank(user2);
        fundingManager.buy(buyAmount, 1);

        uint issuanceBalance = issuanceToken.balanceOf(user2);
        assertGt(
            issuanceBalance, 0, "User2 should have received issuance tokens"
        );

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

    function test_e2e_Sell_MultipleUsersQueueOrder() public {
        _init();

        // Setup users
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        uint initialPrice = 1e18; // 1:1 ratio
        uint buyAmount = 1e18;

        // Setup oracle price
        LM_ManualExternalPriceSetter_v1 oraclelm =
            _setupOracle(orchestrator, admin, initialPrice);
        vm.prank(admin);
        oraclelm.setRedemptionPrice(initialPrice);

        // User 1 buys tokens
        console.log("\n=== User 1 buying tokens ===");
        _prepareBuyConditions(orchestrator, admin, user1, buyAmount);
        vm.prank(user1);
        fundingManager.buy(buyAmount, 1);
        uint user1Balance = issuanceToken.balanceOf(user1);
        assertGt(user1Balance, 0, "User1 should have received issuance tokens");

        // User 2 buys tokens
        console.log("\n=== User 2 buying tokens ===");
        _prepareBuyConditions(orchestrator, admin, user2, buyAmount);
        vm.prank(user2);
        fundingManager.buy(buyAmount, 1);
        uint user2Balance = issuanceToken.balanceOf(user2);
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
        assertEq(
            issuanceToken.balanceOf(user1),
            0,
            "User1 should have 0 issuance tokens after selling"
        );
        assertEq(
            issuanceToken.balanceOf(user2),
            0,
            "User2 should have 0 issuance tokens after selling"
        );
    }

    function test_e2e_DepositFunds_PaymentProcessor() public {
        _init();

        // Setup oracle and set prices
        uint initialPrice = 1e18; // 1:1 ratio
        LM_ManualExternalPriceSetter_v1 oraclelm =
            _setupOracle(orchestrator, admin, initialPrice);
        vm.prank(admin);
        oraclelm.setRedemptionPrice(initialPrice);

        // Setup user and initial conditions
        address user = makeAddr("user");
        uint buyAmount = 1e18;

        // User buys tokens first
        console.log("\n=== User buying tokens ===");
        _prepareBuyConditions(orchestrator, admin, user, buyAmount);
        vm.prank(user);
        fundingManager.buy(buyAmount, 1);
        uint userBalance = issuanceToken.balanceOf(user);
        assertGt(userBalance, 0, "User should have received issuance tokens");

        // User creates a sell order which adds a payment order to the queue
        console.log("\n=== Creating sell order (adds payment to queue) ===");
        _prepareSellConditions(orchestrator, admin, user, userBalance);
        vm.prank(user);
        fundingManager.sell(userBalance, 1);

        // Get the payment processor's balance before funding
        uint balanceBefore = token.balanceOf(address(paymentProcessor));

        // Fund the payment processor with tokens to process payments
        console.log("\n=== Funding payment processor ===");
        vm.startPrank(admin);
        token.mint(admin, userBalance);
        token.transfer(address(paymentProcessor), userBalance);
        vm.stopPrank();

        // Verify the funding
        uint balanceAfter = token.balanceOf(address(paymentProcessor));
        assertEq(
            balanceAfter,
            balanceBefore + userBalance,
            "Payment processor should have received the tokens for processing payments"
        );
    }

    function test_e2e_ExecuteQueue_SinglePayment() public {
        _init();

        // Setup oracle and set prices
        uint initialPrice = 1e18; // 1:1 ratio
        LM_ManualExternalPriceSetter_v1 oraclelm =
            _setupOracle(orchestrator, admin, initialPrice);
        vm.prank(admin);
        oraclelm.setRedemptionPrice(initialPrice);

        // Setup user and initial conditions
        address user = makeAddr("user");
        uint buyAmount = 1e18;

        // User buys tokens first
        console.log("\n=== User buying tokens ===");
        _prepareBuyConditions(orchestrator, admin, user, buyAmount);
        vm.prank(user);
        fundingManager.buy(buyAmount, 1);
        uint userBalance = issuanceToken.balanceOf(user);
        assertGt(userBalance, 0, "User should have received issuance tokens");

        // Fund the payment processor with tokens to process payments
        console.log("\n=== Funding payment processor ===");
        vm.startPrank(admin);
        token.mint(admin, userBalance);
        token.transfer(address(paymentProcessor), userBalance);
        vm.stopPrank();

        // Get user's balance before selling
        uint userBalanceBefore = token.balanceOf(user);

        // User sells tokens which triggers payment processing
        console.log("\n=== User selling tokens ===");
        _prepareSellConditions(orchestrator, admin, user, userBalance);
        vm.prank(user);
        fundingManager.sell(userBalance, 1);

        // Verify payment was processed correctly
        uint userBalanceAfter = token.balanceOf(user);

        assertGt(
            userBalanceAfter,
            userBalanceBefore,
            "User should have received payment"
        );
        assertEq(
            issuanceToken.balanceOf(user),
            0,
            "User should have 0 issuance tokens after sell"
        );

        // Verify queue is empty by checking its size
        uint queueSize = IPP_Queue_v1(address(paymentProcessor))
            .getQueueSizeForClient(address(fundingManager));
        assertEq(queueSize, 0, "Queue should be empty after payment processing");
    }

    function test_e2e_ExecuteQueue_MultiplePayments() public {
        _init();

        // Setup oracle and set prices
        uint initialPrice = 1e18;
        LM_ManualExternalPriceSetter_v1 oraclelm =
            _setupOracle(orchestrator, admin, initialPrice);
        vm.prank(admin);
        oraclelm.setRedemptionPrice(initialPrice);

        // Setup users
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        uint buyAmount = 1e18;

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
        uint user1Balance = issuanceToken.balanceOf(user1);

        uint user1TokensBefore = token.balanceOf(user1);
        _prepareSellConditions(orchestrator, admin, user1, user1Balance);
        vm.prank(user1);
        fundingManager.sell(user1Balance, 1);

        // User 2 buys and sells
        console.log("\n=== User 2 buying and selling ===");
        _prepareBuyConditions(orchestrator, admin, user2, buyAmount);
        vm.prank(user2);
        fundingManager.buy(buyAmount, 1);
        uint user2Balance = issuanceToken.balanceOf(user2);

        uint user2TokensBefore = token.balanceOf(user2);
        _prepareSellConditions(orchestrator, admin, user2, user2Balance);
        vm.prank(user2);
        fundingManager.sell(user2Balance, 1);

        // Verify both users received their payments
        assertGt(
            token.balanceOf(user1),
            user1TokensBefore,
            "User 1 should have received payment"
        );
        assertGt(
            token.balanceOf(user2),
            user2TokensBefore,
            "User 2 should have received payment"
        );
        assertEq(
            issuanceToken.balanceOf(user1),
            0,
            "User 1 should have 0 issuance tokens"
        );
        assertEq(
            issuanceToken.balanceOf(user2),
            0,
            "User 2 should have 0 issuance tokens"
        );

        // Verify queue is empty
        uint queueSize = IPP_Queue_v1(address(paymentProcessor))
            .getQueueSizeForClient(address(fundingManager));
        assertEq(
            queueSize, 0, "Queue should be empty after processing all payments"
        );
    }

    function test_e2e_ExecuteQueue_InsufficientBalance() public {
        _init();

        // Setup oracle and set prices
        uint initialPrice = 1e18;
        LM_ManualExternalPriceSetter_v1 oraclelm =
            _setupOracle(orchestrator, admin, initialPrice);
        vm.prank(admin);
        oraclelm.setRedemptionPrice(initialPrice);

        // Setup user
        address user = makeAddr("user");
        uint buyAmount = 1e18;

        // User buys tokens first
        console.log("\n=== User buying tokens ===");
        _prepareBuyConditions(orchestrator, admin, user, buyAmount);
        vm.prank(user);
        fundingManager.buy(buyAmount, 1);
        uint userBalance = issuanceToken.balanceOf(user);

        // Prepare sell conditions without funding the payment processor
        _prepareSellConditionsWithoutFunding(
            orchestrator, admin, user, userBalance
        );

        // User tries to sell - should revert due to queue operation failure
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__PP_Queue_QueueOperationFailed(address)",
                address(fundingManager)
            )
        );
        fundingManager.sell(userBalance, 1);

        // Verify user still has their issuance tokens
        assertEq(
            issuanceToken.balanceOf(user),
            userBalance,
            "User should still have their issuance tokens"
        );
    }

    function _setupOracle(
        IOrchestrator_v1 orchestrator,
        address admin,
        uint initialPrice
    ) internal returns (LM_ManualExternalPriceSetter_v1) {
        // Find oracle module
        LM_ManualExternalPriceSetter_v1 oraclelm;
        address[] memory modulesList = orchestrator.listModules();
        for (uint i; i < modulesList.length; ++i) {
            try LM_ManualExternalPriceSetter_v1(modulesList[i])
                .getPriceForIssuance() returns (uint) {
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
            orchestrator.authorizer().generateRoleId(
                address(oraclelm), "PRICE_SETTER_ROLE"
            ),
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
        uint initialPrice
    ) internal {
        address[] memory modules = orchestrator.listModules();
        for (uint i = 0; i < modules.length; i++) {
            console.log("Module %s: %s", i, modules[i]);
        }

        console.log("Issuance Price:", oraclelm.getPriceForIssuance());
        console.log("Redemption Price:", oraclelm.getPriceForRedemption());
        console.log("Oracle address:", address(oraclelm));

        vm.prank(address(fundingManager));
        uint price = oraclelm.getPriceForIssuance();
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
        uint buyAmount
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
            orchestrator.authorizer().generateRoleId(
                address(fundingManager), "WHITELIST_ROLE"
            ),
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
        uint amount
    ) internal {
        // Enable selling functionality
        vm.startPrank(admin);
        fundingManager.openSell();

        // Ensure funding manager has enough tokens for redemption
        uint requiredAmount = amount * 2; // Double to account for fees
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
        uint amount
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