// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IOraclePrice_v1} from "src/modules/fundingManager/oracle/interfaces/IOraclePrice_v1.sol";
import {FM_PC_ExternalPrice_Redeeming_v1} from "src/modules/fundingManager/oracle/FM_PC_ExternalPrice_Redeeming_v1.sol";
import {IFM_PC_ExternalPrice_Redeeming_v1} from "src/modules/fundingManager/oracle/interfaces/IFM_PC_ExternalPrice_Redeeming_v1.sol";
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
import "./utils/mocks/OraclePriceMock.sol";

contract FM_PC_ExternalPrice_Redeeming_v1_Test is ModuleTest {
    FM_PC_ExternalPrice_Redeeming_v1 fundingManager;
    AuthorizerV1Mock authorizer;

    // Test addresses
    address admin;
    address user;
    address whitelisted;

    // Mock tokens
    MockERC20 collateralToken;  // The token accepted for payment (like USDC)
    MockERC20 issuanceToken;    // The token to be issued

    // Mock oracle
    IOraclePrice_v1 oracle;

    // Constants
    bytes32 constant WHITELIST_ROLE = "WHITELIST_ROLE";
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

    function setUp() public {
        // Setup addresses
        admin = makeAddr("admin");
        user = makeAddr("user");
        whitelisted = makeAddr("whitelisted");

        vm.startPrank(admin);

        // Create mock tokens with different decimals
        collateralToken = new MockERC20(6);  // Like USDC
        issuanceToken = new MockERC20(18);   // Like most ERC20s

        // Setup orchestrator and authorizer
        authorizer = new AuthorizerV1Mock();
        _authorizer = authorizer;

        // Setup oracle
        oracle = new OraclePriceMock();

        // Setup funding manager
        address impl = address(new FM_PC_ExternalPrice_Redeeming_v1());
        fundingManager = FM_PC_ExternalPrice_Redeeming_v1(Clones.clone(impl));

        // Prepare config data
        bytes memory configData = abi.encode(
            address(oracle),           // oracle address
            address(issuanceToken),    // issuance token
            address(collateralToken),  // accepted token
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
        bytes32 roleId = _authorizer.generateRoleId(address(fundingManager), WHITELIST_ROLE);
        _authorizer.grantRole(roleId, whitelisted);

        vm.stopPrank();
    }

    //--------------------------------------------------------------------------
    // Test: Initialization
    
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
            address(collateralToken),  // accepted token
            DEFAULT_BUY_FEE,          // buy fee
            DEFAULT_SELL_FEE,         // sell fee
            MAX_SELL_FEE,             // max sell fee
            MAX_BUY_FEE,              // max buy fee
            DIRECT_OPERATIONS_ONLY     // direct operations only flag
        );

        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        fundingManager.init(_orchestrator, _METADATA, configData);
    }

        //--------------------------------------------------------------------------
    // Test: Configuration

    /* testInitialFeeConfiguration()
        └── Given an initialized contract
            ├── Then buy fee should be set to DEFAULT_BUY_FEE
            ├── Then sell fee should be set to DEFAULT_SELL_FEE
            ├── Then max buy fee should be set to MAX_BUY_FEE
            └── Then max sell fee should be set to MAX_SELL_FEE
    */
    function testInitialFeeConfiguration() public {
        assertEq(
            fundingManager.buyFee(),
            DEFAULT_BUY_FEE,
            "Buy fee not set correctly"
        );
        assertEq(
            fundingManager.sellFee(),
            DEFAULT_SELL_FEE,
            "Sell fee not set correctly"
        );
        assertEq(
            fundingManager.getMaxBuyFee(),
            MAX_BUY_FEE,
            "Max buy fee not set correctly"
        );
        assertEq(
            fundingManager.getMaxSellFee(),
            MAX_SELL_FEE,
            "Max sell fee not set correctly"
        );
    }

    /* testInitWithInvalidBuyFee()
        └── Given a new contract initialization
            └── When buy fee exceeds maximum
                └── Then it should revert with FeeExceedsMaximum
    */
    function testInitWithInvalidBuyFee() public {
        bytes memory invalidConfigData = abi.encode(
            address(oracle),           // oracle address
            address(issuanceToken),    // issuance token
            address(collateralToken),  // accepted token
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

    /* testInitWithInvalidSellFee()
        └── Given a new contract initialization
            └── When sell fee exceeds maximum
                └── Then it should revert with FeeExceedsMaximum
    */
    function testInitWithInvalidSellFee() public {
        bytes memory invalidConfigData = abi.encode(
            address(oracle),           // oracle address
            address(issuanceToken),    // issuance token
            address(collateralToken),  // accepted token
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
}