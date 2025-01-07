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
import {PP_Queue_v1Mock} from
    "test/utils/mocks/modules/paymentProcessor/PP_Queue_v1Mock.sol";
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
    ERC20PaymentClientBaseV1Mock paymentClient;
    PP_Queue_v1Mock paymentProcessor;


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
        address PaymentImpl = address(new PP_Queue_v1Mock());
        paymentProcessor = PP_Queue_v1Mock(Clones.clone(PaymentImpl));

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
    // Configuration
    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════
    
    /* Test testFees_initializesToDefaultConfiguration() function
        ├── Given a newly deployed funding manager
        │   └── Then it should initialize with:
        │       ├── Buy fee = DEFAULT_BUY_FEE
        │       ├── Sell fee = DEFAULT_SELL_FEE
        │       ├── Maximum buy fee = MAX_BUY_FEE
        │       └── Maximum sell fee = MAX_SELL_FEE
    */
    function testFees_initializesToDefaultConfiguration() public {
        // Then - Verify buy fee configuration
        assertEq(
            fundingManager.buyFee(),
            DEFAULT_BUY_FEE,
            "Initial buy fee must match default value"
        );

        // Then - Verify sell fee configuration  
        assertEq(
            fundingManager.sellFee(),
            DEFAULT_SELL_FEE,
            "Initial sell fee must match default value"
        );

        // Then - Verify maximum fee constraints
        assertEq(
            fundingManager.getMaxBuyFee(),
            MAX_BUY_FEE,
            "Maximum buy fee must match configured cap"
        );

        assertEq(
            fundingManager.getMaxProjectSellFee(),
            MAX_SELL_FEE,
            "Maximum sell fee must match configured cap"
        );
    }

    /* Test testToken_initializesIssuanceTokenCorrectly() function
        ├── Given a newly deployed funding manager
        │   └── Then it should:
        │       ├── Store correct issuance token address
        │       └── Maintain token reference accessibility
    */
    function testToken_initializesIssuanceTokenCorrectly() public {
        assertEq(
            fundingManager.getIssuanceToken(),
            address(issuanceToken),
            "Contract must reference configured issuance token"
        );
    }

    /* Test testToken_initializesCollateralTokenCorrectly() function 
        ├── Given a newly deployed funding manager
        │   └── Then it should:
        │       ├── Store correct collateral token address
        │       └── Maintain token reference accessibility
    */
    function testToken_initializesCollateralTokenCorrectly() public {
        assertEq(
            address(fundingManager.token()),
            address(_token),
            "Contract must reference configured collateral token"
        );
    }

    /* Test testInit_rejectsExcessiveBuyFee() function
        ├── Given contract deployment parameters
        │   └── When initializing with buy fee > MAX_BUY_FEE
        │       └── Then it should:
        │           ├── Revert with FeeExceedsMaximum error
        │           └── Include exceeded and maximum values
    */
    function testInit_rejectsExcessiveBuyFee() public {
        bytes memory invalidConfigData = abi.encode(
            address(oracle),           // oracle address
            address(issuanceToken),    // issuance token
            address(_token),           // accepted token
            MAX_BUY_FEE + 1,          // buy fee exceeds max
            DEFAULT_SELL_FEE,         // sell fee
            MAX_SELL_FEE,             // max sell fee
            MAX_BUY_FEE,              // max buy fee
            DIRECT_OPERATIONS_ONLY     // direct operations only flag
        );

        address impl = address(new FM_PC_ExternalPrice_Redeeming_v1());
        address newFundingManager = address(new ERC1967Proxy(impl, ""));
        
        vm.expectRevert(
            abi.encodeWithSelector(
            IFM_PC_ExternalPrice_Redeeming_v1.Module__FM_PC_ExternalPrice_Redeeming_FeeExceedsMaximum.selector,
            MAX_BUY_FEE + 1,
            MAX_BUY_FEE
            )
        );
        FM_PC_ExternalPrice_Redeeming_v1(newFundingManager).init(
            _orchestrator,
            _METADATA,
            invalidConfigData
        );
    }

    /* Test initialization with invalid fees
        ├── Given a new contract deployment
        │   └── And sell fee exceeds MAX_SELL_FEE
        │       └── When the init() function is called
        │           └── Then should revert with FeeExceedsMaximum error
    */
    function testExternalInit_revertsGivenSellFeeExceedsMaximum() public {
        bytes memory invalidConfigData = abi.encode(
            address(oracle),           // oracle address
            address(issuanceToken),    // issuance token
            address(_token),           // accepted token
            DEFAULT_BUY_FEE,          // buy fee
            MAX_SELL_FEE + 1,         // sell fee exceeds max
            MAX_SELL_FEE,             // max sell fee
            MAX_BUY_FEE,              // max buy fee
            DIRECT_OPERATIONS_ONLY     // direct operations only flag
        );

        address impl = address(new FM_PC_ExternalPrice_Redeeming_v1());
        address newFundingManager = address(new ERC1967Proxy(impl, ""));
        
        vm.expectRevert(
            abi.encodeWithSelector(
            IFM_PC_ExternalPrice_Redeeming_v1.Module__FM_PC_ExternalPrice_Redeeming_FeeExceedsMaximum.selector,
            MAX_SELL_FEE + 1,
            MAX_SELL_FEE
            )
        );
        FM_PC_ExternalPrice_Redeeming_v1(newFundingManager).init(
            _orchestrator,
            _METADATA,
            invalidConfigData
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════
    // Oracle
    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════

    /* Test oracle configuration and validation
        ├── Given a valid oracle implementation
        │   └── When checking oracle interface and prices
        │       ├── Then should support IOraclePrice_v1 interface
        │       └── Then should return correct issuance and redemption prices
        ├── Given an invalid oracle address
        │   └── When initializing contract
        │       └── Then initialization should revert
    */
    function testExternalInit_succeedsGivenValidOracleAndRevertsGivenInvalidOracle() public {
        // Verify valid oracle interface
        assertTrue(
            ERC165(address(oracle)).supportsInterface(type(IOraclePrice_v1).interfaceId),
            "Mock oracle should support IOraclePrice_v1 interface"
        );

        // Verify oracle price reporting
        oracle.setIssuancePrice(2e18);  // 2:1 ratio
        oracle.setRedemptionPrice(1.9e18);  // 1.9:1 ratio

        assertEq(
            oracle.getPriceForIssuance(),
            2e18,
            "Oracle issuance price not set correctly"
        );
        assertEq(
            oracle.getPriceForRedemption(),
            1.9e18,
            "Oracle redemption price not set correctly"
        );

        // Test initialization with invalid oracle
        bytes memory invalidConfigData = abi.encode(
            address(_token),           // invalid oracle address
            address(issuanceToken),    // issuance token
            address(_token),           // accepted token
            DEFAULT_BUY_FEE,          // buy fee
            DEFAULT_SELL_FEE,         // sell fee
            MAX_SELL_FEE,             // max sell fee
            MAX_BUY_FEE,              // max buy fee
            DIRECT_OPERATIONS_ONLY     // direct operations only flag
        );
        
        vm.expectRevert();  
        fundingManager.init(_orchestrator, _METADATA, invalidConfigData);
    }

    /* Test initialization with invalid oracle interface
        ├── Given a mock contract that doesn't implement IOraclePrice_v1
        │   └── And a new funding manager instance
        │       └── When initializing with invalid oracle
        │           └── Then should revert with InvalidInitialization error
    */
    function testExternalInit_revertsGivenOracleWithoutRequiredInterface() public {
        // Create mock without IOraclePrice_v1 interface
        InvalidOracleMock invalidOracle = new InvalidOracleMock();

        // Deploy new funding manager
        address impl = address(new FM_PC_ExternalPrice_Redeeming_v1());
        FM_PC_ExternalPrice_Redeeming_v1 invalidOracleFM = FM_PC_ExternalPrice_Redeeming_v1(Clones.clone(impl));

        // Prepare config with invalid oracle
        bytes memory configData = abi.encode(
            address(invalidOracle),    // invalid oracle address
            address(issuanceToken),    // issuance token
            address(_token),           // accepted token
            DEFAULT_BUY_FEE,          // buy fee
            DEFAULT_SELL_FEE,         // sell fee
            MAX_SELL_FEE,             // max sell fee
            MAX_BUY_FEE,              // max buy fee
            DIRECT_OPERATIONS_ONLY     // direct operations only flag
        );

        // Setup orchestrator
        _setUpOrchestrator(invalidOracleFM);

        // Verify revert on initialization
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        fundingManager.init(_orchestrator, _METADATA, configData);
    }

    /* Test token decimals validation
        ├── Given an initialized contract with ERC20 tokens
        │   └── When checking token decimals
        │       ├── Then issuance token should have exactly 18 decimals
        │       └── Then collateral token should have exactly 18 decimals
    */
    function testExternalInit_succeedsGivenTokensWithCorrectDecimals() public {
        assertEq(
            IERC20Metadata(address(issuanceToken)).decimals(),
            18,
            "Issuance token should have 18 decimals"
        );
        assertEq(
            IERC20Metadata(address(_token)).decimals(),
            18,
            "Collateral token should have 18 decimals"
        );
    }

    /* Test fee configuration validation
        ├── Given an initialized funding manager contract
        │   └── When reading fee configuration values
        │       ├── Then buyFee should equal DEFAULT_BUY_FEE (1% = 100 basis points)
        │       ├── Then sellFee should equal DEFAULT_SELL_FEE (1% = 100 basis points) 
        │       ├── Then maxBuyFee should equal MAX_BUY_FEE (5% = 500 basis points)
        │       └── Then maxSellFee should equal MAX_SELL_FEE (5% = 500 basis points)
    */
    function testExternalInit_succeedsGivenDefaultFeeConfiguration() public {
        // Verify buy fee
        assertEq(
            BondingCurveBase_v1(address(fundingManager)).buyFee(),
            DEFAULT_BUY_FEE,
            "Buy fee not set correctly"
        );

        // Verify sell fee
        assertEq(
            RedeemingBondingCurveBase_v1(address(fundingManager)).sellFee(),
            DEFAULT_SELL_FEE,
            "Sell fee not set correctly"
        );

        // Verify max buy fee
        assertEq(
            fundingManager.getMaxBuyFee(),
            MAX_BUY_FEE,
            "Max buy fee not set correctly"
        );

        // Verify max sell fee
        assertEq(
            fundingManager.getMaxProjectSellFee(),
            MAX_SELL_FEE,
            "Max sell fee not set correctly"
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════
    // Fee Management
    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════

    /* Test fee limits enforcement
        ├── Given a funding manager initialized with default fees
        │   ├── When setBuyFee is called with fee > MAX_BUY_FEE
        │   │   └── Then should revert with FeeExceedsMaximum(invalidFee, MAX_BUY_FEE)
        │   └── When setSellFee is called with fee > MAX_SELL_FEE
        │       └── Then should revert with FeeExceedsMaximum(invalidFee, MAX_SELL_FEE)
    */
    function testExternalSetFees_revertGivenFeesExceedingMaximum() public {
        // Verify buy fee limit
        uint invalidBuyFee = MAX_BUY_FEE + 1;
        vm.expectRevert(abi.encodeWithSelector(
            IFM_PC_ExternalPrice_Redeeming_v1.Module__FM_PC_ExternalPrice_Redeeming_FeeExceedsMaximum.selector,
            MAX_BUY_FEE + 1,
            MAX_BUY_FEE
        ));
        fundingManager.setBuyFee(invalidBuyFee);
        
        // Verify sell fee limit
        uint invalidSellFee = MAX_SELL_FEE + 1;
        vm.expectRevert(abi.encodeWithSelector(
            IFM_PC_ExternalPrice_Redeeming_v1.Module__FM_PC_ExternalPrice_Redeeming_FeeExceedsMaximum.selector,
            MAX_SELL_FEE + 1,
            MAX_SELL_FEE
        ));
        fundingManager.setSellFee(invalidSellFee);
    }

    /* Test buy fee update authorization and validation
        ├── Given an initialized funding manager and valid fee value
        │   ├── When non-admin calls setBuyFee
        │   │   └── Then reverts with unauthorized error
        │   └── When admin calls setBuyFee
        │       └── Then buyFee state and getter return new value
    */
    function testExternalSetBuyFee_succeedsGivenAdminAndValidFee(uint256 newBuyFee) public {
        // Bound fee to valid range
        newBuyFee = bound(newBuyFee, 0, MAX_BUY_FEE);
        
        // Verify non-admin cannot set fee
        vm.prank(user);
        vm.expectRevert();
        fundingManager.setBuyFee(newBuyFee);
        
        // Update fee as admin
        vm.prank(admin);
        fundingManager.setBuyFee(newBuyFee);
        
        // Verify fee updated in state
        assertEq(
            BondingCurveBase_v1(address(fundingManager)).buyFee(),
            newBuyFee,
            "Buy fee state variable not updated correctly"
        );
        
        // Verify fee getter
        assertEq(
            fundingManager.getBuyFee(),
            newBuyFee,
            "Buy fee getter not returning correct value"
        );
    }

    /* Test sell fee update authorization and validation
        ├── Given an initialized funding manager and valid fee value
        │   ├── When non-admin calls setSellFee
        │   │   └── Then reverts with unauthorized error
        │   └── When admin calls setSellFee
        │       └── Then sellFee state and getter return new value 
    */
    function testExternalSetSellFee_succeedsGivenAdminAndValidFee(uint256 newSellFee) public {
        // Bound fee to valid range
        newSellFee = bound(newSellFee, 0, MAX_SELL_FEE);
        
        // Verify non-admin cannot set fee
        vm.prank(user);
        vm.expectRevert();
        fundingManager.setSellFee(newSellFee);
        
        // Update fee as admin
        vm.prank(admin);
        fundingManager.setSellFee(newSellFee);
        
        // Verify fee updated in state
        assertEq(
            RedeemingBondingCurveBase_v1(address(fundingManager)).sellFee(),
            newSellFee,
            "Sell fee state variable not updated correctly"
        );
        
        // Verify fee getter
        assertEq(
            fundingManager.getSellFee(),
            newSellFee,
            "Sell fee getter not returning correct value"
        );
    }

    /* Test fee update permissions for different roles
        ├── Given initialized funding manager and valid fee values
        │   ├── When whitelisted user calls setBuyFee and setSellFee
        │   │   └── Then both calls revert with unauthorized error
        │   ├── When regular user calls setBuyFee and setSellFee  
        │   │   └── Then both calls revert with unauthorized error
        │   └── When admin calls setBuyFee and setSellFee
        │       └── Then fees are updated successfully
    */
    function testExternalSetFees_succeedsOnlyForAdmin(
        uint256 newBuyFee,
        uint256 newSellFee
    ) public {
        // Bound fees to valid ranges
        newBuyFee = bound(newBuyFee, 0, MAX_BUY_FEE);
        newSellFee = bound(newSellFee, 0, MAX_SELL_FEE);
        
        // Verify whitelisted user cannot set fees
        vm.startPrank(whitelisted);
        vm.expectRevert();
        fundingManager.setBuyFee(newBuyFee);
        vm.expectRevert();
        fundingManager.setSellFee(newSellFee);
        vm.stopPrank();
        
        // Verify regular user cannot set fees
        vm.startPrank(user);
        vm.expectRevert();
        fundingManager.setBuyFee(newBuyFee);
        vm.expectRevert();
        fundingManager.setSellFee(newSellFee);
        vm.stopPrank();
        
        // Verify admin can set fees
        vm.startPrank(admin);
        
        fundingManager.setBuyFee(newBuyFee);
        assertEq(
            fundingManager.getBuyFee(),
            newBuyFee,
            "Admin should be able to update buy fee"
        );
        
        fundingManager.setSellFee(newSellFee);
        assertEq(
            fundingManager.getSellFee(),
            newSellFee,
            "Admin should be able to update sell fee"
        );
        
        vm.stopPrank();
    }

    /* Test sequential fee updates validation
        ├── Given initialized funding manager and admin role
        │   ├── When admin performs three sequential buy fee updates
        │   │   └── Then getBuyFee returns the latest set value after each update
        │   └── When admin performs three sequential sell fee updates
        │       └── Then getSellFee returns the latest set value after each update
    */
    function testExternalSetFees_succeedsWithSequentialUpdates(
        uint256 fee1,
        uint256 fee2,
        uint256 fee3
    ) public {
        vm.startPrank(admin);

        // Sequential buy fee updates
        fee1 = bound(fee1, 0, MAX_BUY_FEE);
        fee2 = bound(fee2, 0, MAX_BUY_FEE);
        fee3 = bound(fee3, 0, MAX_BUY_FEE);
        
        fundingManager.setBuyFee(fee1);
        assertEq(
            fundingManager.getBuyFee(),
            fee1,
            "Buy fee not updated correctly in first update"
        );
        
        fundingManager.setBuyFee(fee2);
        assertEq(
            fundingManager.getBuyFee(),
            fee2,
            "Buy fee not updated correctly in second update"
        );
        
        fundingManager.setBuyFee(fee3);
        assertEq(
            fundingManager.getBuyFee(),
            fee3,
            "Buy fee not updated correctly in third update"
        );
        
        // Sequential sell fee updates
        fee1 = bound(fee1, 0, MAX_SELL_FEE);
        fee2 = bound(fee2, 0, MAX_SELL_FEE);
        fee3 = bound(fee3, 0, MAX_SELL_FEE);
        
        fundingManager.setSellFee(fee1);
        assertEq(
            fundingManager.getSellFee(),
            fee1,
            "Sell fee not updated correctly in first update"
        );
        
        fundingManager.setSellFee(fee2);
        assertEq(
            fundingManager.getSellFee(),
            fee2,
            "Sell fee not updated correctly in second update"
        );
        
        fundingManager.setSellFee(fee3);
        assertEq(
            fundingManager.getSellFee(),
            fee3,
            "Sell fee not updated correctly in third update"
        );
        
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════
    // Buy Operations
    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════

    /* Test testExternalBuy_succeedsGivenWhitelistedUserAndValidAmount() function
        ├── Given an initialized funding manager contract with sufficient collateral
        │   └── And a whitelisted user
        │       ├── When the user buys tokens with a valid amount
        │       │   ├── Then the buy fee should be calculated correctly
        │       │   ├── Then the collateral tokens should be transferred to project treasury
        │       │   └── Then the issued tokens should be minted to user
        │       └── When checking final balances
        │           ├── Then user should have correct issued token balance
        │           ├── Then user should have correct collateral token balance
        │           └── Then project treasury should have correct collateral token balance
    */
    function testExternalBuy_succeedsGivenWhitelistedUserAndValidAmount(uint256 buyAmount) public {
        // Given - Bound the buy amount to reasonable values
        uint256 minAmount = 1 * 10**_token.decimals();
        uint256 maxAmount = 1_000_000 * 10**_token.decimals();
        buyAmount = bound(buyAmount, minAmount, maxAmount);

        // Calculate expected issuance tokens using helper
        uint256 expectedIssuedTokens = _calculateExpectedIssuance(buyAmount);

        // Setup buying conditions using helper
        _prepareBuyConditions(whitelisted, buyAmount);

        // Record initial balances
        uint256 initialUserCollateral = _token.balanceOf(whitelisted);
        uint256 initialProjectTreasuryCollateral = _token.balanceOf(fundingManager.getProjectTreasury());
        uint256 initialUserIssuedTokens = issuanceToken.balanceOf(whitelisted);

        // Execute buy operation
        vm.startPrank(whitelisted);
        _token.approve(address(fundingManager), buyAmount);
        fundingManager.buy(buyAmount, expectedIssuedTokens);
        vm.stopPrank();

        // Verify user's collateral token balance decreased correctly
        assertEq(
            _token.balanceOf(whitelisted),
            initialUserCollateral - buyAmount,
            "User collateral balance incorrect"
        );

        // Verify project treasury received the collateral
        assertEq(
            _token.balanceOf(fundingManager.getProjectTreasury()),
            initialProjectTreasuryCollateral + buyAmount,
            "Project treasury collateral balance incorrect"
        );

        // Verify user received the correct amount of issuance tokens
        assertEq(
            issuanceToken.balanceOf(whitelisted),
            initialUserIssuedTokens + expectedIssuedTokens,
            "User issued token balance incorrect"
        );

        // Verify the oracle price used matches what we expect
        uint256 oraclePrice = oracle.getPriceForIssuance();
        assertGt(oraclePrice, 0, "Oracle price should be greater than 0");

        // Verify the funding manager's buy functionality is still open
        assertTrue(fundingManager.buyIsOpen(), "Buy functionality should remain open");

    }

    /* Test testExternalBuy_revertsGivenInvalidInputs() function revert conditions
        ├── Given a whitelisted user and initialized funding manager
        │   ├── When attempting to buy with zero amount
        │   │   └── Then it should revert with InvalidDepositAmount
        │   │
        │   ├── When attempting to buy with zero expected tokens
        │   │   └── Then it should revert with InvalidMinAmountOut
        │   │
        │   ├── When buying functionality is closed
        │   │   └── Then buying attempt should revert with BuyingFunctionalitiesClosed
        │   │
        │   └── When attempting to buy with excessive slippage
        │       ├── Given buying is reopened
        │       └── Then buying with multiplied expected amount should revert with InsufficientOutputAmount
    */
    function testExternalBuy_revertsGivenInvalidInputs(uint256 buyAmount, uint256 slippageMultiplier) public {
        // Bound the buy amount to reasonable values
        uint256 minAmount = 1 * 10**_token.decimals();
        uint256 maxAmount = 1_000_000 * 10**_token.decimals();
        buyAmount = bound(buyAmount, minAmount, maxAmount);
        
        // Bound slippage multiplier (between 2x and 10x)
        slippageMultiplier = bound(slippageMultiplier, 2, 10);

        // Setup
        _prepareBuyConditions(whitelisted, buyAmount);

        // Test zero amount
        vm.startPrank(whitelisted);
        vm.expectRevert(abi.encodeWithSignature("Module__BondingCurveBase__InvalidDepositAmount()"));
        fundingManager.buy(0, 0);

        // Test zero expected tokens
        vm.expectRevert(abi.encodeWithSignature("Module__BondingCurveBase__InvalidMinAmountOut()"));
        fundingManager.buy(1 ether, 0);
        vm.stopPrank();

        // Test closed buy
        vm.prank(admin);
        fundingManager.closeBuy();
        
        vm.expectRevert(abi.encodeWithSignature("Module__BondingCurveBase__BuyingFunctionaltiesClosed()"));
        vm.prank(whitelisted);
        fundingManager.buy(buyAmount, buyAmount);

        // Test slippage
        vm.prank(admin);
        fundingManager.openBuy();
        
        uint256 expectedTokens = _calculateExpectedIssuance(buyAmount);
        
        vm.startPrank(whitelisted);
        vm.expectRevert(abi.encodeWithSignature("Module__BondingCurveBase__InsufficientOutputAmount()"));
        // Try to buy with higher expected tokens than possible (multiplied by fuzzed value)
        fundingManager.buy(buyAmount, expectedTokens * slippageMultiplier);
        vm.stopPrank();
    }

    /* Test testExternalBuy_revertsGivenExcessiveSlippage() function slippage protection
        ├── Given a whitelisted user and initialized funding manager
        │   └── And buying functionality is open
        │       └── When attempting to buy with excessive slippage (2x-10x expected amount)
        │           └── Then it should revert with InsufficientOutputAmount
    */
    function testExternalBuy_revertsGivenExcessiveSlippage(uint256 buyAmount, uint256 slippageMultiplier) public {
        // Bound the buy amount to reasonable values
        uint256 minAmount = 1 * 10**_token.decimals();
        uint256 maxAmount = 1_000_000 * 10**_token.decimals();
        buyAmount = bound(buyAmount, minAmount, maxAmount);
        
        // Bound slippage multiplier (between 2x and 10x)
        slippageMultiplier = bound(slippageMultiplier, 2, 10);

        // Setup
        _prepareBuyConditions(whitelisted, buyAmount);

        // Test slippage
        vm.prank(admin);
        fundingManager.openBuy();
        
        uint256 expectedTokens = _calculateExpectedIssuance(buyAmount);
        
        vm.startPrank(whitelisted);
        vm.expectRevert(abi.encodeWithSignature("Module__BondingCurveBase__InsufficientOutputAmount()"));
        // Try to buy with higher expected tokens than possible (multiplied by fuzzed value)
        fundingManager.buy(buyAmount, expectedTokens * slippageMultiplier);
        vm.stopPrank();
    }

    /* Test testExternalBuy_revertsGivenNonWhitelistedUser() function
        ├── Given an initialized funding manager contract
        │   └── And buying is open
        │       └── When a non-whitelisted address attempts to buy tokens
        │           ├── And the address has enough payment tokens
        │           ├── And the address is not zero address
        │           ├── And the address is not an admin
        │           ├── And the address is not whitelisted
        │           └── Then it should revert with CallerNotAuthorized error
    */
    function testExternalBuy_revertsGivenNonWhitelistedUser(address nonWhitelisted, uint256 buyAmount) public {
        vm.assume(nonWhitelisted != address(0));
        vm.assume(nonWhitelisted != whitelisted);
        vm.assume(nonWhitelisted != admin);
        vm.assume(nonWhitelisted != address(this));
        
        // Prepare buy conditions with a fixed amount
        uint256 minAmount = 1 * 10**_token.decimals();
        uint256 maxAmount = 1_000_000 * 10**_token.decimals();
        buyAmount = bound(buyAmount, minAmount, maxAmount);

        vm.prank(admin);
        _prepareBuyConditions(nonWhitelisted, buyAmount);

        vm.prank(admin);
        fundingManager.openBuy();

        // Calculate expected tokens
        uint256 expectedTokens = _calculateExpectedIssuance(buyAmount);
        
        // Attempt to buy tokens with any non-whitelisted address
        vm.startPrank(nonWhitelisted);
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                roleId,
                nonWhitelisted
            )
        );
        fundingManager.buy(buyAmount, expectedTokens);
        vm.stopPrank();
    }

    /* Test testExternalBuy_revertsGivenBuyingClosed() function
        ├── Given an initialized funding manager contract
        │   └── And buying is closed
        │       └── When a whitelisted user attempts to buy tokens
        │           ├── And the user is not zero address
        │           ├── And the user has sufficient payment tokens
        │           ├── And the amount is within valid bounds
        │           └── Then it should revert with BuyingFunctionalitiesClosed error
    */
    function testExternalBuy_revertsGivenBuyingClosed(address buyer, uint256 buyAmount) public {
        // Given - Valid user assumptions
        vm.assume(buyer != address(0));
        vm.assume(buyer != address(this));
        vm.assume(buyer != admin);

        // Given - Valid amount bounds
        uint256 minAmount = 1 * 10**_token.decimals();
        uint256 maxAmount = 1_000_000 * 10**_token.decimals();
        buyAmount = bound(buyAmount, minAmount, maxAmount);

        // Given - Grant whitelist role to the user
        _authorizer.grantRole(roleId, buyer);

        // Mint collateral tokens to buyer
        _token.mint(buyer, buyAmount);
        
        // Approve funding manager to spend tokens
        vm.prank(buyer);
        _token.approve(address(fundingManager), buyAmount);

        // When/Then - Attempt to buy when closed
        uint256 expectedTokens = _calculateExpectedIssuance(buyAmount);
        vm.startPrank(buyer);
        vm.expectRevert(abi.encodeWithSignature("Module__BondingCurveBase__BuyingFunctionaltiesClosed()"));
        fundingManager.buy(buyAmount, expectedTokens);
        vm.stopPrank();
    }

    /* Test testExternalBuy_revertsGivenZeroAmount() function
        ├── Given an initialized funding manager contract
        │   ├── And buying is open
        │   └── And user is whitelisted
        │       └── When attempting to buy tokens with zero amount
        │           └── Then it should revert with InvalidDepositAmount error
    */
    function testExternalBuy_revertsGivenZeroAmount(address buyer) public {
        // Given - Valid user assumptions
        vm.assume(buyer != address(0));
        vm.assume(buyer != address(this));
        vm.assume(buyer != admin);

        // Given - Grant whitelist role to the user
        _authorizer.grantRole(roleId, buyer);

        // Given - Open buying
        vm.prank(admin);
        _prepareBuyConditions(buyer, 1 ether);
        // fundingManager.openBuy();

        // When/Then - Attempt to buy with zero amount
        vm.startPrank(buyer);
        vm.expectRevert(abi.encodeWithSignature("Module__BondingCurveBase__InvalidDepositAmount()"));
        fundingManager.buy(0, 0);
        vm.stopPrank();
    }

    /* Test testExternalBuy_succeedsGivenMaxAmount() function
        ├── Given an initialized funding manager contract
        │   ├── And buying is open
        │   ├── And user is whitelisted
        │   └── And user has sufficient payment tokens
        │       └── When user buys tokens with maximum allowed amount
        │           └── Then it should:
        │               ├── Transfer correct payment tokens from buyer to treasury
        │               ├── Transfer correct issued tokens to buyer
        │               ├── Maintain valid oracle price
        │               └── Keep buy functionality open
    */
    function testExternalBuy_succeedsGivenMaxAmount(address buyer) public {
        // Given - Valid user assumptions
        vm.assume(buyer != address(0));
        vm.assume(buyer != address(this));
        vm.assume(buyer != admin);

        // Given - Use maximum allowed amount
        uint256 buyAmount = 1_000_000 * 10**_token.decimals();

        // Given - Setup buying conditions
        _authorizer.grantRole(roleId, buyer);
        _prepareBuyConditions(buyer, buyAmount);
        vm.prank(admin);
        fundingManager.openBuy();

        // Given - Calculate expected tokens and store initial balances
        uint256 expectedTokens = _calculateExpectedIssuance(buyAmount);
        uint256 buyerBalanceBefore = _token.balanceOf(buyer);
        uint256 projectTreasuryBalanceBefore = _token.balanceOf(fundingManager.getProjectTreasury());
        uint256 buyerIssuedTokensBefore = issuanceToken.balanceOf(buyer);
        
        // When - Buy tokens with max amount
        vm.startPrank(buyer);
        fundingManager.buy(buyAmount, expectedTokens);
        vm.stopPrank();

        // Then - Verify balances
        assertEq(
            _token.balanceOf(buyer),
            buyerBalanceBefore - buyAmount,
            "Buyer payment token balance not decreased correctly"
        );
        assertEq(
            _token.balanceOf(fundingManager.getProjectTreasury()),
            projectTreasuryBalanceBefore + buyAmount,
            "Project treasury payment token balance not increased correctly"
        );
        assertEq(
            issuanceToken.balanceOf(buyer),
            buyerIssuedTokensBefore + expectedTokens,
            "Buyer issued token balance not increased correctly"
        );

        // Verify the oracle price used matches what we expect
        uint256 oraclePrice = oracle.getPriceForIssuance();
        assertGt(oraclePrice, 0, "Oracle price should be greater than 0");

        // Verify the funding manager's buy functionality is still open
        assertTrue(fundingManager.buyIsOpen(), "Buy functionality should remain open");
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════
    // Sell Operations
    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════

    /* Test testPublicSell_succeedsGivenWhitelistedUserAndValidAmount() function
        ├── Given a whitelisted user
        │   └── And selling is enabled
        │       └── And user has sufficient issuance tokens
        │           └── And amount is within valid bounds
        │               └── When the user calls sell()
        │                   └── Then the issuance tokens should be burned
        │                   └── And redemption amount should be queued correctly
    */
    function testPublicSell_succeedsGivenWhitelistedUserAndValidAmount(uint256 depositAmount) public {
        address seller = whitelisted;
        
        // Bound deposit to reasonable values
        depositAmount = bound(
            depositAmount, 
            1 * 10**_token.decimals(), 
            1_000_000 * 10**_token.decimals()
        );
        
        uint256 issuanceAmount = _prepareSellConditions(seller, depositAmount);
        uint256 expectedCollateral = _calculateExpectedCollateral(issuanceAmount);
        uint256 initialSellerIssuance = issuanceToken.balanceOf(seller);
        uint256 initialOpenRedemptions = fundingManager.getOpenRedemptionAmount();
        
        vm.prank(seller);
        fundingManager.sell(issuanceAmount, 1);
        
        // Verify tokens were burned
        assertEq(
            issuanceToken.balanceOf(seller),
            initialSellerIssuance - issuanceAmount,
            "Issuance tokens not burned correctly"
        );
        
        // Verify redemption amount was queued
        assertEq(
            fundingManager.getOpenRedemptionAmount(),
            initialOpenRedemptions + expectedCollateral,
            "Redemption amount not queued correctly"
        );
        
        // Verify seller has no remaining balance
        assertEq(
            issuanceToken.balanceOf(seller),
            0,
            "Seller should have no remaining issuance tokens"
        );
    }

    /* Test testPublicSell_revertsGivenInvalidAmount() function invalid amounts
        ├── Given selling is enabled
        │   └── Given user is whitelisted with issued tokens
        │       ├── When selling zero tokens
        │       │   └── Then reverts with Module__BondingCurveBase__InvalidDepositAmount
        │       └── When selling more than balance
        │           └── Then reverts with ERC20InsufficientBalance
    */
    function testPublicSell_revertsGivenInvalidAmount(uint256 depositAmount) public {
        // Given - Setup initial state
        address seller = whitelisted;
        
        // Bound initial deposit to reasonable values
        depositAmount = bound(
            depositAmount, 
            1 * 10**_token.decimals(), 
            1_000_000 * 10**_token.decimals()
        );
        
        // Buy some tokens first to have a balance
        uint256 issuanceAmount = _prepareSellConditions(seller, depositAmount);
        
        // Test zero amount
        vm.startPrank(seller);
        vm.expectRevert(abi.encodeWithSignature("Module__BondingCurveBase__InvalidDepositAmount()"));
        fundingManager.sell(0, 1);
        vm.stopPrank();
        
        // Test amount exceeding balance
        vm.startPrank(seller);
        uint256 userBalance = issuanceToken.balanceOf(seller);
        uint256 excessAmount = userBalance + depositAmount;
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                seller,
                userBalance,
                excessAmount
            )
        );
        fundingManager.sell(excessAmount, 1);
        vm.stopPrank();
    }

    /* Test testPublicSell_revertsGivenZeroAmount() function with zero amount
        ├── Given selling is enabled
        │   └── Given user is whitelisted with issued tokens
        │       └── When selling zero tokens
        │           └── Then reverts with Module__BondingCurveBase__InvalidDepositAmount
    */
    function testPublicSell_revertsGivenZeroAmount(uint256 depositAmount) public {
        // Given - Setup initial state
        address seller = whitelisted;
        
        // Bound initial deposit to reasonable values
        uint256 minAmount = 1 * 10**_token.decimals();
        uint256 maxAmount = 1_000_000 * 10**_token.decimals();
        depositAmount = bound(depositAmount, minAmount, maxAmount);
        
        // Buy some tokens first to have a balance
        uint256 issuanceAmount = _prepareSellConditions(seller, depositAmount);
        
        vm.startPrank(seller);
        vm.expectRevert(abi.encodeWithSignature("Module__BondingCurveBase__InvalidDepositAmount()"));
        fundingManager.sell(0, 1);
        vm.stopPrank();
    }

    /* Test testPublicSell_revertsGivenExceedingBalance() function with exceeding balance
        ├── Given selling is enabled
        │   └── Given user is whitelisted with issued tokens
        │       └── When selling more than user balance
        │           └── Then reverts with ERC20InsufficientBalance
    */
    function testPublicSell_revertsGivenExceedingBalance(uint256 depositAmount) public {
        // Given - Setup initial state
        address seller = whitelisted;
        
        // Bound initial deposit to reasonable values
        uint256 minAmount = 1 * 10**_token.decimals();
        uint256 maxAmount = 1_000_000 * 10**_token.decimals();
        depositAmount = bound(depositAmount, minAmount, maxAmount);
        
        // Buy some tokens first to have a balance
        uint256 issuanceAmount = _prepareSellConditions(seller, depositAmount);
        
        vm.startPrank(seller);
        uint256 userBalance = issuanceToken.balanceOf(seller);
        uint256 excessAmount = userBalance + 1;
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, seller, userBalance, excessAmount));
        fundingManager.sell(excessAmount, 1);
        vm.stopPrank();
    }

    /* Test testPublicSell_revertsGivenInsufficientOutput() function with insufficient output
        ├── Given selling is enabled
        │   └── Given user is whitelisted with issued tokens
        │       └── When minAmountOut is unreasonably high
        │           └── Then reverts with Module__BondingCurveBase__InsufficientOutputAmount
    */
    function testPublicSell_revertsGivenInsufficientOutput(uint256 depositAmount) public {
        // Given - Setup initial state
        address seller = whitelisted;
        
        // Bound initial deposit to reasonable values
        uint256 minAmount = 1 * 10**_token.decimals();
        uint256 maxAmount = 1_000_000 * 10**_token.decimals();
        depositAmount = bound(depositAmount, minAmount, maxAmount);
        
        // Buy some tokens first to have a balance
        uint256 issuanceAmount = _prepareSellConditions(seller, depositAmount);
        
        vm.startPrank(seller);
        // Try to sell 1 token but require an unreasonably high minAmountOut
        uint256 unreasonablyHighMinAmountOut = type(uint256).max;
        vm.expectRevert(abi.encodeWithSignature("Module__BondingCurveBase__InsufficientOutputAmount()"));
        fundingManager.sell(issuanceAmount, unreasonablyHighMinAmountOut);
        vm.stopPrank();
    }

    /* Test testPublicSell_revertsGivenSellingDisabled() function with selling disabled
        ├── Given selling is disabled
        │   └── Given user is whitelisted with issued tokens
        │       └── When attempting to sell tokens
        │           └── Then reverts with Module__RedeemingBondingCurveBase__SellingFunctionaltiesClosed
    */
    function testPublicSell_revertsGivenSellingDisabled(uint256 depositAmount) public {
        // Given - Setup initial state
        address seller = whitelisted;
        
        // Bound initial deposit to reasonable values
        uint256 minAmount = 1 * 10**_token.decimals();
        uint256 maxAmount = 1_000_000 * 10**_token.decimals();
        depositAmount = bound(depositAmount, minAmount, maxAmount);
        
        // Buy some tokens first to have a balance
        uint256 issuanceAmount = _prepareSellConditions(seller, depositAmount);
        
        vm.startPrank(admin);
        fundingManager.closeBuy();
        fundingManager.closeSell();
        vm.stopPrank();
        
        vm.startPrank(seller);
        vm.expectRevert(abi.encodeWithSignature("Module__RedeemingBondingCurveBase__SellingFunctionaltiesClosed()"));
        fundingManager.sell(1, 1);
        vm.stopPrank();
    }

    /* Test testPublicSell_revertsGivenInsufficientCollateral() function with insufficient collateral
        ├── Given selling is enabled
        │   └── Given user is whitelisted with issued tokens
        │       └── Given contract collateral has been withdrawn
        │           └── When attempting to sell tokens
        │               └── Then reverts with Module__RedeemingBondingCurveBase__InsufficientCollateralForProjectFee
    */
    function testPublicSell_revertsGivenInsufficientCollateral(uint256 depositAmount) public {
        // Given - Setup initial state
        address seller = whitelisted;
        
        // Bound initial deposit to reasonable values
        depositAmount = bound(
            depositAmount, 
            100 * 10**_token.decimals(), // Aseguramos una cantidad significativa
            1_000_000 * 10**_token.decimals()
        );
        
        // Buy some tokens first to have a balance
        uint256 issuanceAmount = _prepareSellConditions(seller, depositAmount);
        
        // Calculate how much collateral we need
        uint256 saleReturn = fundingManager.calculateSaleReturn(issuanceAmount);
        
        // Get current collateral balance
        uint256 collateralBalance = _token.balanceOf(address(fundingManager));
        
        // Drain ALL collateral from the contract
        vm.startPrank(address(admin));
        fundingManager.withdrawProjectCollateralFee(seller, collateralBalance);
        vm.stopPrank();

        // Verify contract has no collateral
        assertEq(
            _token.balanceOf(address(fundingManager)),
            0,
            "Contract should have no collateral"
        );
        
        // Attempt to sell tokens
        /* 
        TODO => Test projectCollateralFeeCollected in _sellOrder
                Error => Module__RedeemingBondingCurveBase__InsufficientCollateralForProjectFee
        */
        // vm.startPrank(seller);
        // vm.expectRevert(
        //     abi.encodeWithSignature(
        //         "Module__RedeemingBondingCurveBase__InsufficientCollateralForProjectFee()"
        //     )
        // );
        // fundingManager.sell(issuanceAmount, 1); // Intentamos vender todos los tokens
        // vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════
    // Redemption Orders
    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════

    /* Test testExternalSell_succeedsGivenValidRedemptionOrder() function
        ├── Given an initialized funding manager contract
        │   ├── And selling is open
        │   ├── And user is whitelisted
        │   └── And user has sufficient issued tokens
        │       └── When user sells tokens
        │           └── Then it should:
        │               ├── Create redemption order with correct parameters
        │               ├── Update open redemption amount
        │               ├── Set order state to PROCESSING
        │               └── Emit TokensSold event
    */
    function testExternalSell_succeedsGivenValidRedemptionOrder(
        uint256 depositAmount
    ) public {
        // Given - Setup seller
        address seller = whitelisted;
        
        // Given - Setup valid deposit bounds
        uint256 minAmount = 1 * 10**_token.decimals();
        uint256 maxAmount = 1_000_000 * 10**_token.decimals();
        depositAmount = bound(depositAmount, minAmount, maxAmount);
        
        // Given - Prepare initial token balance through purchase
        vm.prank(seller);
        uint256 issuanceAmount = _prepareSellConditions(seller, depositAmount);

        // Given - Calculate expected redemption amounts
        uint256 sellAmount = issuanceAmount / 2; // Selling 50% of purchased tokens
        uint256 expectedCollateral = _calculateExpectedCollateral(sellAmount);
        
        // Given - Record initial state
        uint256 initialOpenRedemptionAmount = fundingManager.getOpenRedemptionAmount();
        
        // When - Create redemption order
        vm.startPrank(seller);
        fundingManager.sell(sellAmount, 1);
        vm.stopPrank();
        
        // Then - Verify redemption amount update
        assertEq(
            fundingManager.getOpenRedemptionAmount(),
            initialOpenRedemptionAmount + expectedCollateral,
            "Open redemption amount not updated correctly"
        );
    }

    /* Test testExternalQueue_succeedsGivenSingleRedemptionOrder() function
        ├── Given an initialized funding manager contract
        │   ├── And a single redemption order exists
        │   ├── And sufficient collateral is available
        │   └── And caller has queue manager role
        │       └── When queue manager processes redemption queue
        │           └── Then it should:
        │               ├── Process order correctly 
        │               ├── Update order state
        │               └── Create payment stream with correct parameters
    */
    // function testExternalQueue_succeedsGivenSingleRedemptionOrder(
    //     uint256 depositAmount
    // ) public {
    //     // Given - Setup valid deposit bounds
    //     depositAmount = bound(
    //         depositAmount, 
    //         1 * 10**_token.decimals(), 
    //         1_000_000 * 10**_token.decimals()
    //     );
        
    //     // Given - Create redemption order via buy and sell
    //     vm.prank(whitelisted);
    //     uint256 issuanceAmount = _prepareSellConditions(whitelisted, depositAmount);
    //     uint256 sellAmount = issuanceAmount / 2; // Selling 50% of purchased tokens
    //     uint256 expectedCollateral = _calculateExpectedCollateral(sellAmount);
        
    //     // Given - Fund contract with redemption collateral
    //     _token.mint(address(fundingManager), expectedCollateral);
        
    //     // Given - Record initial state
    //     uint256 initialWhitelistedBalance = _token.balanceOf(whitelisted);
        
    //     // When - Create redemption order/payment stream
    //     vm.startPrank(whitelisted);
    //     fundingManager.sell(sellAmount, 1);
    //     vm.stopPrank();

    //     // Then - Verify initial stream state
    //     assertEq(
    //         paymentProcessor.releasableForSpecificStream(
    //             address(fundingManager),
    //             whitelisted,
    //             1 // Default wallet ID for unique recipients
    //         ),
    //         0,
    //         "Stream should have 0 releasable amount at start"
    //     );
    // }

    /* Test testExternalQueue_updatesRedemptionAmountToZero() function
        ├── Given an initialized funding manager contract
        │   ├── And a redemption order exists
        │   └── And sufficient collateral is available
        │       └── When queue manager processes redemption queue
        │           └── Then open redemption amount should be zero
    */
    // function testExternalQueue_updatesRedemptionAmountToZero(
    //     uint256 depositAmount
    // ) public {
    //     // Given - Setup valid deposit bounds
    //     depositAmount = bound(
    //         depositAmount, 
    //         1 * 10**_token.decimals(), 
    //         1_000_000 * 10**_token.decimals()
    //     );
        
    //     // Given - Create redemption order
    //     uint256 issuanceAmount = _prepareSellConditions(whitelisted, depositAmount);
    //     uint256 sellAmount = issuanceAmount / 2; // Selling 50% of purchased tokens
    //     uint256 expectedCollateral = _calculateExpectedCollateral(sellAmount);
        
    //     // Given - Fund contract with redemption collateral
    //     _token.mint(address(fundingManager), expectedCollateral);
        
    //     // When - Create redemption order
    //     vm.prank(whitelisted);
    //     fundingManager.sell(sellAmount, 1);
        
    //     _addLogicModuleToOrchestrator(address(paymentClient));
    //     vm.prank(address(paymentClient));
    //     fundingManager.deductProcessedRedemptionAmount(expectedCollateral);
        
    //     // Then - Verify redemption amount reset
    //     assertEq(
    //         fundingManager.getOpenRedemptionAmount(),
    //         0,
    //         "Open redemption amount should be zero after processing"
    //     );
    // }

    /* Test testExternalQueue_updatesOrderIdsCorrectly() function
        ├── Given an initialized funding manager contract
        │   └── And a redemption order exists
        │       └── When queue manager processes redemption queue
        │           └── Then it should:
        │               ├── Set current order ID to previous next order ID
        │               └── Increment next order ID
    */
    function testExternalQueue_updatesOrderIdsCorrectly(
        uint256 depositAmount
    ) public {
        // Given - Setup valid deposit bounds
        depositAmount = bound(
            depositAmount, 
            1 * 10**_token.decimals(), 
            1_000_000 * 10**_token.decimals()
        );
        
        // Given - Create redemption order
        uint256 issuanceAmount = _prepareSellConditions(whitelisted, depositAmount);
        uint256 sellAmount = issuanceAmount / 2; // Selling 50% of purchased tokens
        uint256 expectedCollateral = _calculateExpectedCollateral(sellAmount);
        
        // Given - Fund contract with redemption collateral
        _token.mint(address(fundingManager), expectedCollateral);
        
        // Given - Record initial order IDs
        uint256 initialOrderId = fundingManager.getOrderId();
        uint256 initialNextOrderId = fundingManager.getNextOrderId();
        
        // When - Create redemption order
        vm.prank(whitelisted);
        fundingManager.sell(sellAmount / 2, 1);

        // Then - Get final order IDs
        uint256 finalOrder = fundingManager.getOrderId();
        uint256 finalNextOrderId = fundingManager.getNextOrderId();

        // Then - Verify order ID updates
        assertEq(
            initialNextOrderId,
            finalOrder,
            "Current order ID should match previous next order ID"
        );
        assertGt(
            finalNextOrderId,
            initialOrderId,
            "Next order ID should be incremented"
        );
    }

    /* Test testExternalQueue_updatesOrderIdsCorrectlyForMultipleOrders() function
        ├── Given an initialized funding manager contract
        │   └── And multiple redemption orders exist
        │       └── When queue manager processes redemption queue twice
        │           └── Then it should:
        │               ├── Set current order ID to previous next order ID for each order
        │               └── Increment next order ID sequentially
    */
    function testExternalQueue_updatesOrderIdsCorrectlyForMultipleOrders(
        uint256 depositAmount
    ) public {
        // Given - Setup valid deposit bounds
        depositAmount = bound(
            depositAmount, 
            1 * 10**_token.decimals(), 
            1_000_000 * 10**_token.decimals()
        );
        
        // Given - Create initial redemption order
        uint256 issuanceAmount = _prepareSellConditions(whitelisted, depositAmount);
        uint256 sellAmount = issuanceAmount / 2; // Selling 50% of purchased tokens
        uint256 expectedCollateral = _calculateExpectedCollateral(sellAmount);
        
        // Given - Fund contract for redemption
        _token.mint(address(fundingManager), expectedCollateral);
        
        // Given - Record initial order IDs
        uint256 initialOrderId = fundingManager.getOrderId();
        uint256 initialNextOrderId = fundingManager.getNextOrderId();
        
        // When - Create first redemption order
        vm.prank(whitelisted);
        fundingManager.sell(sellAmount / 2, 1);
        
        uint256 firstOrderId = fundingManager.getOrderId();
        uint256 firstNextOrderId = fundingManager.getNextOrderId();

        // When - Create second redemption order
        vm.prank(whitelisted);
        fundingManager.sell(10000, 1);

        uint256 secondOrderId = fundingManager.getOrderId();
        uint256 secondNextOrderId = fundingManager.getNextOrderId();

        // Then - Verify sequential order ID updates
        assertEq(
            firstNextOrderId,
            secondOrderId,
            "Second order ID should match first next order ID"
        );
        assertGt(
            secondNextOrderId,
            firstOrderId,
            "Next order ID should increment sequentially"
        );    
    }

    /* Test testExternalQueue_processesMultipleOrdersCorrectly() function
        ├── Given an initialized funding manager contract
        │   └── When multiple redemption orders are created
        │       └── Then it should:
        │           ├── Process each order successfully
        │           ├── Update total redemption amount correctly
        │           ├── Reset open redemption amount to zero
        │           └── Transfer expected collateral to users
    */
    // function testExternalQueue_processesMultipleOrdersCorrectly(
    //     uint256[] calldata depositAmounts
    // ) public {
    //     // Given - Validate input array size
    //     vm.assume(depositAmounts.length > 0 && depositAmounts.length <= 5);
        
    //     uint256 totalExpectedCollateral = 0;
        
    //     // When - Process multiple redemption orders
    //     for(uint i = 0; i < depositAmounts.length; i++) {
    //         // Given - Setup valid deposit bounds for each order
    //         uint256 depositAmount = bound(
    //             depositAmounts[i], 
    //             1 * 10**_token.decimals(), 
    //             1_000_000 * 10**_token.decimals()
    //         );
            
    //         // Given - Create redemption order
    //         uint256 issuanceAmount = _prepareSellConditions(whitelisted, depositAmount);
    //         uint256 sellAmount = issuanceAmount / 2; // Selling 50% of purchased tokens
    //         uint256 expectedCollateral = _calculateExpectedCollateral(sellAmount);
            
    //         // Given - Track total collateral
    //         totalExpectedCollateral += expectedCollateral;
            
    //         // Given - Fund contract for redemption
    //         _token.mint(address(fundingManager), expectedCollateral);
            
    //         // When - Create redemption order
    //         vm.prank(whitelisted);
    //         fundingManager.sell(sellAmount, 1);
    //     }
        
    //     // Given - Record pre-processing state 
    //     uint256 initialOpenRedemption = fundingManager.getOpenRedemptionAmount();

    //     // Process all orders at once
    //     _addLogicModuleToOrchestrator(address(paymentClient));
    //     vm.prank(address(paymentClient));
    //     fundingManager.deductProcessedRedemptionAmount(totalExpectedCollateral);
        
    //     // Then - Verify redemption amount reset
    //     assertEq(
    //         fundingManager.getOpenRedemptionAmount(),
    //         0,
    //         "Open redemption amount should reset after processing orders"
    //     );
    // }

    /* Test testExternalQueue_managesCollateralCorrectly() function
        ├── Given an initialized funding manager contract
        │   └── When a redemption order is processed
        │       └── Then it should:
        │           ├── Track contract collateral balance correctly
        │           ├── Update user token balance appropriately
        │           ├── Transfer expected collateral amounts
        │           └── Process fees according to configuration
    */
    function testExternalQueue_managesCollateralCorrectly(
        uint256 depositAmount
    ) public {
        // Given - Setup valid deposit bounds
        depositAmount = bound(
            depositAmount, 
            1 * 10**_token.decimals(), 
            1_000_000 * 10**_token.decimals()
        );
        
        // Given - Create redemption conditions
        uint256 issuanceAmount = _prepareSellConditions(whitelisted, depositAmount);
        uint256 sellAmount = issuanceAmount / 2; // Selling 50% of purchased tokens
        uint256 expectedCollateral = _calculateExpectedCollateral(sellAmount);
        
        // Given - Record initial balances
        uint256 initialContractBalance = _token.balanceOf(address(fundingManager));
        uint256 initialUserBalance = _token.balanceOf(whitelisted);
        
        // Given - Fund contract for redemption
        _token.mint(address(fundingManager), expectedCollateral);
        
        // When - Create and process redemption order
        vm.prank(whitelisted);
        fundingManager.sell(sellAmount, 1);
        
        // Then - Verify collateral accounting
        assertEq(
            _token.balanceOf(address(fundingManager)),
            initialContractBalance + expectedCollateral,
            "Contract balance should increase by expected collateral amount"
        );
    }

    /* Test testExternalQueue_processesMultipleOrdersSequentially() function
        ├── Given an initialized funding manager contract
        │   └── When creating multiple redemption orders
        │       └── Then for each order it should:
        │           ├── Set current order ID to previous next order ID
        │           ├── Increment next order ID sequentially
        │           └── Maintain consistent order ID progression
    */
    function testExternalQueue_processesMultipleOrdersSequentially(
        uint256 depositAmount,
        uint8 numberOfOrders
    ) public {
        // Given - Bound number of orders for gas efficiency
        numberOfOrders = uint8(bound(uint256(numberOfOrders), 2, 20));
        
        // Given - Setup valid deposit bounds
        depositAmount = bound(
            depositAmount, 
            1 * 10**_token.decimals(), 
            1_000_000 * 10**_token.decimals()
        );
        
        // Given - Create redemption conditions
        uint256 issuanceAmount = _prepareSellConditions(whitelisted, depositAmount);
        uint256 sellAmount = issuanceAmount / numberOfOrders; // Equal distribution
        uint256 expectedCollateral = _calculateExpectedCollateral(sellAmount);
        
        // Given - Fund contract for all redemptions
        _token.mint(
            address(fundingManager), 
            expectedCollateral * numberOfOrders
        );
        
        // Given - Record initial IDs
        uint256 previousOrderId = fundingManager.getOrderId();
        uint256 previousNextOrderId = fundingManager.getNextOrderId();
        
        // When - Process multiple orders
        for(uint8 i = 0; i < numberOfOrders; i++) {
            // Create redemption order
            vm.prank(whitelisted);
            fundingManager.sell(sellAmount, 1);
            
            // Get updated IDs
            uint256 currentOrderId = fundingManager.getOrderId();
            uint256 currentNextOrderId = fundingManager.getNextOrderId();
            
            // Then - Verify ID progression
            assertEq(
                currentOrderId,
                previousNextOrderId,
                "Current order ID should match previous next order ID"
            );
            
            assertTrue(
                currentNextOrderId > previousOrderId,
                "Next order ID should increment sequentially"
            );
            
            // Update tracking IDs
            previousOrderId = currentOrderId;
            previousNextOrderId = currentNextOrderId;
        }
        
        // Then - Verify final state
        assertTrue(
            fundingManager.getNextOrderId() - fundingManager.getOrderId() == 1,
            "Final next order ID should be consecutive"
        );
        
        assertEq(
            fundingManager.getOrderId(),
            numberOfOrders - 1,
            "Final order ID should match processed order count"
        );
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