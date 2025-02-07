// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol"; // @todo remove console imports
import {IERC20Metadata} from
    "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Errors} from
    "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IOraclePrice_v1} from "@lm/interfaces/IOraclePrice_v1.sol";
import {IFM_PC_ExternalPrice_Redeeming_v1} from
    "@fm/oracle/interfaces/IFM_PC_ExternalPrice_Redeeming_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {ModuleTest} from "test/modules/ModuleTest.sol";
import {Clones} from "@oz/proxy/Clones.sol";
import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {OZErrors} from "test/utils/errors/OZErrors.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {
    BondingCurveBase_v1,
    IBondingCurveBase_v1
} from "@fm/bondingCurve/abstracts/BondingCurveBase_v1.sol";
import {RedeemingBondingCurveBase_v1} from
    "@fm/bondingCurve/abstracts/RedeemingBondingCurveBase_v1.sol";
import {ERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol";
import {LM_ManualExternalPriceSetter_v1} from
    "src/modules/logicModule/LM_ManualExternalPriceSetter_v1.sol";
import {OraclePrice_Mock} from
    "test/utils/mocks/modules/logicModules/OraclePrice_Mock.sol";
import {FM_PC_ExternalPrice_Redeeming_v1_Exposed} from
    "test/modules/fundingManager/oracle/FM_PC_ExternalPrice_Redeeming_v1_Exposed.sol";
import {
    IERC20PaymentClientBase_v1,
    ERC20PaymentClientBaseV1Mock,
    ERC20Mock
} from "test/utils/mocks/modules/paymentClient/ERC20PaymentClientBaseV1Mock.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";

import {RedeemingBondingCurveBaseV1Mock} from
    "test/modules/fundingManager/bondingCurve/utils/mocks/RedeemingBondingCurveBaseV1Mock.sol";
import {FM_BC_Tools} from "@fm/bondingCurve/FM_BC_Tools.sol";

// Tests and Mocks
import {ERC20Decimals_Mock} from "test/utils/mocks/ERC20Decimals_Mock.sol";

/**
 * @title FM_PC_ExternalPrice_Redeeming_v1_Test
 * @notice Test contract for FM_PC_ExternalPrice_Redeeming_v1
 */
contract FM_PC_ExternalPrice_Redeeming_v1_Test is ModuleTest {
    // ================================================================================
    // Constants
    
    // Token initial configuration
    string internal constant NAME = "Issuance Token";
    string internal constant SYMBOL = "IST";
    uint8 internal constant DECIMALS = 18;
    uint internal constant MAX_SUPPLY = type(uint).max;
    bytes32 constant WHITELIST_ROLE = "WHITELIST_ROLE";
    bytes32 constant ORACLE_ROLE = "ORACLE_ROLE";
    bytes32 constant QUEUE_MANAGER_ROLE = "QUEUE_MANAGER_ROLE";
    bytes32 constant QUEUE_EXECUTOR_ROLE = "QUEUE_EXECUTOR_ROLE";
    uint8 constant INTERNAL_DECIMALS = 18;
    uint constant BPS = 10_000; // Basis points (100%)

    // FM initial configuration
    uint constant DEFAULT_BUY_FEE = 100; // 1%
    uint constant DEFAULT_SELL_FEE = 100; // 1%
    uint constant MAX_BUY_FEE = 500; // 5%
    uint constant MAX_SELL_FEE = 500; // 5%
    bool constant DIRECT_OPERATIONS_ONLY = true;

    // ================================================================================
    // State

    // Contracts
    FM_PC_ExternalPrice_Redeeming_v1_Exposed fundingManager;
    ERC20Issuance_v1 issuanceToken;
    OraclePrice_Mock oracle;
    ERC20PaymentClientBaseV1Mock paymentClient;

    // Test addresses
    address projectTreasury;

    // ================================================================================
    // Setup

    function setUp() public {
        // Setup addresses
        projectTreasury = makeAddr("projectTreasury");

        // Create issuance token
        issuanceToken = new ERC20Issuance_v1(
            NAME, SYMBOL, DECIMALS, MAX_SUPPLY, address(this)
        );

        // Setup mock oracle
        address impl = address(new OraclePrice_Mock());
        oracle = OraclePrice_Mock(Clones.clone(impl));

        _setUpOrchestrator(oracle);
        // Init mock oracle. No role authorization required as it is a mock
        oracle.init(_orchestrator, _METADATA, "");

        // Prepare config data
        bytes memory configData = abi.encode(
            projectTreasury, // oracle address
            address(issuanceToken), // issuance token
            address(_token), // accepted token
            DEFAULT_BUY_FEE, // buy fee
            DEFAULT_SELL_FEE, // sell fee
            MAX_SELL_FEE, // max sell fee
            MAX_BUY_FEE, // max buy fee
            DIRECT_OPERATIONS_ONLY // direct operations only flag
        );

        // Setup funding manager
        impl = address(new FM_PC_ExternalPrice_Redeeming_v1_Exposed());
        fundingManager =
            FM_PC_ExternalPrice_Redeeming_v1_Exposed(Clones.clone(impl));
        _setUpOrchestrator(fundingManager);

        // Initialize the funding manager
        fundingManager.init(_orchestrator, _METADATA, configData);

        // Grant minting rights to the FM in issuance token
        issuanceToken.setMinter(address(fundingManager), true);
        // set oracle address in FM
        fundingManager.setOracleAddress(address(oracle));

        // Grant whitelist role to test contract
        fundingManager.grantModuleRole(
            fundingManager.getWhitelistRole(), address(this)
        );
        // Grant queue executor role to test contract
        fundingManager.grantModuleRole(
            fundingManager.getQueueExecutorRole(), address(this)
        );
    }

    // ================================================================================
    // Test Init

    // testInit(): This function tests all the getters
    function testInit() public override(ModuleTest) {
        assertEq(
            fundingManager.getProjectTreasury(),
            projectTreasury,
            "Project treasury not set correctly"
        );
        assertEq(
            fundingManager.getIssuanceToken(),
            address(issuanceToken),
            "Issuance token not set correctly"
        );
        assertEq(
            address(fundingManager.token()),
            address(_token),
            "Accepted token not set correctly"
        );
        assertEq(
            fundingManager.getBuyFee(),
            DEFAULT_BUY_FEE,
            "Buy fee not set correctly"
        );
        assertEq(
            fundingManager.getSellFee(),
            DEFAULT_SELL_FEE,
            "Sell fee not set correctly"
        );
        assertEq(
            fundingManager.getMaxProjectBuyFee(),
            MAX_BUY_FEE,
            "Max buy fee not set correctly"
        );
        assertEq(
            fundingManager.getMaxProjectSellFee(),
            MAX_SELL_FEE,
            "Max sell fee not set correctly"
        );
        assertEq(
            fundingManager.getIsDirectOperationsOnly(),
            DIRECT_OPERATIONS_ONLY,
            "Direct operations only flag not set correctly"
        );
    }

    /* testReinitFails()
        └── Given an initialized contract
            └── When trying to initialize again
                └── Then it should revert with InvalidInitialization
    */
    function testReinitFails() public override(ModuleTest) {
        bytes memory configData = abi.encode(
            address(projectTreasury), // treasury address
            address(issuanceToken), // issuance token
            address(_token), // accepted token
            DEFAULT_BUY_FEE, // buy fee
            DEFAULT_SELL_FEE, // sell fee
            MAX_SELL_FEE, // max sell fee
            MAX_BUY_FEE, // max buy fee
            DIRECT_OPERATIONS_ONLY // direct operations only flag
        );

        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        fundingManager.init(_orchestrator, _METADATA, configData);
    }

    // ================================================================================
    // Test External (public + external)
    
    /* Test: Function supportsInterface()
        └── Given different interface ids
            └── When the function supportsInterface() is called
                ├── Then it should return true for supported interfaces
                └── Then it should return false for unsupported interfaces
    */
    function testExternalSupportsInterface_worksGivenDifferentInterfaces() public {
        // Test - Verify supported interfaces
        assertTrue(
            fundingManager.supportsInterface(
                type(IFM_PC_ExternalPrice_Redeeming_v1).interfaceId
            ),
            "Should support IFM_PC_ExternalPrice_Redeeming_v1"
        );

        assertTrue(
            fundingManager.supportsInterface(
                type(IFundingManager_v1).interfaceId
            ),
            "Should support IFundingManager_v1"
        );

        assertTrue(
            fundingManager.supportsInterface(
                type(IERC165).interfaceId
            ),
            "Should support IERC165"
        );

        // Test - Verify unsupported interface
        bytes4 unsupportedInterfaceId = bytes4(keccak256("unsupported()"));
        assertFalse(
            fundingManager.supportsInterface(unsupportedInterfaceId),
            "Should not support random interface"
        );
    }

    /* Test: Function getWhitelistRole()
        └── Given we want to get the whitelist role
            └── When the function getWhitelistRole() is called
                └── Then it should return the correct whitelist role identifier
    */
    function testGetWhitelistRole_worksGivenWhitelistRoleRetrieved() public {
        // Test - Verify whitelist role
        bytes32 expectedRole = bytes32("WHITELIST_ROLE");
        assertEq(
            fundingManager.getWhitelistRole(),
            expectedRole,
            "Incorrect whitelist role identifier"
        );
    }

    /* Test: Function: getWhitelistRoleAdmin()
        └── Given we want to get the whitelist role admin
            └── When the function getWhitelistRoleAdmin() is called
                └── Then it should return the correct whitelist role admin identifier
    */
    function testGetWhitelistRoleAdmin_worksGivenWhitelistRoleAdminRetrieved() public {
        // Test - Verify whitelist role admin
        bytes32 expectedRole = bytes32("WHITELIST_ROLE_ADMIN");
        assertEq(
            fundingManager.getWhitelistRoleAdmin(),
            expectedRole,
            "Incorrect whitelist role admin identifier"
        );
    }

    /* Test: Function getQueueExecutorRole()
        └── Given we want to get the queue executor role
            └── When the function getQueueExecutorRole() is called
                └── Then it should return the correct queue executor role identifier
    */
    function testGetQueueExecutorRole_worksGivenQueueExecutorRoleRetrieved() public {
        // Test - Verify queue executor role
        bytes32 expectedRole = bytes32("QUEUE_EXECUTOR_ROLE");
        assertEq(
            fundingManager.getQueueExecutorRole(),
            expectedRole,
            "Incorrect queue executor role identifier"
        );
    }

    /* Test: Function getQueueExecutorRoleAdmin()
        └── Given we want to get the queue executor role admin
            └── When the function getQueueExecutorRoleAdmin() is called
                └── Then it should return the correct queue executor role admin identifier
    */
    function testGetQueueExecutorRoleAdmin_worksGivenQueueExecutorRoleAdminRetrieved() public {
        // Test - Verify queue executor role admin
        bytes32 expectedRole = bytes32("QUEUE_EXECUTOR_ROLE_ADMIN");
        assertEq(
            fundingManager.getQueueExecutorRoleAdmin(),
            expectedRole,
            "Incorrect queue executor role admin identifier"
        );
    }

    /* Test: Function getStaticPriceForBuying()
        ├── Given we want to get the static price for buying
            └── When the function getStaticPriceForBuying() is called
                └── Then it should return the correct static price for buying
    */
    function testGetStaticPriceForBuying_worksGivenStaticPriceForBuyingRetrieved() public {
        // Test - Verify static price for buying
        uint256 expectedPrice = 1e6;
        assertEq(
            fundingManager.getStaticPriceForBuying(),
            expectedPrice,
            "Incorrect static price for buying"
        );
    }

    /* Test: Function getStaticPriceForSelling()
        ├── Given we want to get the static price for selling
            └── When the function getStaticPriceForSelling() is called
                └── Then it should return the correct static price for selling
    */
    function testGetStaticPriceForSelling_worksGivenStaticPriceForSellingRetrieved() public {
        // Test - Verify static price for selling
        uint256 expectedPrice = 1e6;
        assertEq(
            fundingManager.getStaticPriceForSelling(),
            expectedPrice,
            "Incorrect static price for selling"
        );
    }

    /* Test: Function getOpenRedemptionAmount()
        └── Given multiple redemption orders are created
            └── When getOpenRedemptionAmount() is called
                └── Then it should return the total collateral amount pending redemption
    */
    function testGetOpenRedemptionAmount_worksGivenMultipleOrders() public {
        // Setup - Initial amount should be 0
        assertEq(
            fundingManager.getOpenRedemptionAmount(),
            0,
            "Initial open redemption amount should be 0"
        );

        // Setup - Create first order
        address receiver1_ = makeAddr("receiver1");
        uint depositAmount1_ = 1e18;
        uint collateralRedeemAmount1_ = 2e18;
        uint projectSellFeeAmount1_ = 1e17;

        fundingManager.exposed_createAndEmitOrder(
            receiver1_,
            depositAmount1_,
            collateralRedeemAmount1_,
            projectSellFeeAmount1_
        );

        // Test - Amount should be updated after first order
        assertEq(
            fundingManager.getOpenRedemptionAmount(),
            collateralRedeemAmount1_,
            "Open redemption amount should match first collateral amount"
        );

        // Setup - Create second order
        address receiver2_ = makeAddr("receiver2");
        uint depositAmount2_ = 2e18;
        uint collateralRedeemAmount2_ = 3e18;
        uint projectSellFeeAmount2_ = 2e17;

        fundingManager.exposed_createAndEmitOrder(
            receiver2_,
            depositAmount2_,
            collateralRedeemAmount2_,
            projectSellFeeAmount2_
        );

        // Test - Amount should be updated after second order
        assertEq(
            fundingManager.getOpenRedemptionAmount(),
            collateralRedeemAmount1_ + collateralRedeemAmount2_,
            "Open redemption amount should be sum of both collateral amounts"
        );
    }

    /* Test: Function getOrderId()
        └── Given a new order is created
            └── When getOrderId() is called
                └── Then it should return the correct order ID
    */
    function testGetOrderId_worksGivenNewOrderCreated() public {
        // Setup - Create first order
        address receiver1_ = makeAddr("receiver1");
        uint depositAmount1_ = 1e18;
        uint collateralRedeemAmount1_ = 2e18;
        uint projectSellFeeAmount1_ = 1e17;

        fundingManager.exposed_createAndEmitOrder(
            receiver1_,
            depositAmount1_,
            collateralRedeemAmount1_,
            projectSellFeeAmount1_
        );

        // Test - First order should have ID 1
        assertEq(
            fundingManager.getOrderId(),
            1,
            "First order should have ID 1"
        );

        // Setup - Create second order
        address receiver2_ = makeAddr("receiver2");
        uint depositAmount2_ = 2e18;
        uint collateralRedeemAmount2_ = 3e18;
        uint projectSellFeeAmount2_ = 2e17;

        fundingManager.exposed_createAndEmitOrder(
            receiver2_,
            depositAmount2_,
            collateralRedeemAmount2_,
            projectSellFeeAmount2_
        );

        // Test - Second order should have ID 2
        assertEq(
            fundingManager.getOrderId(),
            2,
            "Second order should have ID 2"
        );
    }

    /* Test: Function depositReserve()
        └── Given a valid amount of tokens to deposit
            └── When depositReserve() is called
                └── Then it should transfer tokens to the funding manager
                └── And emit a ReserveDeposited event
    */
    function testDepositReserve_worksGivenValidAmount(uint256 amount_) public {
        // Setup - Bound amount to reasonable values and ensure non-zero
        amount_ = bound(amount_, 1, 1000e18);
        
        // Setup - Fund test contract with tokens
        deal(address(_token), address(this), amount_);
        
        // Setup - Approve funding manager to spend tokens
        _token.approve(address(fundingManager), amount_);
        
        // Test - Record balances before deposit
        uint256 balanceBefore = _token.balanceOf(address(this));
        uint256 fmBalanceBefore = _token.balanceOf(address(fundingManager));
        
        // Test - Expect ReserveDeposited event
        vm.expectEmit(true, true, true, true);
        emit IFM_PC_ExternalPrice_Redeeming_v1.
        ReserveDeposited(address(this), amount_);
        
        // Test - Deposit reserve
        fundingManager.depositReserve(amount_);
        
        // Verify - Check balances after deposit
        assertEq(
            _token.balanceOf(address(this)),
            balanceBefore - amount_,
            "Sender balance not decreased correctly"
        );
        assertEq(
            _token.balanceOf(address(fundingManager)),
            fmBalanceBefore + amount_,
            "FM balance not increased correctly"
        );
    }

    /* Test: Function depositReserve()
        └── Given a zero amount
            └── When depositReserve() is called
                └── Then it should revert with InvalidAmount error
    */
    function testDepositReserve_revertGivenZeroAmount() public {
        // Test - Expect revert on zero amount
        vm.expectRevert(
            IFM_PC_ExternalPrice_Redeeming_v1
            .Module__FM_PC_ExternalPrice_Redeeming_InvalidAmount
            .selector
        );
        fundingManager.depositReserve(0);
    }

   /* Test: Function depositReserve()
        └── Given insufficient allowance
            └── When depositReserve() is called
                └── Then it should revert with ERC20InsufficientAllowance error
    */
    function testDepositReserve_revertGivenInsufficientAllowance() public {
        // Setup
        uint256 amount = 100e18;
        deal(address(_token), address(this), amount);
        
        // Test - Don't approve, expect ERC20InsufficientAllowance error
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(fundingManager),
                0,
                amount
            )
        );
        fundingManager.depositReserve(amount);
    }

    /* Test: Function buy()
        └── Given a user with WHITELIST_ROLE and buying is open
            └── When buy() is called with valid minAmountOut
                └── Then it should execute successfully
    */
    function testBuy_worksGivenWhitelistedUser() public {
        // Setup 
        uint256 amount_ = 1e18;
        deal(address(_token), address(this), amount_);
        _token.approve(address(fundingManager), amount_);
        
        // Setup - Open buy operations
        fundingManager.openBuy();
        
        // Setup - Calculate minimum amount out
        uint256 minAmountOut_ = fundingManager.calculatePurchaseReturn(amount_);
        
        // Test - Should not revert
        fundingManager.buy(amount_, minAmountOut_);
    }

    /* Test: Function buy()
        └── Given a user without WHITELIST_ROLE but buying is open
            └── When buy() is called with valid minAmountOut
                └── Then it should revert with Module__CallerNotAuthorized error
    */
    function testBuy_revertGivenNonWhitelistedUser() public {
        // Setup
        address nonWhitelisted_ = makeAddr("nonWhitelisted");
        uint256 amount_ = 1e18;
        deal(address(_token), nonWhitelisted_, amount_);
        
        // Setup - Open buy operations
        fundingManager.openBuy();
        
        // Setup - Calculate minimum amount out
        uint256 minAmountOut_ = fundingManager.calculatePurchaseReturn(amount_);

        vm.startPrank(nonWhitelisted_);
        vm.expectRevert();
        fundingManager.buy(amount_, minAmountOut_);
        vm.stopPrank();
    }

    /* Test: Function buyFor()
        └── Given a user with WHITELIST_ROLE and third party operations enabled
            └── When buyFor() is called
                └── Then it should execute successfully
    */
    function testBuyFor_worksGivenWhitelistedUserAndTPOEnabled() public {
        // Setup
        address receiver_ = makeAddr("receiver");
        uint256 amount_ = 1e18;
        deal(address(_token), address(this), amount_);
        _token.approve(address(fundingManager), amount_);
        
        // Setup - Open buy operations and enable TPO
        fundingManager.openBuy();
        fundingManager.exposed_setIsDirectOperationsOnly(false);
        
        // Setup - Calculate minimum amount out
        uint256 minAmountOut_ = fundingManager.calculatePurchaseReturn(amount_);
        
        // Test - Should not revert
        fundingManager.buyFor(receiver_, amount_, minAmountOut_);
    }

    /* Test: Function buyFor()
        └── Given a user without WHITELIST_ROLE but TPO enabled
            └── When buyFor() is called
                └── Then it should revert
    */
    function testBuyFor_revertGivenNonWhitelistedUserAndTPOEnabled() public {
        // Setup
        address nonWhitelisted_ = makeAddr("nonWhitelisted");
        address receiver_ = makeAddr("receiver");
        uint256 amount_ = 1e18;
        deal(address(_token), nonWhitelisted_, amount_);
        
        // Setup - Open buy operations
        fundingManager.openBuy();
        fundingManager.exposed_setIsDirectOperationsOnly(false);
        
        // Setup - Calculate minimum amount out
        uint256 minAmountOut_ = fundingManager.calculatePurchaseReturn(amount_);

        // Test - Switch to non-whitelisted user and expect revert
        vm.startPrank(nonWhitelisted_);
        vm.expectRevert();
        fundingManager.buyFor(receiver_, amount_, minAmountOut_);
        vm.stopPrank();
    }

    /* Test: Function buyFor()
        └── Given a whitelisted user but TPO disabled
            └── When buyFor() is called
                └── Then it should revert
    */
    function testBuyFor_revertGivenTPODisabled() public {
        // Setup
        address receiver_ = makeAddr("receiver");
        uint256 amount_ = 1e18;
        deal(address(_token), address(this), amount_);
        _token.approve(address(fundingManager), amount_);
        
        // Setup - Open buy operations but leave TPO disabled
        fundingManager.openBuy();
        
        // Setup - Calculate minimum amount out
        uint256 minAmountOut_ = fundingManager.calculatePurchaseReturn(amount_);
        
        // Test - Should revert as TPO is disabled
        vm.expectRevert();
        fundingManager.buyFor(receiver_, amount_, minAmountOut_);
    }

    // /* Test: Function sell()
    //     └── Given a user with WHITELIST_ROLE and selling is open
    //         └── When sell() is called
    //             └── Then it should execute successfully
    // */
    // function testSell_worksGivenWhitelistedUser() public {
    //     // Setup
    //     uint256 amount_ = 1e18;
    //     deal(address(_token), address(this), amount_);
    //     _token.approve(address(fundingManager), amount_);
        
    //     // Setup - Open buy operations
    //     fundingManager.openBuy();
        
    //     // Setup - Calculate minimum amount out
    //     uint256 minBuyAmountOut_ = fundingManager.calculatePurchaseReturn(amount_);
        
    //     // Test - Should not revert
    //     fundingManager.buy(amount_, minBuyAmountOut_);

    //     fundingManager.openSell();
        
    //     uint256 minSellAmountOut_ = fundingManager.calculateSaleReturn(minBuyAmountOut_);
        
    //     // Test - Should not revert - sell the tokens we received from buying
    //     fundingManager.sell(minBuyAmountOut_, minSellAmountOut_);
    // }

    // /* Test: Function sell()
    //     └── Given a user without WHITELIST_ROLE but selling is open
    //         └── When sell() is called
    //             └── Then it should revert
    // */
    // function testSell_revertGivenNonWhitelistedUser() public {
    //     // Setup
    //     address nonWhitelisted_ = makeAddr("nonWhitelisted");
    //     uint256 amount_ = 1e18;
    //     deal(address(_token), nonWhitelisted_, amount_);
        
    //     // Setup - Open sell operations
    //     fundingManager.openSell();
        
    //     // Setup - Calculate minimum amount out
    //     uint256 minAmountOut_ = fundingManager.calculateSaleReturn(amount_);

    //     // Test - Switch to non-whitelisted user and expect revert
    //     vm.startPrank(nonWhitelisted_);
    //     vm.expectRevert();
    //     fundingManager.sell(amount_, minAmountOut_);
    //     vm.stopPrank();
    // }

    // /* Test: Function transferOrchestratorToken()
    //     ├── Given caller is not the payment client
    //     │   └── When transferOrchestratorToken() is called
    //     │       └── Then it should revert
    //     */
    // function testTransferOrchestratorToken_revertGivenNonPaymentClient() public {
    //     // Setup
    //     address receiver_ = makeAddr("receiver");
    //     uint amount_ = 100;
        
    //     // Test - Should revert if not called by payment client
    //     vm.expectRevert(
    //         IModule_v1.Module__OnlyCallableByPaymentClient.selector
    //     );
    //     fundingManager.transferOrchestratorToken(receiver_, amount_);
    // }

    // /* Test: Function transferOrchestratorToken()
    //     ├── Given caller is the payment client
    //     │   └── When transferOrchestratorToken() is called
    //     │       ├── Then it should transfer the tokens
    //     │       └── And it should emit the TransferOrchestratorToken event
    //     */
    // function testTransferOrchestratorToken_worksGivenPaymentClient() public {
    //     // Setup
    //     address receiver_ = makeAddr("receiver");
    //     uint amount_ = 100;
        
    //     // Setup - Mint tokens to funding manager
    //     deal(address(_token), address(fundingManager), amount_);
        
    //     // Setup - Create and register payment client
    //     paymentClient = new ERC20PaymentClientBaseV1Mock();
        
    //     // Setup - Mock payment client call
    //     vm.startPrank(address(paymentClient));
        
    //     // Test - Expect event
    //     vm.expectEmit(true, true, true, true, address(fundingManager));
    //     emit IFundingManager_v1.TransferOrchestratorToken(receiver_, amount_);
        
    //     // Test - Transfer tokens
    //     fundingManager.transferOrchestratorToken(receiver_, amount_);
    //     vm.stopPrank();
        
    //     // Test - Verify balances
    //     assertEq(_token.balanceOf(receiver_), amount_);
    //     assertEq(_token.balanceOf(address(fundingManager)), 0);
    // }

    /* Test: Function amountPaid()
        └── Given a payment is made
            └── When amountPaid() is called by the payment processor
                └── Then it should update outstanding token amounts
                └── And emit PaymentOrderProcessed event
    */
    function testAmountPaid_worksGivenPaymentMade() public {
        // Setup - Create order to generate payment
        address receiver_ = makeAddr("receiver");
        uint depositAmount_ = 1e18;
        uint collateralRedeemAmount_ = 2e18;
        uint projectSellFeeAmount_ = 1e17;

        fundingManager.exposed_createAndEmitOrder(
            receiver_,
            depositAmount_,
            collateralRedeemAmount_,
            projectSellFeeAmount_
        );

        // Setup - Mock payment processor call
        vm.startPrank(address(_orchestrator.paymentProcessor()));

        // Test - Call amountPaid
        fundingManager.amountPaid(address(_token), collateralRedeemAmount_);

        // Test - Verify outstanding amount is reduced
        assertEq(
            fundingManager.outstandingTokenAmount(address(_token)),
            0,
            "Outstanding amount should be reduced"
        );

        vm.stopPrank();
    }

    /* Test: Function setSellFee()
        ├── Given the sell fee is 0
        │   └── When the function setSellFee() is called
        │       └── Then it should set the sell fee correctly
    */
    function testSetSellFee_worksGivenZeroSellFee() public {
        // Test
        fundingManager.setSellFee(0);
        
        // Test - Verify state
        assertEq(fundingManager.sellFee(), 0);
    }

    /* Test: Function setSellFee()
        ├── Given the sell fee is not 0
        │   └── When the function setSellFee() is called
        │       └── Then it should set the sell fee correctly
    */
    function testSetSellFee_worksGivenNonZeroSellFee() public {
        // Test
        fundingManager.setSellFee(100);
        
        // Test - Verify state
        assertEq(fundingManager.sellFee(), 100);
    }

    /* Test: Function setBuyFee()
        ├── Given the buy fee is not 0
        │   └── When the function setSellFee() is called
        │       └── Then it should set the sell fee correctly
    */
    function testSetBuyFee_worksGivenNonZeroBuyFee() public {
        // Test
        fundingManager.setBuyFee(100);
        
        // Test - Verify state
        assertEq(fundingManager.buyFee(), 100);
    }

    /* Test: Function setBuyFee()
        ├── Given the buy fee is 0
        │   └── When the function setSellFee() is called
        │       └── Then it should revert
    */
    function testSetBuyFee_worksGivenZeroBuyFee() public {
        // Test
        fundingManager.setBuyFee(0);
        
        // Test - Verify state
        assertEq(fundingManager.buyFee(), 0);
    }

    /* Test: Function setProjectTreasury()
        ├── Given the project treasury is a valid address
        │   └── When the function setProjectTreasury() is called
        │       └── Then it should set the project treasury correctly
    */
    function testSetProjectTreasury_worksGivenValidAddress(
        address projectTreasury_
    ) public {
        // Setup
        vm.assume(projectTreasury_ != address(0));

        // Test
        fundingManager.setProjectTreasury(projectTreasury_);

        // Test - Verify state
        assertEq(fundingManager.getProjectTreasury(), projectTreasury_);
    }

    /* Test: Function setOracleAddress()
        ├── Given the oracle supports the IOraclePrice_v1 interface
        │   └── When the function _setOracleAddress() is called
        │       └── Then it should set the oracle address correctly
        └── Given the oracle does not support the IOraclePrice_v1 interface
            └── When the function _setOracleAddress() is called
                └── Then it should revert
    */
    function testSetOracleAddress_worksGivenValidOracle(address _oracle) public {
        // Setup
        vm.assume(address(_oracle) != address(0));

        OraclePrice_Mock newOracle = new OraclePrice_Mock();

        // Test
        fundingManager.setOracleAddress(address(newOracle));

        // Assert
        assertEq(
            fundingManager.getOracle(),
            address(newOracle),
            "Oracle address not set correctly"
        );
    }

    /* Test: Function setIsDirectOperationsOnly()
        └── Given a valid value
            └── When the function exposed_setIsDirectOperationsOnly() is called
                └── Then the value should be set correctly
    */
    function testSetIsDirectOperationsOnly_worksGivenValidValue(
        bool _isDirectOperationsOnly
    ) public {
        // Test
        fundingManager.setIsDirectOperationsOnly(_isDirectOperationsOnly);
        
        // Test - Verify state
        assertEq(
            fundingManager.getIsDirectOperationsOnly(),
            _isDirectOperationsOnly,
            "Is direct operations only not set correctly"
        );
    }

    /* Test: Function executeRedemptionQueue()
        └── Given caller has QUEUE_EXECUTOR_ROLE
            └── And there are redemption orders in the queue
            └── When executeRedemptionQueue() is called
                └── Then it should call payment processor with correct parameters
                └── Then it should not revert
    */
    function testExecuteRedemptionQueue_worksGivenCallerHasQueueExecutorRole()
        public
    {
        // Setup - Create a redemption order
        address receiver_ = makeAddr("receiver");
        uint depositAmount_ = 1e18;
        uint collateralRedeemAmount_ = 2e18;
        uint projectSellFeeAmount_ = 1e17;

        // Setup - Create order
        fundingManager.exposed_createAndEmitOrder(
            receiver_,
            depositAmount_,
            collateralRedeemAmount_,
            projectSellFeeAmount_
        );

        // Execute
        fundingManager.executeRedemptionQueue();

        // Test - Verify payment processor was called
        assertEq(
            _paymentProcessor.processPaymentsTriggered(),
            1,
            "Payment processor should be triggered once"
        );
    }
    
    // ================================================================================
    // Test Internal

    /* Test: Function _setProjectTreasury()
        ├── Given the project treasury is the zero address
        │   └── When the function _setProjectTreasury() is called
        │       └── Then it should revert
        └── Given the project treasury is not the zero address
            └── When the function _setProjectTreasury() is called
                ├── Then it should set the project treasury correctly
                └── And it should emit an event
    */
    function testInternalSetProjectTreasury_revertGivenZeroAddress() public {
        // Test
        vm.expectRevert(
            abi.encodeWithSelector(
                IFM_PC_ExternalPrice_Redeeming_v1
                    .Module__FM_PC_ExternalPrice_Redeeming_InvalidProjectTreasury
                    .selector
            )
        );
        fundingManager.exposed_setProjectTreasury(address(0));
    }

    function testInternalSetProjectTreasury_worksGivenValidAddress(
        address projectTreasury_
    ) public {
        // Setup
        vm.assume(projectTreasury_ != address(0));

        // Test
        vm.expectEmit(true, true, true, true);
        emit IFM_PC_ExternalPrice_Redeeming_v1.ProjectTreasuryUpdated(
            projectTreasury, projectTreasury_
        );

        fundingManager.exposed_setProjectTreasury(projectTreasury_);

        // Assert
        assertEq(
            fundingManager.getProjectTreasury(),
            projectTreasury_,
            "Project treasury not set correctly"
        );
    }

    /* Test: Function _deductFromOpenRedemptionAmount()
        └── When the function _deductFromOpenRedemptionAmount() is called
            └── Then it should deduct the amount correctly
                └── And it should emit an event
    */
    function testInternalDeductFromOpenRedemptionAmount_worksGivenOpenRedemptionAmountUpdated(
        uint openRedemptionAmount_,
        uint amount_
    ) public {
        // Setup
        openRedemptionAmount_ = bound(openRedemptionAmount_, 1, type(uint).max);
        amount_ = bound(amount_, 1, openRedemptionAmount_);
        _setOpenRedemptionAmount(openRedemptionAmount_);

        // Test
        vm.expectEmit(true, true, true, true);
        emit IFM_PC_ExternalPrice_Redeeming_v1.RedemptionAmountUpdated(
            openRedemptionAmount_ - amount_
        );

        fundingManager.exposed_deductFromOpenRedemptionAmount(amount_);

        // Assert
        assertEq(
            fundingManager.getOpenRedemptionAmount(),
            openRedemptionAmount_ - amount_,
            "Open redemption amount not deducted correctly"
        );
    }

    /* Test: Function _addToOpenRedemptionAmount()
        └── When the function _addToOpenRedemptionAmount() is called
            └── Then it should add the amount correctly
                └── And it should emit an event
    */
    function testInternalAddToOpenRedemptionAmount_worksGivenOpenRedemptionAmountUpdated(
        uint openRedemptionAmount_,
        uint amount_
    ) public {
        // Setup
        openRedemptionAmount_ =
            bound(openRedemptionAmount_, 0, type(uint).max - 2);
        amount_ = bound(amount_, 1, type(uint).max - openRedemptionAmount_);
        _setOpenRedemptionAmount(openRedemptionAmount_);

        // Test
        vm.expectEmit(true, true, true, true);
        emit IFM_PC_ExternalPrice_Redeeming_v1.RedemptionAmountUpdated(
            openRedemptionAmount_ + amount_
        );

        fundingManager.exposed_addToOpenRedemptionAmount(amount_);

        // Assert
        assertEq(
            fundingManager.getOpenRedemptionAmount(),
            openRedemptionAmount_ + amount_,
            "Open redemption amount not added correctly"
        );
    }

    /* Test: Function _setOracleAddress()
        ├── Given the oracle does not support the IOraclePrice_v1 interface
        │   └── When the function _setOracleAddress() is called
        │       └── Then it should revert
        └── Given the oracle supports the IOraclePrice_v1 interface
            └── When the function _setOracleAddress() is called
                └── Then it should set the oracle address correctly
                    └── And it should emit an event
    */
    function testInternalSetOracleAddress_revertGivenOracleDoesNotSupportInterface(
        address invalidOracle_
    ) public {
        // If no supportInterface is implemented, it reverts without the custom
        // error message.
        vm.expectRevert();

        fundingManager.exposed_setOracleAddress(invalidOracle_);
    }

    function testInternalSetOracleAddress_worksGivenOracleSupportsInterface()
        public
    {
        // Setup
        OraclePrice_Mock newOracle = new OraclePrice_Mock();
        address currentOracle = fundingManager.getOracle();

        // Test
        vm.expectEmit(true, true, true, true);
        emit IFM_PC_ExternalPrice_Redeeming_v1.OracleUpdated(
            currentOracle, address(newOracle)
        );

        fundingManager.exposed_setOracleAddress(address(newOracle));

        // Assert
        assertEq(
            fundingManager.getOracle(),
            address(newOracle),
            "Oracle address not set correctly"
        );
        assertNotEq(
            fundingManager.getOracle(),
            currentOracle,
            "Oracle address not updated correctly"
        );
    }

    /* Test: Function _handleCollateralTokensBeforeBuy()
        └── When the function _handleCollateralTokensBeforeBuy() is called
            └── Then it should mint tokens to the recipient
    */
    function testInternalHandleCollateralTokensBeforeBuy_worksGivenMintedTokens(
        address recipient_,
        uint amount_
    ) public {
        // Setup
        vm.assume(recipient_ != address(0));
        vm.assume(amount_ > 0);
        _prepareBuyConditions(recipient_, amount_);

        // Assert
        assertEq(
            _token.balanceOf(recipient_),
            amount_,
            "Recipient should the right amount of tokens"
        );
        assertEq(
            _token.balanceOf(projectTreasury),
            0,
            "Project treasury should not have any tokens"
        );

        // Test
        fundingManager.exposed_handleCollateralTokensBeforeBuy(
            recipient_, amount_
        );

        // Assert
        assertEq(
            _token.balanceOf(recipient_),
            0,
            "Tokens should be transferred to the project treasury"
        );
        assertEq(
            _token.balanceOf(projectTreasury),
            amount_,
            "Project treasury should have the right amount of tokens"
        );
    }

    /* Test: Function _handleIssuanceTokensAfterBuy()
        └── When the function _handleIssuanceTokensAfterBuy() is called
            └── Then it should mint tokens to the recipient
    */
    function testInternalHandleIssuanceTokensAfterBuy_worksGivenMintedTokens(
        address recipient_,
        uint amount_
    ) public {
        // Setup
        vm.assume(recipient_ != address(0));
        vm.assume(amount_ > 0);

        // Assert
        assertEq(
            issuanceToken.balanceOf(recipient_),
            0,
            "Recipient should not have any tokens"
        );

        // Test
        fundingManager.exposed_handleIssuanceTokensAfterBuy(recipient_, amount_);

        // Assert
        assertEq(
            issuanceToken.balanceOf(recipient_),
            amount_,
            "Recipient should have the right amount of tokens"
        );
    }

    /* Test: Function _setIssuanceToken()
        └── When the function _setIssuanceToken() is called
            └── Then it should set the issuance token correctly
                └── And it should emit an event with the right decimals
    */

    function testInternalSetIssuanceToken_worksGivenValidToken(uint8 decimals_)
        public
    {
        // Setup
        vm.assume(decimals_ > 0);
        ERC20Issuance_v1 newIssuanceToken = new ERC20Issuance_v1(
            "New Issuance Token", "NIT", decimals_, MAX_SUPPLY, address(this)
        );

        // Assert
        assertEq(
            fundingManager.getIssuanceToken(),
            address(issuanceToken),
            "Issuance token not set correctly during initialization"
        );

        // Test
        vm.expectEmit(true, true, true, true);
        emit IBondingCurveBase_v1.IssuanceTokenSet(
            address(newIssuanceToken), decimals_
        );

        fundingManager.exposed_setIssuanceToken(address(newIssuanceToken));

        // Assert
        assertEq(
            fundingManager.getIssuanceToken(),
            address(newIssuanceToken),
            "Issuance token not set correctly"
        );
    }

    /* Test: Function _redeemTokensFormulaWrapper()
        └── Given the amount is bigger than 0
            └── When the function _redeemTokensFormulaWrapper() is called
                └── Then it should return the correct amount of redeemable collateral tokens
    */
    function testInternalRedeemTokensFormulaWrapper_worksGivenValidAmount(
        uint amount_,
        uint8 issuanceTokenDecimals_,
        uint8 collateralTokenDecimals_
    ) public {
        // Setup
        amount_ = bound(amount_, 1, type(uint64).max);
        issuanceTokenDecimals_ = uint8(bound(issuanceTokenDecimals_, 1, 18));
        collateralTokenDecimals_ = uint8(bound(collateralTokenDecimals_, 1, 18));
        // Convert amount to issuance token decimals
        amount_ = amount_ * 10 ** issuanceTokenDecimals_;

        FM_PC_ExternalPrice_Redeeming_v1_Exposed newFundingManager =
        FM_PC_ExternalPrice_Redeeming_v1_Exposed(
            _initializeFundingManagerWithDifferentTokenDecimals(
                issuanceTokenDecimals_, collateralTokenDecimals_
            )
        );

        // Set oracle address and price
        newFundingManager.setOracleAddress(address(oracle));
        uint oraclePrice = 10 ** collateralTokenDecimals_;
        oracle.setRedemptionPrice(oraclePrice);

        // Prepare deposit amount (scaled to issuance decimals)
        uint depositAmount = amount_ * 10 ** issuanceTokenDecimals_;

        // Test
        uint actualRedeemAmount = newFundingManager
            .exposed_redeemTokensFormulaWrapper(depositAmount);

        // Calculate expected amount manually following the formula:
        // 1. Convert to collateral decimals
        uint collateralTokenDecimalConvertedAmount = FM_BC_Tools
            ._convertAmountToRequiredDecimal(
            depositAmount, issuanceTokenDecimals_, collateralTokenDecimals_
        );

        // 2. Apply oracle price and final division
        uint expectedAmount = (collateralTokenDecimalConvertedAmount * oraclePrice) / 
            10 ** collateralTokenDecimals_;

        // Assert - Verify calculation matches expected
        assertEq(
            actualRedeemAmount,
            expectedAmount,
            "Redeem amount calculation incorrect"
        );        
    }

    /* Test: Function testInternalIssueTokensFormulaWrapper_worksGivenValidAmount()
        └── Given a valid amount
            └── When the function exposed_issueTokensFormulaWrapper() is called
                └── Then the amount should be correctly calculated 
    */
    function testInternalIssueTokensFormulaWrapper_worksGivenValidAmount(
        uint amount_,
        uint8 issuanceTokenDecimals_,
        uint8 collateralTokenDecimals_
    ) public {
        // Setup - Bound inputs to prevent overflow
        amount_ = bound(amount_, 1, type(uint64).max);
        issuanceTokenDecimals_ = uint8(bound(issuanceTokenDecimals_, 1, 18));
        collateralTokenDecimals_ = uint8(bound(collateralTokenDecimals_, 1, 18));
        
        FM_PC_ExternalPrice_Redeeming_v1_Exposed newFundingManager =
            FM_PC_ExternalPrice_Redeeming_v1_Exposed(
            _initializeFundingManagerWithDifferentTokenDecimals(
                issuanceTokenDecimals_, collateralTokenDecimals_
            )
        );

        // Set oracle address and price
        newFundingManager.setOracleAddress(address(oracle));
        uint oraclePrice = 10 ** collateralTokenDecimals_;
        oracle.setIssuancePrice(oraclePrice);

        // Scale amount to issuance decimals
        uint scaledAmount = amount_ * 10 ** issuanceTokenDecimals_;

        // Test
        uint actualIssueAmount = newFundingManager
            .exposed_issueTokensFormulaWrapper(scaledAmount);

        // Calculate expected amount manually following the formula:
        // 1. Calculate initial mint amount with oracle price
        uint initialMintAmount = (oraclePrice * scaledAmount) / 
            10 ** collateralTokenDecimals_;

        // 2. Convert to issuance token decimals
        uint expectedAmount = FM_BC_Tools._convertAmountToRequiredDecimal(
            initialMintAmount,
            collateralTokenDecimals_,
            issuanceTokenDecimals_
        );

        // Assert - Verify calculation matches expected
        assertEq(
            actualIssueAmount,
            expectedAmount,
            "Issue amount calculation incorrect"
        );
    }

    /* Test: Function _setIsDirectOperationsOnly()
        └── Given a valid value
            └── When the function exposed_setIsDirectOperationsOnly() is called
                └── Then the value should be set correctly
    */
    function testInternalSetIsDirectOperationsOnly_worksGivenValidValue(
        bool isDirect_
    ) public {
        // Test
        fundingManager.exposed_setIsDirectOperationsOnly(isDirect_);

        // Assert
        assertEq(
            fundingManager.getIsDirectOperationsOnly(),
            isDirect_,
            "IsDirect not set correctly"
        );
    }

    /* Test: Function _setMaxProjectBuyFee()
        └── Given a valid fee
            └── When the function exposed_setMaxProjectBuyFee() is called
                └── Then the fee should be set correctly
    */
    function testInternalSetMaxProjectBuyFee_worksGivenValidFee(uint fee_)
        public
    {
        // Setup
        fee_ = bound(fee_, fundingManager.getBuyFee(), type(uint128).max);

        // Test
        fundingManager.exposed_setMaxProjectBuyFee(fee_);

        // Assert
        assertEq(
            fundingManager.getMaxProjectBuyFee(), fee_, "Fee not set correctly"
        );
    }

    /* Test: Function _setBuyFee()
        └── Given a fee below current buy fee
            └── When the function exposed_setMaxProjectBuyFee() is called
                └── Then it should revert with Module__BondingCurveBase__InvalidMaxFee
    */
    function testInternalSetMaxProjectBuyFee_revertGivenFeeBelowCurrentBuyFee()
        public
    {
        // Setup
        uint currentBuyFee_ = 500; // 5%
        uint maxFee_ = 400; // 4%

        // Set current buy fee
        fundingManager.exposed_setBuyFee(currentBuyFee_);

        // Test
        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__FM_PC_ExternalPrice_Redeeming_InvalidMaxFee()"
            )
        );
        fundingManager.exposed_setMaxProjectBuyFee(maxFee_);
    }

    /* Test: Function _setMaxProjectSellFee()
        └── Given a valid fee
            └── When the function exposed_setMaxProjectSellFee() is called
                └── Then the fee should be set correctly
    */
    function testInternalSetMaxProjectSellFee_worksGivenValidFee(uint fee_)
        public
    {
        // Setup
        fee_ = bound(fee_, 1, fundingManager.getMaxProjectSellFee());

        // Test
        fundingManager.exposed_setMaxProjectSellFee(fee_);

        // Assert
        assertEq(
            fundingManager.getMaxProjectSellFee(), fee_, "Fee not set correctly"
        );
    }

    /* Test: Function _setBuyFee()
        └── Given a valid fee
            └── When the function exposed_setBuyFee() is called
                └── Then the fee should be set correctly
    */
    function testInternalSetBuyFee_worksGivenValidFee(uint fee_) public {
        // Setup
        fee_ = bound(fee_, 1, fundingManager.getMaxProjectBuyFee());

        // Test
        fundingManager.exposed_setBuyFee(fee_);

        // Assert
        assertEq(fundingManager.getBuyFee(), fee_, "Fee not set correctly");
    }

    /* Test: Function _setMaxProjectBuyFee()
        └── Given a fee above max project buy fee
            └── When the function exposed_setBuyFee() is called
                └── Then it should revert with Module__FM_PC_ExternalPrice_Redeeming_FeeExceedsMaximum
    */
    function testInternalSetBuyFee_revertGivenFeeAboveMaxProjectBuyFee()
        public
    {
        // Setup
        uint maxFee_ = 400;
        uint fee_ = maxFee_ + 1;

        fundingManager.exposed_setMaxProjectBuyFee(maxFee_);

        // Test
        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__FM_PC_ExternalPrice_Redeeming_FeeExceedsMaximum(uint256,uint256)",
                fee_,
                maxFee_
            )
        );
        fundingManager.exposed_setBuyFee(fee_);
    }

    /* Test: Function _setSellFee()
        └── Given a valid fee
            └── When the function exposed_setSellFee() is called
                └── Then the fee should be set correctly
    */
    function testInternalSetSellFee_worksGivenValidFee(uint fee_) public {
        // Setup
        fee_ = bound(fee_, 1, fundingManager.getMaxProjectSellFee());

        // Test
        fundingManager.exposed_setSellFee(fee_);

        // Assert
        assertEq(fundingManager.getSellFee(), fee_, "Fee not set correctly");
    }

    /* Test: Function _projectFeeCollected()
        └── Given a valid project fee amount
            └── When the function exposed_projectFeeCollected() is called
                └── Then it should emit ProjectCollateralFeeAdded event with correct amount
    */
    function testInternalProjectFeeCollected_worksGivenValidAmount(
        uint projectFeeAmount_
    ) public {
        // Setup - Bound inputs to prevent overflow
        projectFeeAmount_ = bound(projectFeeAmount_, 0, type(uint128).max);

        // Test - Expect event emission
        vm.expectEmit(true, true, true, true);
        emit IBondingCurveBase_v1.ProjectCollateralFeeAdded(projectFeeAmount_);

        // Execute
        fundingManager.exposed_projectFeeCollected(projectFeeAmount_);
    }

    /* Test: Function _createAndEmitOrder()
        └── Given valid parameters
            └── When the function exposed_createAndEmitOrder() is called
                └── Then it should emit OrderCreated event with correct parameters
                └── Then the open redemption amount should be set correctly
    */
    function testInternalCreateAndEmitOrder_worksGivenValidParameters(
        uint depositAmount_,
        uint collateralRedeemAmount_,
        uint projectSellFeeAmount_
    ) public {
        // Setup
        address receiver_ = makeAddr("receiver");
        
        // Setup - Bound inputs to prevent overflow
        depositAmount_ = bound(depositAmount_, 1, type(uint64).max);
        collateralRedeemAmount_ = bound(collateralRedeemAmount_, 1, type(uint64).max);
        projectSellFeeAmount_ = bound(projectSellFeeAmount_, 0, collateralRedeemAmount_);

        // Setup - Get current values
        uint exchangeRate_ = oracle.getPriceForRedemption();
        uint sellFee_ = fundingManager.getSellFee();
        
        // Test - Expect event emission
        vm.expectEmit(true, true, true, true, address(fundingManager));
        emit IFM_PC_ExternalPrice_Redeeming_v1.RedemptionOrderCreated(
            address(fundingManager), // paymentClient_
            1,                      // orderId_ (first order)
            address(this),           // seller_
            receiver_,              // receiver_
            depositAmount_,         // sellAmount_
            exchangeRate_,          // exchangeRate_
            sellFee_,              // feePercentage_
            projectSellFeeAmount_, // feeAmount_
            collateralRedeemAmount_, // finalRedemptionAmount_
            address(_token),        // collateralToken_
            IFM_PC_ExternalPrice_Redeeming_v1.RedemptionState.PENDING // state_
        );

        // Execute
        fundingManager.exposed_createAndEmitOrder(
            receiver_,
            depositAmount_,
            collateralRedeemAmount_,
            projectSellFeeAmount_
        );

        // Assert
        assertEq(
            fundingManager.getOpenRedemptionAmount(),
            collateralRedeemAmount_,
            "Open redemption amount not set correctly"
        );
    }

    // /* Test: Function  oracle configuration and validation
    //     ├── Given a valid oracle implementation
    //     │   └── When checking oracle interface and prices
    //     │       ├── Then should support IOraclePrice_v1 interface
    //     │       └── Then should return correct issuance and redemption prices
    //     ├── Given an invalid oracle address
    //     │   └── When initializing contract
    //     │       └── Then initialization should revert
    // */
    // function testExternalInit_succeedsGivenValidOracleAndRevertsGivenInvalidOracle(
    // ) public {
    //     // Verify valid oracle interface
    //     assertTrue(
    //         ERC165(address(oracle)).supportsInterface(
    //             type(IOraclePrice_v1).interfaceId
    //         ),
    //         "Mock oracle should support IOraclePrice_v1 interface"
    //     );

    //     // Verify oracle price reporting
    //     oracle.setIssuancePrice(2e18); // 2:1 ratio
    //     oracle.setRedemptionPrice(1.9e18); // 1.9:1 ratio

    //     assertEq(
    //         oracle.getPriceForIssuance(),
    //         2e18,
    //         "Oracle issuance price not set correctly"
    //     );
    //     assertEq(
    //         oracle.getPriceForRedemption(),
    //         1.9e18,
    //         "Oracle redemption price not set correctly"
    //     );

    //     // Test initialization with invalid oracle
    //     bytes memory invalidConfigData = abi.encode(
    //         address(_token), // invalid oracle address
    //         address(issuanceToken), // issuance token
    //         address(_token), // accepted token
    //         DEFAULT_BUY_FEE, // buy fee
    //         DEFAULT_SELL_FEE, // sell fee
    //         MAX_SELL_FEE, // max sell fee
    //         MAX_BUY_FEE, // max buy fee
    //         DIRECT_OPERATIONS_ONLY // direct operations only flag
    //     );

    //     vm.expectRevert();
    //     fundingManager.init(_orchestrator, _METADATA, invalidConfigData);
    // }

    // /* Test initialization with invalid oracle interface
    //     ├── Given a mock contract that doesn't implement IOraclePrice_v1
    //     │   └── And a new funding manager instance
    //     │       └── When initializing with invalid oracle
    //     │           └── Then should revert with InvalidInitialization error
    // */
    // function testExternalInit_revertsGivenOracleWithoutRequiredInterface()
    //     public
    // {
    //     // Create mock without IOraclePrice_v1 interface
    //     address invalidOracle = makeAddr("InvalidOracleMock");

    //     // Deploy new funding manager
    //     address impl = address(new FM_PC_ExternalPrice_Redeeming_v1_Exposed());
    //     FM_PC_ExternalPrice_Redeeming_v1_Exposed invalidOracleFM =
    //         FM_PC_ExternalPrice_Redeeming_v1_Exposed(Clones.clone(impl));

    //     // Prepare config with invalid oracle
    //     bytes memory configData = abi.encode(
    //         address(invalidOracle), // invalid oracle address
    //         address(issuanceToken), // issuance token
    //         address(_token), // accepted token
    //         DEFAULT_BUY_FEE, // buy fee
    //         DEFAULT_SELL_FEE, // sell fee
    //         MAX_SELL_FEE, // max sell fee
    //         MAX_BUY_FEE, // max buy fee
    //         DIRECT_OPERATIONS_ONLY // direct operations only flag
    //     );

    //     // Setup orchestrator
    //     _setUpOrchestrator(invalidOracleFM);

    //     // Verify revert on initialization
    //     vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
    //     fundingManager.init(_orchestrator, _METADATA, configData);
    // }

    // /* Test token decimals validation
    //     ├── Given an initialized contract with ERC20 tokens
    //     │   └── When checking token decimals
    //     │       ├── Then issuance token should have exactly 18 decimals
    //     │       └── Then collateral token should have exactly 18 decimals
    // */
    // function testExternalInit_succeedsGivenTokensWithCorrectDecimals() public {
    //     assertEq(
    //         IERC20Metadata(address(issuanceToken)).decimals(),
    //         18,
    //         "Issuance token should have 18 decimals"
    //     );
    //     assertEq(
    //         IERC20Metadata(address(_token)).decimals(),
    //         18,
    //         "Collateral token should have 18 decimals"
    //     );
    // }

    // // ═══════════════════════════════════════════════════════════════════════════════════════════════════════
    // // Fee Management
    // // ═══════════════════════════════════════════════════════════════════════════════════════════════════════

    // /* Test fee limits enforcement
    //     ├── Given a funding manager initialized with default fees
    //     │   ├── When setBuyFee is called with fee > MAX_BUY_FEE
    //     │   │   └── Then should revert with FeeExceedsMaximum(invalidFee, MAX_BUY_FEE)
    //     │   └── When setSellFee is called with fee > MAX_SELL_FEE
    //     │       └── Then should revert with FeeExceedsMaximum(invalidFee, MAX_SELL_FEE)
    // */
    // function testExternalSetFees_revertGivenFeesExceedingMaximum() public {
    //     // Verify buy fee limit
    //     uint invalidBuyFee = MAX_BUY_FEE + 1;
    //     vm.expectRevert(
    //         abi.encodeWithSelector(
    //             IFM_PC_ExternalPrice_Redeeming_v1
    //                 .Module__FM_PC_ExternalPrice_Redeeming_FeeExceedsMaximum
    //                 .selector,
    //             MAX_BUY_FEE + 1,
    //             MAX_BUY_FEE
    //         )
    //     );
    //     fundingManager.setBuyFee(invalidBuyFee);

    //     // Verify sell fee limit
    //     uint invalidSellFee = MAX_SELL_FEE + 1;
    //     vm.expectRevert(
    //         abi.encodeWithSelector(
    //             IFM_PC_ExternalPrice_Redeeming_v1
    //                 .Module__FM_PC_ExternalPrice_Redeeming_FeeExceedsMaximum
    //                 .selector,
    //             MAX_SELL_FEE + 1,
    //             MAX_SELL_FEE
    //         )
    //     );
    //     fundingManager.setSellFee(invalidSellFee);
    // }

    // /* Test buy fee update authorization and validation
    //     ├── Given an initialized funding manager and valid fee value
    //     │   ├── When non-admin calls setBuyFee
    //     │   │   └── Then reverts with unauthorized error
    //     │   └── When admin calls setBuyFee
    //     │       └── Then buyFee state and getter return new value
    // */
    // function testExternalSetBuyFee_succeedsGivenAdminAndValidFee(uint newBuyFee)
    //     public
    // {
    //     // Bound fee to valid range
    //     newBuyFee = bound(newBuyFee, 0, MAX_BUY_FEE);

    //     // Verify non-admin cannot set fee
    //     vm.prank(user);
    //     vm.expectRevert();
    //     fundingManager.setBuyFee(newBuyFee);

    //     // Update fee as admin

    //     fundingManager.setBuyFee(newBuyFee);

    //     // Verify fee updated in state
    //     assertEq(
    //         BondingCurveBase_v1(address(fundingManager)).buyFee(),
    //         newBuyFee,
    //         "Buy fee state variable not updated correctly"
    //     );

    //     // Verify fee getter
    //     assertEq(
    //         fundingManager.getBuyFee(),
    //         newBuyFee,
    //         "Buy fee getter not returning correct value"
    //     );
    // }

    // /* Test sell fee update authorization and validation
    //     ├── Given an initialized funding manager and valid fee value
    //     │   ├── When non-admin calls setSellFee
    //     │   │   └── Then reverts with unauthorized error
    //     │   └── When admin calls setSellFee
    //     │       └── Then sellFee state and getter return new value
    // */
    // function testExternalSetSellFee_succeedsGivenAdminAndValidFee(
    //     uint newSellFee
    // ) public {
    //     // Bound fee to valid range
    //     newSellFee = bound(newSellFee, 0, MAX_SELL_FEE);

    //     // Verify non-admin cannot set fee
    //     vm.prank(user);
    //     vm.expectRevert();
    //     fundingManager.setSellFee(newSellFee);

    //     // Update fee as admin

    //     fundingManager.setSellFee(newSellFee);

    //     // Verify fee updated in state
    //     assertEq(
    //         RedeemingBondingCurveBase_v1(address(fundingManager)).sellFee(),
    //         newSellFee,
    //         "Sell fee state variable not updated correctly"
    //     );

    //     // Verify fee getter
    //     assertEq(
    //         fundingManager.getSellFee(),
    //         newSellFee,
    //         "Sell fee getter not returning correct value"
    //     );
    // }

    // /* Test fee update permissions for different roles
    //     ├── Given initialized funding manager and valid fee values
    //     │   ├── When whitelisted user calls setBuyFee and setSellFee
    //     │   │   └── Then both calls revert with unauthorized error
    //     │   ├── When regular user calls setBuyFee and setSellFee
    //     │   │   └── Then both calls revert with unauthorized error
    //     │   └── When admin calls setBuyFee and setSellFee
    //     │       └── Then fees are updated successfully
    // */
    // function testExternalSetFees_succeedsOnlyForAdmin(
    //     uint newBuyFee,
    //     uint newSellFee
    // ) public {
    //     // Bound fees to valid ranges
    //     newBuyFee = bound(newBuyFee, 0, MAX_BUY_FEE);
    //     newSellFee = bound(newSellFee, 0, MAX_SELL_FEE);

    //     // Verify whitelisted user cannot set fees

    //     vm.expectRevert();
    //     fundingManager.setBuyFee(newBuyFee);
    //     vm.expectRevert();
    //     fundingManager.setSellFee(newSellFee);
    //     vm.stopPrank();

    //     // Verify regular user cannot set fees

    //     vm.expectRevert();
    //     fundingManager.setBuyFee(newBuyFee);
    //     vm.expectRevert();
    //     fundingManager.setSellFee(newSellFee);
    //     vm.stopPrank();

    //     // Verify admin can set fees

    //     fundingManager.setBuyFee(newBuyFee);
    //     assertEq(
    //         fundingManager.getBuyFee(),
    //         newBuyFee,
    //         "Admin should be able to update buy fee"
    //     );

    //     fundingManager.setSellFee(newSellFee);
    //     assertEq(
    //         fundingManager.getSellFee(),
    //         newSellFee,
    //         "Admin should be able to update sell fee"
    //     );

    //     vm.stopPrank();
    // }

    // /* Test sequential fee updates validation
    //     ├── Given initialized funding manager and admin role
    //     │   ├── When admin performs three sequential buy fee updates
    //     │   │   └── Then getBuyFee returns the latest set value after each update
    //     │   └── When admin performs three sequential sell fee updates
    //     │       └── Then getSellFee returns the latest set value after each update
    // */
    // function testExternalSetFees_succeedsWithSequentialUpdates(
    //     uint fee1,
    //     uint fee2,
    //     uint fee3
    // ) public {
    //     // Sequential buy fee updates
    //     fee1 = bound(fee1, 0, MAX_BUY_FEE);
    //     fee2 = bound(fee2, 0, MAX_BUY_FEE);
    //     fee3 = bound(fee3, 0, MAX_BUY_FEE);

    //     fundingManager.setBuyFee(fee1);
    //     assertEq(
    //         fundingManager.getBuyFee(),
    //         fee1,
    //         "Buy fee not updated correctly in first update"
    //     );

    //     fundingManager.setBuyFee(fee2);
    //     assertEq(
    //         fundingManager.getBuyFee(),
    //         fee2,
    //         "Buy fee not updated correctly in second update"
    //     );

    //     fundingManager.setBuyFee(fee3);
    //     assertEq(
    //         fundingManager.getBuyFee(),
    //         fee3,
    //         "Buy fee not updated correctly in third update"
    //     );

    //     // Sequential sell fee updates
    //     fee1 = bound(fee1, 0, MAX_SELL_FEE);
    //     fee2 = bound(fee2, 0, MAX_SELL_FEE);
    //     fee3 = bound(fee3, 0, MAX_SELL_FEE);

    //     fundingManager.setSellFee(fee1);
    //     assertEq(
    //         fundingManager.getSellFee(),
    //         fee1,
    //         "Sell fee not updated correctly in first update"
    //     );

    //     fundingManager.setSellFee(fee2);
    //     assertEq(
    //         fundingManager.getSellFee(),
    //         fee2,
    //         "Sell fee not updated correctly in second update"
    //     );

    //     fundingManager.setSellFee(fee3);
    //     assertEq(
    //         fundingManager.getSellFee(),
    //         fee3,
    //         "Sell fee not updated correctly in third update"
    //     );

    //     vm.stopPrank();
    // }

    // // ═══════════════════════════════════════════════════════════════════════════════════════════════════════
    // // Buy Operations
    // // ═══════════════════════════════════════════════════════════════════════════════════════════════════════

    // /* Test testExternalBuy_succeedsGivenWhitelistedUserAndValidAmount() function
    //     ├── Given an initialized funding manager contract with sufficient collateral
    //     │   └── And a whitelisted user
    //     │       ├── When the user buys tokens with a valid amount
    //     │       │   ├── Then the buy fee should be calculated correctly
    //     │       │   ├── Then the collateral tokens should be transferred to project treasury
    //     │       │   └── Then the issued tokens should be minted to user
    //     │       └── When checking final balances
    //     │           ├── Then user should have correct issued token balance
    //     │           ├── Then user should have correct collateral token balance
    //     │           └── Then project treasury should have correct collateral token balance
    // */
    // function testExternalBuy_succeedsGivenWhitelistedUserAndValidAmount(
    //     uint buyAmount
    // ) public {
    //     // Given - Bound the buy amount to reasonable values
    //     uint minAmount = 1 * 10 ** _token.decimals();
    //     uint maxAmount = 1_000_000 * 10 ** _token.decimals();
    //     buyAmount = bound(buyAmount, minAmount, maxAmount);

    //     // Calculate expected issuance tokens using helper
    //     uint expectedIssuedTokens = _calculateExpectedIssuance(buyAmount);

    //     // Setup buying conditions using helper
    //     _prepareBuyConditions(whitelisted, buyAmount);

    //     // Record initial balances
    //     uint initialUserCollateral = _token.balanceOf(whitelisted);
    //     uint initialProjectTreasuryCollateral =
    //         _token.balanceOf(fundingManager.getProjectTreasury());
    //     uint initialUserIssuedTokens = issuanceToken.balanceOf(whitelisted);

    //     // Execute buy operation

    //     _token.approve(address(fundingManager), buyAmount);
    //     fundingManager.buy(buyAmount, expectedIssuedTokens);
    //     vm.stopPrank();

    //     // Verify user's collateral token balance decreased correctly
    //     assertEq(
    //         _token.balanceOf(whitelisted),
    //         initialUserCollateral - buyAmount,
    //         "User collateral balance incorrect"
    //     );

    //     // Verify project treasury received the collateral
    //     assertEq(
    //         _token.balanceOf(fundingManager.getProjectTreasury()),
    //         initialProjectTreasuryCollateral + buyAmount,
    //         "Project treasury collateral balance incorrect"
    //     );

    //     // Verify user received the correct amount of issuance tokens
    //     assertEq(
    //         issuanceToken.balanceOf(whitelisted),
    //         initialUserIssuedTokens + expectedIssuedTokens,
    //         "User issued token balance incorrect"
    //     );

    //     // Verify the oracle price used matches what we expect
    //     uint oraclePrice = oracle.getPriceForIssuance();
    //     assertGt(oraclePrice, 0, "Oracle price should be greater than 0");

    //     // Verify the funding manager's buy functionality is still open
    //     assertTrue(
    //         fundingManager.buyIsOpen(), "Buy functionality should remain open"
    //     );
    // }

    // /* Test testExternalBuy_revertsGivenInvalidInputs() function revert conditions
    //     ├── Given a whitelisted user and initialized funding manager
    //     │   ├── When attempting to buy with zero amount
    //     │   │   └── Then it should revert with InvalidDepositAmount
    //     │   │
    //     │   ├── When attempting to buy with zero expected tokens
    //     │   │   └── Then it should revert with InvalidMinAmountOut
    //     │   │
    //     │   ├── When buying functionality is closed
    //     │   │   └── Then buying attempt should revert with BuyingFunctionalitiesClosed
    //     │   │
    //     │   └── When attempting to buy with excessive slippage
    //     │       ├── Given buying is reopened
    //     │       └── Then buying with multiplied expected amount should revert with InsufficientOutputAmount
    // */
    // function testExternalBuy_revertsGivenInvalidInputs(
    //     uint buyAmount,
    //     uint slippageMultiplier
    // ) public {
    //     // Bound the buy amount to reasonable values
    //     uint minAmount = 1 * 10 ** _token.decimals();
    //     uint maxAmount = 1_000_000 * 10 ** _token.decimals();
    //     buyAmount = bound(buyAmount, minAmount, maxAmount);

    //     // Bound slippage multiplier (between 2x and 10x)
    //     slippageMultiplier = bound(slippageMultiplier, 2, 10);

    //     // Setup
    //     _prepareBuyConditions(whitelisted, buyAmount);

    //     // Test zero amount

    //     vm.expectRevert(
    //         abi.encodeWithSignature(
    //             "Module__BondingCurveBase__InvalidDepositAmount()"
    //         )
    //     );
    //     fundingManager.buy(0, 0);

    //     // Test zero expected tokens
    //     vm.expectRevert(
    //         abi.encodeWithSignature(
    //             "Module__BondingCurveBase__InvalidMinAmountOut()"
    //         )
    //     );
    //     fundingManager.buy(1 ether, 0);
    //     vm.stopPrank();

    //     // Test closed buy

    //     fundingManager.closeBuy();

    //     vm.expectRevert(
    //         abi.encodeWithSignature(
    //             "Module__BondingCurveBase__BuyingFunctionaltiesClosed()"
    //         )
    //     );

    //     fundingManager.buy(buyAmount, buyAmount);

    //     // Test slippage

    //     fundingManager.openBuy();

    //     uint expectedTokens = _calculateExpectedIssuance(buyAmount);

    //     vm.expectRevert(
    //         abi.encodeWithSignature(
    //             "Module__BondingCurveBase__InsufficientOutputAmount()"
    //         )
    //     );
    //     // Try to buy with higher expected tokens than possible (multiplied by fuzzed value)
    //     fundingManager.buy(buyAmount, expectedTokens * slippageMultiplier);
    //     vm.stopPrank();
    // }

    // /* Test testExternalBuy_revertsGivenExcessiveSlippage() function slippage protection
    //     ├── Given a whitelisted user and initialized funding manager
    //     │   └── And buying functionality is open
    //     │       └── When attempting to buy with excessive slippage (2x-10x expected amount)
    //     │           └── Then it should revert with InsufficientOutputAmount
    // */
    // function testExternalBuy_revertsGivenExcessiveSlippage(
    //     uint buyAmount,
    //     uint slippageMultiplier
    // ) public {
    //     // Bound the buy amount to reasonable values
    //     uint minAmount = 1 * 10 ** _token.decimals();
    //     uint maxAmount = 1_000_000 * 10 ** _token.decimals();
    //     buyAmount = bound(buyAmount, minAmount, maxAmount);

    //     // Bound slippage multiplier (between 2x and 10x)
    //     slippageMultiplier = bound(slippageMultiplier, 2, 10);

    //     // Setup
    //     _prepareBuyConditions(whitelisted, buyAmount);

    //     // Test slippage

    //     fundingManager.openBuy();

    //     uint expectedTokens = _calculateExpectedIssuance(buyAmount);

    //     vm.expectRevert(
    //         abi.encodeWithSignature(
    //             "Module__BondingCurveBase__InsufficientOutputAmount()"
    //         )
    //     );
    //     // Try to buy with higher expected tokens than possible (multiplied by fuzzed value)
    //     fundingManager.buy(buyAmount, expectedTokens * slippageMultiplier);
    //     vm.stopPrank();
    // }

    // /* Test testExternalBuy_revertsGivenNonWhitelistedUser() function
    //     ├── Given an initialized funding manager contract
    //     │   └── And buying is open
    //     │       └── When a non-whitelisted address attempts to buy tokens
    //     │           ├── And the address has enough payment tokens
    //     │           ├── And the address is not zero address
    //     │           ├── And the address is not an admin
    //     │           ├── And the address is not whitelisted
    //     │           └── Then it should revert with CallerNotAuthorized error
    // */
    // function testExternalBuy_revertsGivenNonWhitelistedUser(
    //     address nonWhitelisted,
    //     uint buyAmount
    // ) public {
    //     vm.assume(nonWhitelisted != address(0));
    //     vm.assume(nonWhitelisted != whitelisted);
    //     vm.assume(nonWhitelisted != admin);
    //     vm.assume(nonWhitelisted != address(this));

    //     roleId =
    //         _authorizer.generateRoleId(address(fundingManager), WHITELIST_ROLE);
    //     // Prepare buy conditions with a fixed amount
    //     uint minAmount = 1 * 10 ** _token.decimals();
    //     uint maxAmount = 1_000_000 * 10 ** _token.decimals();
    //     buyAmount = bound(buyAmount, minAmount, maxAmount);

    //     _prepareBuyConditions(nonWhitelisted, buyAmount);

    //     fundingManager.openBuy();

    //     // Calculate expected tokens
    //     uint expectedTokens = _calculateExpectedIssuance(buyAmount);

    //     // Attempt to buy tokens with any non-whitelisted address
    //     vm.startPrank(nonWhitelisted);
    //     vm.expectRevert(
    //         abi.encodeWithSelector(
    //             IModule_v1.Module__CallerNotAuthorized.selector,
    //             roleId,
    //             nonWhitelisted
    //         )
    //     );
    //     fundingManager.buy(buyAmount, expectedTokens);
    //     vm.stopPrank();
    // }

    // /* Test testExternalBuy_revertsGivenBuyingClosed() function
    //     ├── Given an initialized funding manager contract
    //     │   └── And buying is closed
    //     │       └── When a whitelisted user attempts to buy tokens
    //     │           ├── And the user is not zero address
    //     │           ├── And the user has sufficient payment tokens
    //     │           ├── And the amount is within valid bounds
    //     │           └── Then it should revert with BuyingFunctionalitiesClosed error
    // */
    // function testExternalBuy_revertsGivenBuyingClosed(
    //     address buyer,
    //     uint buyAmount
    // ) public {
    //     // Given - Valid user assumptions
    //     vm.assume(buyer != address(0));
    //     vm.assume(buyer != address(this));
    //     vm.assume(buyer != admin);

    //     // Given - Valid amount bounds
    //     uint minAmount = 1 * 10 ** _token.decimals();
    //     uint maxAmount = 1_000_000 * 10 ** _token.decimals();
    //     buyAmount = bound(buyAmount, minAmount, maxAmount);

    //     // Given - Grant whitelist role to the user
    //     fundingManager.grantModuleRole(WHITELIST_ROLE, buyer);

    //     // Mint collateral tokens to buyer
    //     _token.mint(buyer, buyAmount);

    //     // Approve funding manager to spend tokens
    //     vm.prank(buyer);
    //     _token.approve(address(fundingManager), buyAmount);

    //     // When/Then - Attempt to buy when closed
    //     uint expectedTokens = _calculateExpectedIssuance(buyAmount);
    //     vm.startPrank(buyer);
    //     vm.expectRevert(
    //         abi.encodeWithSignature(
    //             "Module__BondingCurveBase__BuyingFunctionaltiesClosed()"
    //         )
    //     );
    //     fundingManager.buy(buyAmount, expectedTokens);
    //     vm.stopPrank();
    // }

    // /* Test testExternalBuy_revertsGivenZeroAmount() function
    //     ├── Given an initialized funding manager contract
    //     │   ├── And buying is open
    //     │   └── And user is whitelisted
    //     │       └── When attempting to buy tokens with zero amount
    //     │           └── Then it should revert with InvalidDepositAmount error
    // */
    // function testExternalBuy_revertsGivenZeroAmount(address buyer) public {
    //     // Given - Valid user assumptions
    //     vm.assume(buyer != address(0));
    //     vm.assume(buyer != address(this));
    //     vm.assume(buyer != admin);
    //     vm.assume(buyer != address(fundingManager));

    //     // Given - Grant whitelist role to the user
    //     // _authorizer.grantRole(roleId, buyer);
    //     fundingManager.grantModuleRole(WHITELIST_ROLE, buyer);

    //     // Given - Open buying

    //     _prepareBuyConditions(buyer, 1 ether);
    //     // fundingManager.openBuy();

    //     // When/Then - Attempt to buy with zero amount
    //     vm.startPrank(buyer);
    //     vm.expectRevert(
    //         abi.encodeWithSignature(
    //             "Module__BondingCurveBase__InvalidDepositAmount()"
    //         )
    //     );
    //     fundingManager.buy(0, 0);
    //     vm.stopPrank();
    // }

    // /* Test testExternalBuy_succeedsGivenMaxAmount() function
    //     ├── Given an initialized funding manager contract
    //     │   ├── And buying is open
    //     │   ├── And user is whitelisted
    //     │   └── And user has sufficient payment tokens
    //     │       └── When user buys tokens with maximum allowed amount
    //     │           └── Then it should:
    //     │               ├── Transfer correct payment tokens from buyer to treasury
    //     │               ├── Transfer correct issued tokens to buyer
    //     │               ├── Maintain valid oracle price
    //     │               └── Keep buy functionality open
    // */
    // function testExternalBuy_succeedsGivenMaxAmount(address buyer) public {
    //     // Given - Valid user assumptions
    //     vm.assume(buyer != address(0));
    //     vm.assume(buyer != address(this));
    //     vm.assume(buyer != admin);

    //     // Given - Use maximum allowed amount
    //     uint buyAmount = 1_000_000 * 10 ** _token.decimals();

    //     // Given - Setup buying conditions
    //     fundingManager.grantModuleRole(WHITELIST_ROLE, buyer);

    //     // Given - Mint tokens and approve
    //     _token.mint(buyer, buyAmount);
    //     vm.startPrank(buyer);
    //     _token.approve(address(fundingManager), buyAmount);
    //     vm.stopPrank();

    //     // Given - Ensure buying is open
    //     if (!fundingManager.buyIsOpen()) {
    //         fundingManager.openBuy();
    //     }

    //     // Given - Calculate expected tokens and store initial balances
    //     uint expectedTokens = _calculateExpectedIssuance(buyAmount);
    //     uint buyerBalanceBefore = _token.balanceOf(buyer);
    //     uint projectTreasuryBalanceBefore =
    //         _token.balanceOf(fundingManager.getProjectTreasury());
    //     uint buyerIssuedTokensBefore = issuanceToken.balanceOf(buyer);

    //     // When - Buy tokens with max amount
    //     vm.startPrank(buyer);
    //     fundingManager.buy(buyAmount, expectedTokens);
    //     vm.stopPrank();

    //     // Then - Verify balances
    //     assertEq(
    //         _token.balanceOf(buyer),
    //         buyerBalanceBefore - buyAmount,
    //         "Buyer payment token balance not decreased correctly"
    //     );
    //     assertEq(
    //         _token.balanceOf(fundingManager.getProjectTreasury()),
    //         projectTreasuryBalanceBefore + buyAmount,
    //         "Project treasury payment token balance not increased correctly"
    //     );
    //     assertEq(
    //         issuanceToken.balanceOf(buyer),
    //         buyerIssuedTokensBefore + expectedTokens,
    //         "Buyer issued token balance not increased correctly"
    //     );

    //     // Verify the oracle price used matches what we expect
    //     uint oraclePrice = oracle.getPriceForIssuance();
    //     assertGt(oraclePrice, 0, "Oracle price should be greater than 0");

    //     // Verify the funding manager's buy functionality is still open
    //     assertTrue(
    //         fundingManager.buyIsOpen(), "Buy functionality should remain open"
    //     );
    // }

    // // ═══════════════════════════════════════════════════════════════════════════════════════════════════════
    // // Sell Operations
    // // ═══════════════════════════════════════════════════════════════════════════════════════════════════════

    // /* Test testPublicSell_succeedsGivenWhitelistedUserAndValidAmount() function
    //     ├── Given a whitelisted user
    //     │   └── And selling is enabled
    //     │       └── And user has sufficient issuance tokens
    //     │           └── And amount is within valid bounds
    //     │               └── When the user calls sell()
    //     │                   └── Then the issuance tokens should be burned
    //     │                   └── And redemption amount should be queued correctly
    // */
    // function testPublicSell_succeedsGivenWhitelistedUserAndValidAmount(
    //     uint depositAmount
    // ) public {
    //     address seller = whitelisted;

    //     // Bound deposit to reasonable values
    //     depositAmount = bound(
    //         depositAmount,
    //         1 * 10 ** _token.decimals(),
    //         1_000_000 * 10 ** _token.decimals()
    //     );

    //     uint issuanceAmount = _prepareSellConditions(seller, depositAmount);
    //     uint expectedCollateral = _calculateExpectedCollateral(issuanceAmount);
    //     uint initialSellerIssuance = issuanceToken.balanceOf(seller);
    //     uint initialOpenRedemptions = fundingManager.getOpenRedemptionAmount();

    //     vm.prank(seller);
    //     fundingManager.sell(issuanceAmount, 1);

    //     // Verify tokens were burned
    //     assertEq(
    //         issuanceToken.balanceOf(seller),
    //         initialSellerIssuance - issuanceAmount,
    //         "Issuance tokens not burned correctly"
    //     );

    //     // Verify redemption amount was queued
    //     assertEq(
    //         fundingManager.getOpenRedemptionAmount(),
    //         initialOpenRedemptions + expectedCollateral,
    //         "Redemption amount not queued correctly"
    //     );

    //     // Verify seller has no remaining balance
    //     assertEq(
    //         issuanceToken.balanceOf(seller),
    //         0,
    //         "Seller should have no remaining issuance tokens"
    //     );
    // }

    // /* Test testPublicSell_revertsGivenInvalidAmount() function invalid amounts
    //     ├── Given selling is enabled
    //     │   └── Given user is whitelisted with issued tokens
    //     │       ├── When selling zero tokens
    //     │       │   └── Then reverts with Module__BondingCurveBase__InvalidDepositAmount
    //     │       └── When selling more than balance
    //     │           └── Then reverts with ERC20InsufficientBalance
    // */
    // function testPublicSell_revertsGivenInvalidAmount(uint depositAmount)
    //     public
    // {
    //     // Given - Setup initial state
    //     address seller = whitelisted;

    //     // Bound initial deposit to reasonable values
    //     depositAmount = bound(
    //         depositAmount,
    //         1 * 10 ** _token.decimals(),
    //         1_000_000 * 10 ** _token.decimals()
    //     );

    //     // Buy some tokens first to have a balance
    //     uint issuanceAmount = _prepareSellConditions(seller, depositAmount);

    //     // Test zero amount
    //     vm.startPrank(seller);
    //     vm.expectRevert(
    //         abi.encodeWithSignature(
    //             "Module__BondingCurveBase__InvalidDepositAmount()"
    //         )
    //     );
    //     fundingManager.sell(0, 1);
    //     vm.stopPrank();

    //     // Test amount exceeding balance
    //     vm.startPrank(seller);
    //     uint userBalance = issuanceToken.balanceOf(seller);
    //     uint excessAmount = userBalance + depositAmount;
    //     vm.expectRevert(
    //         abi.encodeWithSelector(
    //             IERC20Errors.ERC20InsufficientBalance.selector,
    //             seller,
    //             userBalance,
    //             excessAmount
    //         )
    //     );
    //     fundingManager.sell(excessAmount, 1);
    //     vm.stopPrank();
    // }

    // /* Test testPublicSell_revertsGivenZeroAmount() function with zero amount
    //     ├── Given selling is enabled
    //     │   └── Given user is whitelisted with issued tokens
    //     │       └── When selling zero tokens
    //     │           └── Then reverts with Module__BondingCurveBase__InvalidDepositAmount
    // */
    // function testPublicSell_revertsGivenZeroAmount(uint depositAmount) public {
    //     // Given - Setup initial state
    //     address seller = whitelisted;

    //     // Bound initial deposit to reasonable values
    //     uint minAmount = 1 * 10 ** _token.decimals();
    //     uint maxAmount = 1_000_000 * 10 ** _token.decimals();
    //     depositAmount = bound(depositAmount, minAmount, maxAmount);

    //     // Buy some tokens first to have a balance
    //     uint issuanceAmount = _prepareSellConditions(seller, depositAmount);

    //     vm.startPrank(seller);
    //     vm.expectRevert(
    //         abi.encodeWithSignature(
    //             "Module__BondingCurveBase__InvalidDepositAmount()"
    //         )
    //     );
    //     fundingManager.sell(0, 1);
    //     vm.stopPrank();
    // }

    // /* Test testPublicSell_revertsGivenExceedingBalance() function with exceeding balance
    //     ├── Given selling is enabled
    //     │   └── Given user is whitelisted with issued tokens
    //     │       └── When selling more than user balance
    //     │           └── Then reverts with ERC20InsufficientBalance
    // */
    // function testPublicSell_revertsGivenExceedingBalance(uint depositAmount)
    //     public
    // {
    //     // Given - Setup initial state
    //     address seller = whitelisted;

    //     // Bound initial deposit to reasonable values
    //     uint minAmount = 1 * 10 ** _token.decimals();
    //     uint maxAmount = 1_000_000 * 10 ** _token.decimals();
    //     depositAmount = bound(depositAmount, minAmount, maxAmount);

    //     // Buy some tokens first to have a balance
    //     uint issuanceAmount = _prepareSellConditions(seller, depositAmount);

    //     vm.startPrank(seller);
    //     uint userBalance = issuanceToken.balanceOf(seller);
    //     uint excessAmount = userBalance + 1;
    //     vm.expectRevert(
    //         abi.encodeWithSelector(
    //             IERC20Errors.ERC20InsufficientBalance.selector,
    //             seller,
    //             userBalance,
    //             excessAmount
    //         )
    //     );
    //     fundingManager.sell(excessAmount, 1);
    //     vm.stopPrank();
    // }

    // /* Test testPublicSell_revertsGivenInsufficientOutput() function with insufficient output
    //     ├── Given selling is enabled
    //     │   └── Given user is whitelisted with issued tokens
    //     │       └── When minAmountOut is unreasonably high
    //     │           └── Then reverts with Module__BondingCurveBase__InsufficientOutputAmount
    // */
    // function testPublicSell_revertsGivenInsufficientOutput(uint depositAmount)
    //     public
    // {
    //     // Given - Setup initial state
    //     address seller = whitelisted;

    //     // Bound initial deposit to reasonable values
    //     uint minAmount = 1 * 10 ** _token.decimals();
    //     uint maxAmount = 1_000_000 * 10 ** _token.decimals();
    //     depositAmount = bound(depositAmount, minAmount, maxAmount);

    //     // Buy some tokens first to have a balance
    //     uint issuanceAmount = _prepareSellConditions(seller, depositAmount);

    //     vm.startPrank(seller);
    //     // Try to sell 1 token but require an unreasonably high minAmountOut
    //     uint unreasonablyHighMinAmountOut = type(uint).max;
    //     vm.expectRevert(
    //         abi.encodeWithSignature(
    //             "Module__BondingCurveBase__InsufficientOutputAmount()"
    //         )
    //     );
    //     fundingManager.sell(issuanceAmount, unreasonablyHighMinAmountOut);
    //     vm.stopPrank();
    // }

    // /* Test testPublicSell_revertsGivenSellingDisabled() function with selling disabled
    //     ├── Given selling is disabled
    //     │   └── Given user is whitelisted with issued tokens
    //     │       └── When attempting to sell tokens
    //     │           └── Then reverts with Module__RedeemingBondingCurveBase__SellingFunctionaltiesClosed
    // */
    // function testPublicSell_revertsGivenSellingDisabled(uint depositAmount)
    //     public
    // {
    //     // Given - Setup initial state
    //     address seller = whitelisted;

    //     // Bound initial deposit to reasonable values
    //     uint minAmount = 1 * 10 ** _token.decimals();
    //     uint maxAmount = 1_000_000 * 10 ** _token.decimals();
    //     depositAmount = bound(depositAmount, minAmount, maxAmount);

    //     // Buy some tokens first to have a balance
    //     uint issuanceAmount = _prepareSellConditions(seller, depositAmount);

    //     fundingManager.closeBuy();
    //     fundingManager.closeSell();
    //     vm.stopPrank();

    //     vm.startPrank(seller);
    //     vm.expectRevert(
    //         abi.encodeWithSignature(
    //             "Module__RedeemingBondingCurveBase__SellingFunctionaltiesClosed()"
    //         )
    //     );
    //     fundingManager.sell(1, 1);
    //     vm.stopPrank();
    // }

    // /* Test testPublicSell_revertsGivenInsufficientCollateral() function with insufficient collateral
    //     ├── Given selling is enabled
    //     │   └── Given user is whitelisted with issued tokens
    //     │       └── Given contract collateral has been withdrawn
    //     │           └── When attempting to sell tokens
    //     │               └── Then reverts with Module__RedeemingBondingCurveBase__InsufficientCollateralForProjectFee
    // */
    // function testPublicSell_revertsGivenInsufficientCollateral(
    //     uint depositAmount
    // ) public {
    //     // Given - Setup initial state
    //     address seller = whitelisted;

    //     // Bound initial deposit to reasonable values
    //     depositAmount = bound(
    //         depositAmount,
    //         100 * 10 ** _token.decimals(), // Aseguramos una cantidad significativa
    //         1_000_000 * 10 ** _token.decimals()
    //     );

    //     // Buy some tokens first to have a balance
    //     uint issuanceAmount = _prepareSellConditions(seller, depositAmount);

    //     // Calculate how much collateral we need
    //     uint saleReturn = fundingManager.calculateSaleReturn(issuanceAmount);

    //     // Get current collateral balance
    //     uint collateralBalance = _token.balanceOf(address(fundingManager));

    //     // Drain ALL collateral from the contract
    //     fundingManager.withdrawProjectCollateralFee(seller, collateralBalance);

    //     // Verify contract has no collateral
    //     assertEq(
    //         _token.balanceOf(address(fundingManager)),
    //         0,
    //         "Contract should have no collateral"
    //     );

    //     // Attempt to sell tokens
    //     /*
    //     TODO => Test projectCollateralFeeCollected in _sellOrder
    //             Error => Module__RedeemingBondingCurveBase__InsufficientCollateralForProjectFee
    //     */
    //     // vm.startPrank(seller);
    //     // vm.expectRevert(
    //     //     abi.encodeWithSignature(
    //     //         "Module__RedeemingBondingCurveBase__InsufficientCollateralForProjectFee()"
    //     //     )
    //     // );
    //     // fundingManager.sell(issuanceAmount, 1); // Intentamos vender todos los tokens
    //     // vm.stopPrank();
    // }

    // // ═══════════════════════════════════════════════════════════════════════════════════════════════════════
    // // Redemption Orders
    // // ═══════════════════════════════════════════════════════════════════════════════════════════════════════

    // /* Test testExternalSell_succeedsGivenValidRedemptionOrder() function
    //     ├── Given an initialized funding manager contract
    //     │   ├── And selling is open
    //     │   ├── And user is whitelisted
    //     │   └── And user has sufficient issued tokens
    //     │       └── When user sells tokens
    //     │           └── Then it should:
    //     │               ├── Create redemption order with correct parameters
    //     │               ├── Update open redemption amount
    //     │               ├── Set order state to PENDING
    //     │               └── Emit TokensSold event
    // */
    // function testExternalSell_succeedsGivenValidRedemptionOrder(
    //     uint depositAmount
    // ) public {
    //     // Given - Setup seller
    //     address seller = whitelisted;

    //     // Given - Setup valid deposit bounds
    //     uint minAmount = 1 * 10 ** _token.decimals();
    //     uint maxAmount = 1_000_000 * 10 ** _token.decimals();
    //     depositAmount = bound(depositAmount, minAmount, maxAmount);

    //     // Given - Prepare initial token balance through purchase
    //     vm.prank(seller);
    //     uint issuanceAmount = _prepareSellConditions(seller, depositAmount);

    //     // Given - Calculate expected redemption amounts
    //     uint sellAmount = issuanceAmount / 2; // Selling 50% of purchased tokens
    //     uint expectedCollateral = _calculateExpectedCollateral(sellAmount);

    //     // Given - Record initial state
    //     uint initialOpenRedemptionAmount =
    //         fundingManager.getOpenRedemptionAmount();

    //     // When - Create redemption order
    //     vm.startPrank(seller);
    //     fundingManager.sell(sellAmount, 1);
    //     vm.stopPrank();

    //     // Then - Verify redemption amount update
    //     assertEq(
    //         fundingManager.getOpenRedemptionAmount(),
    //         initialOpenRedemptionAmount + expectedCollateral,
    //         "Open redemption amount not updated correctly"
    //     );
    // }

    // /* Test testExternalQueue_managesCollateralCorrectly() function
    //     ├── Given an initialized funding manager contract
    //     │   └── When a redemption order is processed
    //     │       └── Then it should:
    //     │           ├── Track contract collateral balance correctly
    //     │           ├── Update user token balance appropriately
    //     │           ├── Transfer expected collateral amounts
    //     │           └── Process fees according to configuration
    // */
    // function testExternalQueue_managesCollateralCorrectly(uint depositAmount)
    //     public
    // {
    //     // Given - Setup valid deposit bounds
    //     depositAmount = bound(
    //         depositAmount,
    //         1 * 10 ** _token.decimals(),
    //         1_000_000 * 10 ** _token.decimals()
    //     );

    //     // Given - Create redemption conditions
    //     uint issuanceAmount = _prepareSellConditions(whitelisted, depositAmount);
    //     uint sellAmount = issuanceAmount / 2; // Selling 50% of purchased tokens
    //     uint expectedCollateral = _calculateExpectedCollateral(sellAmount);

    //     // Given - Record initial balances
    //     uint initialContractBalance = _token.balanceOf(address(fundingManager));
    //     uint initialUserBalance = _token.balanceOf(whitelisted);

    //     // Given - Fund contract for redemption
    //     _token.mint(address(fundingManager), expectedCollateral);

    //     // When - Create and process redemption order

    //     fundingManager.sell(sellAmount, 1);

    //     // Then - Verify collateral accounting
    //     assertEq(
    //         _token.balanceOf(address(fundingManager)),
    //         initialContractBalance + expectedCollateral,
    //         "Contract balance should increase by expected collateral amount"
    //     );
    // }

    // // ═══════════════════════════════════════════════════════════════════════════════════════════════════════
    // // View Functions and Direct Operations
    // // ═══════════════════════════════════════════════════════════════════════════════════════════════════════

    // /* Test testOracle_returnsPricesWithinValidRanges() function
    //     ├── Given an initialized oracle contract
    //     │   └── When requesting static prices
    //     │       └── Then it should ensure:
    //     │           ├── Issuance price is positive
    //     │           ├── Redemption price is positive
    //     │           └── Issuance price >= redemption price
    // */
    // function testOracle_returnsPricesWithinValidRanges(uint priceMultiplier)
    //     public
    // {
    //     // Given - Bound multiplier to reasonable range
    //     priceMultiplier = bound(priceMultiplier, 1, 1000);

    //     // When - Get static prices
    //     uint issuancePrice = oracle.getPriceForIssuance();
    //     uint redemptionPrice = oracle.getPriceForRedemption();

    //     // Then - Verify price constraints
    //     assertTrue(issuancePrice > 0, "Issuance price must be positive");
    //     assertTrue(redemptionPrice > 0, "Redemption price must be positive");
    //     assertGe(
    //         issuancePrice,
    //         redemptionPrice,
    //         "Issuance price must be >= redemption price"
    //     );
    // }

    // /* Test testAdmin_transfersOrchestratorTokenCorrectly() function
    //     ├── Given an initialized funding manager
    //     │   ├── When admin transfers orchestrator token
    //     │   │   └── Then it should:
    //     │   │       ├── Update orchestrator reference
    //     │   │       ├── Transfer correct token amount
    //     │   │       └── Emit transfer event
    //     │   └── When non-admin attempts transfer
    //     │       └── Then it should revert with permission error
    // */
    // function testAdmin_transfersOrchestratorTokenCorrectly(uint amount)
    //     public
    // {
    //     // Given - Setup valid transfer amount
    //     amount = bound(amount, 1 * 10 ** 18, 1_000_000 * 10 ** 18);

    //     // Given - Fund contract and configure permissions
    //     _token.mint(address(fundingManager), amount);
    //     _addLogicModuleToOrchestrator(address(paymentClient));

    //     // When - Admin executes transfer
    //     vm.startPrank(address(paymentClient));
    //     fundingManager.transferOrchestratorToken(
    //         address(fundingManager), amount
    //     );

    //     // Then - Verify orchestrator state
    //     assertEq(
    //         address(fundingManager.orchestrator()),
    //         address(_orchestrator),
    //         "Orchestrator reference should be unchanged"
    //     );

    //     // Then - Verify token transfer
    //     assertEq(
    //         _token.balanceOf(address(fundingManager)),
    //         amount,
    //         "Contract balance should match transferred amount"
    //     );
    //     vm.stopPrank();

    //     // When/Then - Non-admin transfer should fail

    //     vm.expectRevert(
    //         abi.encodeWithSignature("Module__OnlyCallableByPaymentClient()")
    //     );
    //     fundingManager.transferOrchestratorToken(
    //         address(fundingManager), amount
    //     );
    //     vm.stopPrank();
    // }

    // /* Test testDirectOperations_executesTradesCorrectly() function
    //     ├── Given an initialized funding manager
    //     │   ├── When whitelisted user performs direct buy
    //     │   │   └── Then it should:
    //     │   │       ├── Accept user's collateral
    //     │   │       └── Issue correct token amount
    //     │   └── When same user performs direct sell
    //     │       └── Then it should:
    //     │           ├── Burn user's issued tokens
    //     │           └── Release appropriate collateral
    // */
    // function testDirectOperations_executesTradesCorrectly(uint buyAmount)
    //     public
    // {
    //     // Given - Setup valid trade amount
    //     buyAmount = bound(
    //         buyAmount,
    //         1 * 10 ** _token.decimals(),
    //         1_000_000 * 10 ** _token.decimals()
    //     );

    //     // When - Execute direct buy

    //     _prepareBuyConditions(whitelisted, buyAmount);

    //     // When - Execute matching sell

    //     uint issuanceAmount = _prepareSellConditions(whitelisted, buyAmount);
    //     uint sellAmount = issuanceAmount; // Sell entire position
    //     uint expectedCollateral = _calculateExpectedCollateral(sellAmount);

    //     fundingManager.sell(sellAmount, 1);
    //     vm.stopPrank();

    //     // Then - Verify position closure
    //     assertEq(
    //         issuanceToken.balanceOf(whitelisted),
    //         0,
    //         "User's issuance tokens should be fully redeemed"
    //     );

    //     // Then - Verify collateral release
    //     assertLt(
    //         _token.balanceOf(address(fundingManager)),
    //         buyAmount,
    //         "Contract should release proportional collateral"
    //     );
    // }
    // ================================================================================
    // Helper Functions

    function _setOpenRedemptionAmount(uint amount_) internal {
        uint openRedemptionAmount = fundingManager.getOpenRedemptionAmount();
        if (amount_ > openRedemptionAmount) {
            fundingManager.exposed_addToOpenRedemptionAmount(
                amount_ - openRedemptionAmount
            );
        } else {
            fundingManager.exposed_deductFromOpenRedemptionAmount(
                openRedemptionAmount - amount_
            );
        }
    }

    // Helper function that mints enough collateral tokens to a buyer and approves the funding manager to spend them
    function _prepareBuyConditions(address buyer, uint amount) internal {
        // Mint collateral tokens to buyer
        _token.mint(buyer, amount);

        // Approve funding manager to spend tokens
        vm.prank(buyer);
        _token.approve(address(fundingManager), amount);
    }

    // Helper function that initializes the funding manager with different token decimals.
    // This helper function is needed to test the wrapper functions which make use of private
    // variables for the token decimals. As I can't override them, I create a new FM for fuzz testing.
    function _initializeFundingManagerWithDifferentTokenDecimals(
        uint8 issuanceTokenDecimals_,
        uint8 collateralTokenDecimals_
    ) internal returns (address fundingManager_) {
        // Create collateral token
        ERC20Decimals_Mock newCollateralToken = new ERC20Decimals_Mock(
            "Collateral Token", "CT", collateralTokenDecimals_
        );

        // Create issuance token
        ERC20Issuance_v1 newIssuanceToken = new ERC20Issuance_v1(
            NAME, SYMBOL, issuanceTokenDecimals_, MAX_SUPPLY, address(this)
        );
        bytes memory newConfigData = abi.encode(
            projectTreasury,
            address(newIssuanceToken),
            address(newCollateralToken),
            DEFAULT_BUY_FEE,
            DEFAULT_SELL_FEE,
            MAX_SELL_FEE,
            MAX_BUY_FEE,
            DIRECT_OPERATIONS_ONLY
        );
        // Setup funding manager
        address impl = address(new FM_PC_ExternalPrice_Redeeming_v1_Exposed());
        FM_PC_ExternalPrice_Redeeming_v1_Exposed newFundingManager =
            FM_PC_ExternalPrice_Redeeming_v1_Exposed(Clones.clone(impl));

        // Initialize funding manager
        newFundingManager.init(_orchestrator, _METADATA, newConfigData);

        return address(newFundingManager);
    }

    // // Helper function that:
    // //      - First prepares buy conditions (mint & approve collateral tokens)
    // //      - Executes buy operation to get issuance tokens
    // //      - Ensures selling is enabled
    // function _prepareSellConditions(address seller, uint amount)
    //     internal
    //     returns (uint availableForSale)
    // {
    //     // First prepare buy conditions
    //     _prepareBuyConditions(seller, amount);

    //     // Calculate expected issuance tokens using the contract's function
    //     uint minAmountOut = fundingManager.calculatePurchaseReturn(amount);

    //     // Execute buy to get issuance tokens
    //     vm.startPrank(seller);
    //     fundingManager.buy(amount, minAmountOut);
    //     vm.stopPrank();

    //     // Ensure selling is enabled
    //     if (!fundingManager.sellIsOpen()) {
    //         fundingManager.openSell();
    //     }

    //     return minAmountOut;
    // }

    // // Helper function to calculate expected issuance tokens for a given collateral amount
    // // This includes:
    // //      - Applying buy fee to get net deposit
    // //      - Multiplying by oracle price to get issuance amount
    // function _calculateExpectedIssuance(uint collateralAmount)
    //     internal
    //     view
    //     returns (uint expectedIssuedTokens)
    // {
    //     // Use the contract's public calculation function that handles all the internal logic
    //     return fundingManager.calculatePurchaseReturn(collateralAmount);
    // }

    // // Helper function to calculate expected collateral tokens for a given issuance amount
    // // This includes:
    // //      - Dividing by oracle price to get gross collateral
    // //      - Applying sell fee to get net collateral
    // function _calculateExpectedCollateral(uint amount)
    //     internal
    //     view
    //     returns (uint)
    // {
    //     return fundingManager.calculateSaleReturn(amount);
    // }
}
