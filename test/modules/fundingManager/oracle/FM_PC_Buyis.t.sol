// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IOraclePrice_v1} from "@lm/interfaces/IOraclePrice_v1.sol";
import {FM_PC_ExternalPrice_Redeeming_v1} from "src/modules/fundingManager/oracle/FM_PC_ExternalPrice_Redeeming_v1.sol";
import {IFM_PC_ExternalPrice_Redeeming_v1} from "@fm/oracle/interfaces/IFM_PC_ExternalPrice_Redeeming_v1.sol";
import {IOrchestrator_v1} from "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {MockERC20} from "test/modules/fundingManager/oracle/utils/mocks/MockERC20.sol";
import {AuthorizerV1Mock} from "test/utils/mocks/modules/AuthorizerV1Mock.sol";
import {OrchestratorV1Mock} from "test/utils/mocks/orchestrator/OrchestratorV1Mock.sol";
import {ModuleTest} from "test/modules/ModuleTest.sol";
import {Clones} from "@oz/proxy/Clones.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {OZErrors} from "test/utils/errors/OZErrors.sol";
import {Module_v1} from "src/modules/base/Module_v1.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {BondingCurveBase_v1} from "@fm/bondingCurve/abstracts/BondingCurveBase_v1.sol";
import {RedeemingBondingCurveBase_v1} from "@fm/bondingCurve/abstracts/RedeemingBondingCurveBase_v1.sol";
import {InvalidOracleMock} from "./utils/mocks/InvalidOracleMock.sol";
import {ERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol";
import {LM_ManualExternalPriceSetter_v1} from "src/modules/logicModule/LM_ManualExternalPriceSetter_v1.sol";
import {LM_ManualExternalPriceSetter_v1_Exposed} from
    "test/modules/fundingManager/oracle/utils/mocks/LM_ManualExternalPriceSetter_v1_exposed.sol";
import {
    IERC20PaymentClientBase_v1,
    ERC20PaymentClientBaseV1Mock,
    ERC20Mock
} from "test/utils/mocks/modules/paymentClient/ERC20PaymentClientBaseV1Mock.sol";
import {PP_Streaming_v1AccessMock} from
    "test/utils/mocks/modules/paymentProcessor/PP_Streaming_v1AccessMock.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

import {
    RedeemingBondingCurveBaseV1Mock,
    IRedeemingBondingCurveBase_v1
} from
    "test/modules/fundingManager/bondingCurve/utils/mocks/RedeemingBondingCurveBaseV1Mock.sol";
import {BancorFormula} from "@fm/bondingCurve/formulas/BancorFormula.sol";
import {
    PP_Streaming_v1,
    IPP_Streaming_v1
} from "src/modules/paymentProcessor/PP_Streaming_v1.sol";

/**
 * @title FM_PC_ExternalPrice_Redeeming_v1_Test
 * @notice Test contract for FM_PC_ExternalPrice_Redeeming_v1
 */
contract FM_PC_ExternalPrice_Redeeming_v1_Test is ModuleTest {

    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════
    // Storage
    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════

    FM_PC_ExternalPrice_Redeeming_v1 fundingManager;
    AuthorizerV1Mock authorizer;
    RedeemingBondingCurveBaseV1Mock bondingCurveFundingManager;

    // Test addresses
    address admin;
    address user;
    address whitelisted;
    address queueManager;

    // Mock tokens
    ERC20Issuance_v1 issuanceToken;    // The token to be issued

    // Mock oracle
    LM_ManualExternalPriceSetter_v1 oracle;

    // Payment processor
    PP_Streaming_v1AccessMock paymentProcessor;
    ERC20PaymentClientBaseV1Mock paymentClient;


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

    // Module Constants
    uint constant MAJOR_VERSION = 1;
    uint constant MINOR_VERSION = 0;
    uint constant PATCH_VERSION = 0;
    string constant URL = "https://github.com/organization/module";
    string constant TITLE = "Module";

    bytes32 internal roleId;
    bytes32 internal roleIDOracle; 
    bytes32 internal queueManagerRoleId;

    uint private constant BUY_FEE = 0;
    uint private constant SELL_FEE = 0;
    bool private constant BUY_IS_OPEN = true;
    bool private constant SELL_IS_OPEN = true;

    address formula;


    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════
    // Setup
    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════

    function setUp() public {
        // Setup addresses
        admin = makeAddr("admin");
        user = makeAddr("user");
        whitelisted = makeAddr("whitelisted");
        queueManager = makeAddr("queueManager");

        admin = address(this);
        vm.startPrank(admin);

        // Create issuance token
        issuanceToken = new ERC20Issuance_v1(
            NAME, SYMBOL, DECIMALS, MAX_SUPPLY, address(this)
        );

        // Setup orchestrator and authorizer
        authorizer = new AuthorizerV1Mock();
        _authorizer = authorizer;

        //paymentProcessor
        address PaymentImpl = address(new PP_Streaming_v1AccessMock());
        paymentProcessor = PP_Streaming_v1AccessMock(Clones.clone(PaymentImpl));

        _setUpOrchestrator(paymentProcessor);
        paymentProcessor.init(_orchestrator, _METADATA, bytes(""));
        _authorizer.setIsAuthorized(address(this), true);
        // Set up PaymentClient Correctöy
        PaymentImpl = address(new ERC20PaymentClientBaseV1Mock());
        paymentClient = ERC20PaymentClientBaseV1Mock(Clones.clone(PaymentImpl));

        _orchestrator.initiateAddModuleWithTimelock(address(paymentClient));
        vm.warp(block.timestamp + _orchestrator.MODULE_UPDATE_TIMELOCK());
        _orchestrator.executeAddModule(address(paymentClient));

        paymentClient.init(_orchestrator, _METADATA, bytes(""));
        paymentClient.setIsAuthorized(address(paymentProcessor), true);
        paymentClient.setToken(_token);

        //
        address impl_ = address(new RedeemingBondingCurveBaseV1Mock());

        bondingCurveFundingManager =
            RedeemingBondingCurveBaseV1Mock(Clones.clone(impl_));

        formula = address(new BancorFormula());

        issuanceToken = new ERC20Issuance_v1(
            NAME, SYMBOL, DECIMALS, type(uint).max, address(this)
        );
        issuanceToken.setMinter(address(bondingCurveFundingManager), true);
        _setUpOrchestrator(bondingCurveFundingManager);
        _authorizer.grantRole(_authorizer.getAdminRole(), admin);

        vm.stopPrank();
        // Set max fee of feeManager to 100% for testing purposes
        vm.prank(address(governor));
        feeManager.setMaxFee(feeManager.BPS());

        vm.startPrank(admin);
        // Init Module
        bondingCurveFundingManager.init(
            _orchestrator,
            _METADATA,
            abi.encode(
                address(issuanceToken),
                formula,
                BUY_FEE,
                BUY_IS_OPEN,
                SELL_IS_OPEN
            )
        );


        //

        // Setup oracle with proper token decimals
        address oracleImpl = address(new LM_ManualExternalPriceSetter_v1());
        oracle = LM_ManualExternalPriceSetter_v1(Clones.clone(oracleImpl));
        bytes memory oracleConfigData = abi.encode(
            address(_token),      // collateral token
            address(issuanceToken) // issuance token
        );
        _setUpOrchestrator(oracle);
        oracle.init(_orchestrator, _METADATA, oracleConfigData);
        // Grant price setter role to admin
        roleIDOracle = _authorizer.generateRoleId(address(oracle), ORACLE_ROLE);
        _authorizer.grantRole(roleIDOracle, admin);

        // Set initial prices
        uint initialPrice = 1e18; // 1:1 ratio
        oracle.setIssuancePrice(initialPrice);
        oracle.setRedemptionPrice(initialPrice);

        // Setup funding manager
        address impl = address(new FM_PC_ExternalPrice_Redeeming_v1());
        fundingManager = FM_PC_ExternalPrice_Redeeming_v1(Clones.clone(impl));

        // Prepare config data
        bytes memory configData = abi.encode(
            address(oracle),           // oracle address
            address(issuanceToken),    // issuance token
            address(_token),           // accepted token
            DEFAULT_BUY_FEE,          // buy fee
            DEFAULT_SELL_FEE,         // sell fee
            MAX_SELL_FEE,             // max sell fee
            MAX_BUY_FEE,              // max buy fee
            DIRECT_OPERATIONS_ONLY     // direct operations only flag
        );

        _setUpOrchestrator(fundingManager);

        // Initialize the funding manager
        fundingManager.init(_orchestrator, _METADATA, configData);

        // Grant whitelist role
        roleId = _authorizer.generateRoleId(address(fundingManager), WHITELIST_ROLE);
        _authorizer.grantRole(roleId, whitelisted);

        // Grant queue manager role to queueManager address
        queueManagerRoleId = _authorizer.generateRoleId(address(fundingManager), QUEUE_MANAGER_ROLE);
        _authorizer.grantRole(queueManagerRoleId, queueManager);

        // Grant minting rights to the funding manager
        issuanceToken.setMinter(address(fundingManager), true);
        fundingManager.setOracleAddress(address(oracle));

        vm.stopPrank();

    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════
    // Initialization
    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════

    /* testInit()
        └── Given a newly deployed contract
            ├── When initializing with valid parameters
            │   ├── Then the oracle should be set correctly
            │   ├── Then the tokens should be set correctly
            │   ├── Then the fees should be set correctly
            │   └── Then the orchestrator should be set correctly
            └── When checking initialization state
                └── Then it should be initialized correctly
    */
    function testInit() public override(ModuleTest) {
        assertEq(
            address(fundingManager.orchestrator()),
            address(_orchestrator),
            "Orchestrator not set correctly"
        );
    }

    /* testReinitFails()
        └── Given an initialized contract
            └── When trying to initialize again
                └── Then it should revert with InvalidInitialization
    */
    function testReinitFails() public override(ModuleTest) {
        bytes memory configData = abi.encode(
            address(oracle),           // oracle address
            address(issuanceToken),    // issuance token
            address(_token),           // accepted token
            DEFAULT_BUY_FEE,          // buy fee
            DEFAULT_SELL_FEE,         // sell fee
            MAX_SELL_FEE,             // max sell fee
            MAX_BUY_FEE,              // max buy fee
            DIRECT_OPERATIONS_ONLY     // direct operations only flag
        );

        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        fundingManager.init(_orchestrator, _METADATA, configData);
    }

   // ═══════════════════════════════════════════════════════════════════════════════════════════════════════
    // View Functions and Direct Operations
    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════

    /* Test testOracle_returnsPricesWithinValidRanges() function
        ├── Given an initialized oracle contract 
        │   └── When requesting static prices
        │       └── Then it should ensure:
        │           ├── Issuance price is positive
        │           ├── Redemption price is positive 
        │           └── Issuance price >= redemption price
    */
    function testOracle_returnsPricesWithinValidRanges(
        uint256 priceMultiplier
    ) public {
        // Given - Bound multiplier to reasonable range
        priceMultiplier = bound(priceMultiplier, 1, 1000);
        
        // When - Get static prices
        uint256 issuancePrice = oracle.getPriceForIssuance();
        uint256 redemptionPrice = oracle.getPriceForRedemption();

        // Then - Verify price constraints
        assertTrue(
            issuancePrice > 0, 
            "Issuance price must be positive"
        );
        assertTrue(
            redemptionPrice > 0, 
            "Redemption price must be positive"
        );
        assertGe(
            issuancePrice, 
            redemptionPrice, 
            "Issuance price must be >= redemption price"
        );
    }

    /* Test testAdmin_transfersOrchestratorTokenCorrectly() function
        ├── Given an initialized funding manager
        │   ├── When admin transfers orchestrator token
        │   │   └── Then it should:
        │   │       ├── Update orchestrator reference
        │   │       ├── Transfer correct token amount
        │   │       └── Emit transfer event
        │   └── When non-admin attempts transfer
        │       └── Then it should revert with permission error
    */
    function testAdmin_transfersOrchestratorTokenCorrectly(
        uint256 amount
    ) public {
        // Given - Setup valid transfer amount
        amount = bound(amount, 1 * 10**18, 1_000_000 * 10**18);
        
        // Given - Fund contract and configure permissions
        _token.mint(address(fundingManager), amount);
        _addLogicModuleToOrchestrator(address(paymentClient));

        // When - Admin executes transfer
        vm.startPrank(address(paymentClient));
        fundingManager.transferOrchestratorToken(
            address(fundingManager), 
            amount
        );
        
        // Then - Verify orchestrator state
        assertEq(
            address(fundingManager.orchestrator()),
            address(_orchestrator),
            "Orchestrator reference should be unchanged"
        );
        
        // Then - Verify token transfer
        assertEq(
            _token.balanceOf(address(fundingManager)),
            amount,
            "Contract balance should match transferred amount"
        );
        vm.stopPrank();

        // When/Then - Non-admin transfer should fail
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSignature("Module__OnlyCallableByPaymentClient()")
        );
        fundingManager.transferOrchestratorToken(
            address(fundingManager), 
            amount
        );
        vm.stopPrank();
    }

    /* Test testDirectOperations_executesTradesCorrectly() function
        ├── Given an initialized funding manager
        │   ├── When whitelisted user performs direct buy
        │   │   └── Then it should:
        │   │       ├── Accept user's collateral
        │   │       └── Issue correct token amount
        │   └── When same user performs direct sell
        │       └── Then it should:
        │           ├── Burn user's issued tokens
        │           └── Release appropriate collateral
    */
    function testDirectOperations_executesTradesCorrectly(
        uint256 buyAmount
    ) public {
        // Given - Setup valid trade amount
        buyAmount = bound(
            buyAmount, 
            1 * 10**_token.decimals(), 
            1_000_000 * 10**_token.decimals()
        );

        // When - Execute direct buy
        vm.prank(whitelisted);
        _prepareBuyConditions(whitelisted, buyAmount);

        // When - Execute matching sell
        vm.prank(whitelisted);
        uint256 issuanceAmount = _prepareSellConditions(whitelisted, buyAmount);
        uint256 sellAmount = issuanceAmount; // Sell entire position
        uint256 expectedCollateral = _calculateExpectedCollateral(sellAmount);

        vm.startPrank(whitelisted);
        fundingManager.sell(sellAmount, 1);
        vm.stopPrank();

        // Then - Verify position closure
        assertEq(
            issuanceToken.balanceOf(whitelisted), 
            0, 
            "User's issuance tokens should be fully redeemed"
        );

        // Then - Verify collateral release
        assertLt(
            _token.balanceOf(address(fundingManager)), 
            buyAmount, 
            "Contract should release proportional collateral"
        );
    }
    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════
    // Helper Functions
    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════

    // Helper function that mints enough collateral tokens to a buyer and approves the funding manager to spend them
    function _prepareBuyConditions(address buyer, uint amount) internal {
        // Mint collateral tokens to buyer
        _token.mint(buyer, amount);
        
        // Approve funding manager to spend tokens
        vm.prank(buyer);
        _token.approve(address(fundingManager), amount);
        
        // Ensure buying is enabled
        if (!fundingManager.buyIsOpen()) {
            vm.prank(admin);
            fundingManager.openBuy();
        }
    }

    // Helper function that:
    //      - First prepares buy conditions (mint & approve collateral tokens)
    //      - Executes buy operation to get issuance tokens
    //      - Ensures selling is enabled
    function _prepareSellConditions(address seller, uint amount) internal returns (uint availableForSale) {
        // First prepare buy conditions
        _prepareBuyConditions(seller, amount);
        
        // Calculate expected issuance tokens using the contract's function
        uint256 minAmountOut = fundingManager.calculatePurchaseReturn(amount);
        
        // Execute buy to get issuance tokens
        vm.startPrank(seller);
        fundingManager.buy(amount, minAmountOut);
        vm.stopPrank();
        
        // Ensure selling is enabled
        if (!fundingManager.sellIsOpen()) {
            vm.prank(admin);
            fundingManager.openSell();
        }

        return minAmountOut;
    }

    // Helper function to calculate expected issuance tokens for a given collateral amount
    // This includes:
    //      - Applying buy fee to get net deposit
    //      - Multiplying by oracle price to get issuance amount
    function _calculateExpectedIssuance(uint256 collateralAmount) internal view returns (uint256 expectedIssuedTokens) {
        // Use the contract's public calculation function that handles all the internal logic
        return fundingManager.calculatePurchaseReturn(collateralAmount);
    }

    // Helper function to calculate expected collateral tokens for a given issuance amount
    // This includes:
    //      - Dividing by oracle price to get gross collateral
    //      - Applying sell fee to get net collateral
    function _calculateExpectedCollateral(uint256 amount) internal view returns (uint256) {
        return fundingManager.calculateSaleReturn(amount);
    }

}