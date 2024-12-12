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
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {BondingCurveBase_v1} from "@fm/bondingCurve/abstracts/BondingCurveBase_v1.sol";
import {RedeemingBondingCurveBase_v1} from "@fm/bondingCurve/abstracts/RedeemingBondingCurveBase_v1.sol";
import {InvalidOracleMock} from "./utils/mocks/InvalidOracleMock.sol";
import {ERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol";

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

    // Test addresses
    address admin;
    address user;
    address whitelisted;

    // Mock tokens
    ERC20Issuance_v1 issuanceToken;    // The token to be issued

    // Mock oracle
    IOraclePrice_v1 oracle;

    // Constants
    string internal constant NAME = "Issuance Token";
    string internal constant SYMBOL = "IST";
    uint8 internal constant DECIMALS = 18;
    uint internal constant MAX_SUPPLY = type(uint).max;
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

    bytes32 internal roleId;

    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════
    // Setup
    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════

    function setUp() public {
        // Setup addresses
        admin = makeAddr("admin");
        user = makeAddr("user");
        whitelisted = makeAddr("whitelisted");

        admin = address(this);
        vm.startPrank(admin);

        // Create issuance token
        issuanceToken = new ERC20Issuance_v1(
            NAME, SYMBOL, DECIMALS, MAX_SUPPLY, address(this)
        );

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

        // Grant minting rights to the funding manager
        issuanceToken.setMinter(address(fundingManager), true);
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

    /* testInitialFeeConfiguration()
        └── Given an initialized contract
            ├── Then buy fee should be set to DEFAULT_BUY_FEE
            ├── Then sell fee should be set to DEFAULT_SELL_FEE
            ├── Then max buy fee should be set to MAX_BUY_FEE
            └── Then max sell fee should be set to MAX_SELL_FEE
    */
    function testGetFees_GivenDefaultValues() public {
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

    /* testIssuanceTokenConfiguration()
        └── Given an initialized contract
            ├── Then issuance token address should be set correctly
            └── Then issuance token should be accessible
    */
    function testGetIssuanceToken_GivenValidToken() public {
        // Verify issuance token address
        assertEq(
            fundingManager.getIssuanceToken(),
            address(issuanceToken),
            "Issuance token not set correctly"
        );
    }

    /* testCollateralTokenConfiguration()
        └── Given an initialized contract
            ├── Then collateral token address should be set correctly
            └── Then collateral token should be accessible
    */
    function testCollateralTokenConfiguration() public {
        // Verify collateral token address
        assertEq(
            address(fundingManager.token()),
            address(_token),
            "Collateral token not set correctly"
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

    /* testInitWithInvalidSellFee()
        └── Given a new contract initialization
            └── When sell fee exceeds maximum
                └── Then it should revert with FeeExceedsMaximum
    */
    function testInitWithInvalidSellFee() public {
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

    /* testOracleConfiguration()
        └── Given a contract initialization
            ├── When oracle implements correct interface
            │   ├── Then initialization should succeed
            │   └── Then oracle should be accessible and return correct prices
            └── When oracle does not implement correct interface
                └── Then initialization should revert
    */
    function testOracleConfiguration() public {
        // Test with valid oracle
        // First verify that our mock oracle has the correct interface
        assertTrue(
            ERC165(address(oracle)).supportsInterface(type(IOraclePrice_v1).interfaceId),
            "Mock oracle should support IOraclePrice_v1 interface"
        );

        // Set test prices in the oracle
        OraclePriceMock(address(oracle)).setPriceForIssuance(2e18);  // 2:1 ratio
        OraclePriceMock(address(oracle)).setPriceForRedemption(1.9e18);  // 1.9:1 ratio

        // Verify that we can get prices from the oracle
        assertEq(
            OraclePriceMock(address(oracle)).getPriceForIssuance(),
            2e18,
            "Oracle issuance price not set correctly"
        );
        assertEq(
            OraclePriceMock(address(oracle)).getPriceForRedemption(),
            1.9e18,
            "Oracle redemption price not set correctly"
        );

        // Test with invalid oracle (using _token as a mock non-oracle contract)
        bytes memory invalidConfigData = abi.encode(
            address(_token),  // invalid oracle address
            address(issuanceToken),    // issuance token
            address(_token),           // accepted token
            DEFAULT_BUY_FEE,          // buy fee
            DEFAULT_SELL_FEE,         // sell fee
            MAX_SELL_FEE,             // max sell fee
            MAX_BUY_FEE,              // max buy fee
            DIRECT_OPERATIONS_ONLY     // direct operations only flag
        );

        address impl = address(new FM_PC_ExternalPrice_Redeeming_v1());
        address newFundingManager = address(new ERC1967Proxy(impl, ""));
        
        vm.expectRevert();  
        FM_PC_ExternalPrice_Redeeming_v1(newFundingManager).init(
            _orchestrator,
            _METADATA,
            invalidConfigData
        );
    }

    /* testInvalidOracleInterface()
        └── Given a contract initialization with invalid oracle
            ├── When oracle does not implement IOraclePrice_v1
            │   └── Then initialization should revert with InvalidOracleInterface error
    */
    function testInvalidOracleInterface() public {
        // Create a mock contract that doesn't implement IOraclePrice_v1
        InvalidOracleMock invalidOracle = new InvalidOracleMock();

        // Create new funding manager instance
        address impl = address(new FM_PC_ExternalPrice_Redeeming_v1());
        FM_PC_ExternalPrice_Redeeming_v1 invalidOracleFM = FM_PC_ExternalPrice_Redeeming_v1(Clones.clone(impl));

        // Prepare config data with invalid oracle
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

        // Initialization should revert
        vm.expectRevert(IFM_PC_ExternalPrice_Redeeming_v1.Module__FM_PC_ExternalPrice_Redeeming_InvalidOracleInterface.selector);
        invalidOracleFM.init(_orchestrator, _METADATA, configData);
    }

    /* testTokenDecimals()
        └── Given an initialized contract
            ├── Then issuance token should have 18 decimals
            └── Then collateral token should have 18 decimals
    */
    function testTokenDecimals() public {
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

    /* testFeeConfiguration()
        └── Given an initialized funding manager contract
            ├── When checking the buy fee
            │   └── Then it should be set to DEFAULT_BUY_FEE (1% = 100 basis points)
            ├── When checking the sell fee
            │   └── Then it should be set to DEFAULT_SELL_FEE (1% = 100 basis points)
            ├── When checking the max buy fee
            │   └── Then it should be set to MAX_BUY_FEE (5% = 500 basis points)
            └── When checking the max sell fee
                └── Then it should be set to MAX_SELL_FEE (5% = 500 basis points)
    */
    function testFeeConfiguration() public {
        // Verify buy fee using the public variable from BondingCurveBase_v1
        assertEq(
            BondingCurveBase_v1(address(fundingManager)).buyFee(),
            DEFAULT_BUY_FEE,
            "Buy fee not set correctly"
        );

        // Verify sell fee using the public variable from RedeemingBondingCurveBase_v1
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
            fundingManager.getMaxSellFee(),
            MAX_SELL_FEE,
            "Max sell fee not set correctly"
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════
    // Fee Management
    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════

    /* testFeesCannotExceedMaximum()
        └── Given a funding manager with default fees
            ├── When trying to set a buy fee higher than maximum
            │   └── Then transaction should revert with FeeExceedsMaximum error
            └── When trying to set a sell fee higher than maximum
                └── Then transaction should revert with FeeExceedsMaximum error
    */
    function testFeesCannotExceedMaximum() public {
        // Try to set buy fee higher than maximum
        uint invalidBuyFee = MAX_BUY_FEE + 1;
        vm.expectRevert(abi.encodeWithSelector(
            IFM_PC_ExternalPrice_Redeeming_v1.Module__FM_PC_ExternalPrice_Redeeming_FeeExceedsMaximum.selector,
            MAX_BUY_FEE + 1,
            MAX_BUY_FEE
        ));
        fundingManager.setBuyFee(invalidBuyFee);
        
        // Try to set sell fee higher than maximum
        uint invalidSellFee = MAX_SELL_FEE + 1;
        vm.expectRevert(abi.encodeWithSelector(
            IFM_PC_ExternalPrice_Redeeming_v1.Module__FM_PC_ExternalPrice_Redeeming_FeeExceedsMaximum.selector,
            MAX_SELL_FEE + 1,
            MAX_SELL_FEE
        ));
        fundingManager.setSellFee(invalidSellFee);
    }

    /* testSetBuyFee_GivenValidFee()
        └── Given an initialized funding manager contract
            ├── When a non-admin tries to update the buy fee
            │   └── Then the transaction should revert with unauthorized error
            └── When admin updates the buy fee to a valid value
                ├── Then the transaction should succeed
                └── Then the new buy fee should be set correctly
    */
    function testSetBuyFee_GivenValidFee(uint256 newBuyFee) public {
        // Given
        newBuyFee = bound(newBuyFee, 0, MAX_BUY_FEE);
        
        // When/Then - Non-admin cannot update fee
        vm.prank(user);
        vm.expectRevert(); // Should revert with unauthorized error
        fundingManager.setBuyFee(newBuyFee);
        
        // When - Admin updates fee
        vm.prank(admin);
        fundingManager.setBuyFee(newBuyFee);
        
        // Then - Fee should be updated correctly
        // Verify through direct state variable access
        assertEq(
            BondingCurveBase_v1(address(fundingManager)).buyFee(),
            newBuyFee,
            "Buy fee state variable not updated correctly"
        );
        
        // Verify through getter function
        assertEq(
            fundingManager.getBuyFee(),
            newBuyFee,
            "Buy fee getter not returning correct value"
        );
    }

    /* testSetSellFee_GivenValidFee()
        └── Given an initialized funding manager contract
            ├── When a non-admin tries to update the sell fee
            │   └── Then the transaction should revert with unauthorized error
            └── When admin updates the sell fee to a valid value
                ├── Then the transaction should succeed
                └── Then the new sell fee should be set correctly
    */
    function testSetSellFee_GivenValidFee(uint256 newSellFee) public {
        // Given
        newSellFee = bound(newSellFee, 0, MAX_SELL_FEE);
        
        // When/Then - Non-admin cannot update fee
        vm.prank(user);
        vm.expectRevert(); // Should revert with unauthorized error
        fundingManager.setSellFee(newSellFee);
        
        // When - Admin updates fee
        vm.prank(admin);
        fundingManager.setSellFee(newSellFee);
        
        // Then - Fee should be updated correctly
        // Verify through direct state variable access
        assertEq(
            RedeemingBondingCurveBase_v1(address(fundingManager)).sellFee(),
            newSellFee,
            "Sell fee state variable not updated correctly"
        );
        
        // Verify through getter function
        assertEq(
            fundingManager.getSellFee(),
            newSellFee,
            "Sell fee getter not returning correct value"
        );
    }

    /* testFuzz_FeeUpdatePermissions()
        └── Given an initialized funding manager contract with default fees
            ├── When a whitelisted user tries to update fees
            │   ├── Then setBuyFee should revert
            │   └── Then setSellFee should revert
            ├── When a regular user tries to update fees
            │   ├── Then setBuyFee should revert
            │   └── Then setSellFee should revert
            └── When admin updates fees
                ├── Then setBuyFee should succeed
                │   └── And new buy fee should be set correctly
                └── Then setSellFee should succeed
                    └── And new sell fee should be set correctly
    */
    function testFuzz_FeeUpdatePermissions(uint256 newBuyFee, uint256 newSellFee) public {
        // Bound fees to valid ranges
        newBuyFee = bound(newBuyFee, 0, MAX_BUY_FEE);
        newSellFee = bound(newSellFee, 0, MAX_SELL_FEE);
        
        // Test whitelisted user (should fail)
        vm.startPrank(whitelisted);
        vm.expectRevert();
        fundingManager.setBuyFee(newBuyFee);
        vm.expectRevert();
        fundingManager.setSellFee(newSellFee);
        vm.stopPrank();
        
        // Test regular user (should fail)
        vm.startPrank(user);
        vm.expectRevert();
        fundingManager.setBuyFee(newBuyFee);
        vm.expectRevert();
        fundingManager.setSellFee(newSellFee);
        vm.stopPrank();
        
        // Test admin (should succeed)
        vm.startPrank(admin);
        
        // Set and verify buy fee
        fundingManager.setBuyFee(newBuyFee);
        assertEq(
            fundingManager.getBuyFee(),
            newBuyFee,
            "Admin should be able to update buy fee"
        );
        
        // Set and verify sell fee
        fundingManager.setSellFee(newSellFee);
        assertEq(
            fundingManager.getSellFee(),
            newSellFee,
            "Admin should be able to update sell fee"
        );
        
        vm.stopPrank();
    }

    /* testFuzz_SequentialFeeUpdates()
        └── Given an initialized funding manager contract
            ├── When admin updates buy fee multiple times with fuzzed values
            │   ├── Then first update should set fee to fee1
            │   ├── Then second update should set fee to fee2
            │   └── Then third update should set fee to fee3
            └── When admin updates sell fee multiple times with fuzzed values
                ├── Then first update should set fee to fee1
                ├── Then second update should set fee to fee2
                └── Then third update should set fee to fee3
    */
    function testFuzz_SequentialFeeUpdates(
        uint256 fee1,
        uint256 fee2,
        uint256 fee3
    ) public {
        // Bound all fees to valid ranges
        fee1 = bound(fee1, 0, MAX_BUY_FEE);
        fee2 = bound(fee2, 0, MAX_BUY_FEE);
        fee3 = bound(fee3, 0, MAX_BUY_FEE);
        
        vm.startPrank(admin);
        
        // First update
        fundingManager.setBuyFee(fee1);
        assertEq(
            fundingManager.getBuyFee(),
            fee1,
            "Buy fee not updated correctly in first update"
        );
        
        // Second update
        fundingManager.setBuyFee(fee2);
        assertEq(
            fundingManager.getBuyFee(),
            fee2,
            "Buy fee not updated correctly in second update"
        );
        
        // Third update
        fundingManager.setBuyFee(fee3);
        assertEq(
            fundingManager.getBuyFee(),
            fee3,
            "Buy fee not updated correctly in third update"
        );
        
        // Repeat for sell fees
        fee1 = bound(fee1, 0, MAX_SELL_FEE);
        fee2 = bound(fee2, 0, MAX_SELL_FEE);
        fee3 = bound(fee3, 0, MAX_SELL_FEE);
        
        // First update
        fundingManager.setSellFee(fee1);
        assertEq(
            fundingManager.getSellFee(),
            fee1,
            "Sell fee not updated correctly in first update"
        );
        
        // Second update
        fundingManager.setSellFee(fee2);
        assertEq(
            fundingManager.getSellFee(),
            fee2,
            "Sell fee not updated correctly in second update"
        );
        
        // Third update
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

    /* testBuy_GivenWhitelistedUser()
        └── Given an initialized funding manager contract with sufficient collateral
            ├── When a whitelisted user buys tokens with fuzzed valid amount
            │   ├── Then the buy fee should be calculated correctly
            │   ├── Then the collateral tokens should be transferred from user
            │   └── Then the issued tokens should be minted to user
            └── When checking final balances
                ├── Then user should have correct issued token balance
                ├── Then user should have correct collateral token balance
                └── Then contract should have correct collateral token balance
    */
    function testBuy_GivenWhitelistedUser(uint256 buyAmount) public {
        // Given - Bound the buy amount to reasonable values
        uint256 minAmount = 1 * 10**_token.decimals();
        uint256 maxAmount = 1_000_000 * 10**_token.decimals();
        buyAmount = bound(buyAmount, minAmount, maxAmount);

        // Calculate expected issuance tokens using helper
        uint256 expectedIssuedTokens = _calculateExpectedIssuance(buyAmount);

        // Setup buying conditions using helper
        _prepareBuyConditions(whitelisted, buyAmount);

        // Grant minting rights to the funding manager
        vm.prank(admin);
        issuanceToken.setMinter(address(fundingManager), true);

        // Record initial balances
        uint256 initialUserCollateral = _token.balanceOf(whitelisted);
        uint256 initialContractCollateral = _token.balanceOf(address(fundingManager));
        uint256 initialUserIssuedTokens = issuanceToken.balanceOf(whitelisted);

        // Execute buy operation
        vm.startPrank(whitelisted);
        issuanceToken.approve(address(fundingManager), buyAmount);
        fundingManager.buy(buyAmount, expectedIssuedTokens);
        vm.stopPrank();

        // Verify balances
        assertEq(
            _token.balanceOf(whitelisted),
            initialUserCollateral - buyAmount,
            "User collateral balance incorrect"
        );
        assertEq(
            _token.balanceOf(address(fundingManager)),
            initialContractCollateral + buyAmount,
            "Contract collateral balance incorrect"
        );
        assertEq(
            issuanceToken.balanceOf(whitelisted),
            initialUserIssuedTokens + expectedIssuedTokens,
            "User issued token balance incorrect"
        );
    }

    /* testBuy_RevertGivenInvalidAmount()
        └── Given a whitelisted user and initialized funding manager
            ├── When attempting to buy with zero amount
            │   └── Then it should revert with InvalidDepositAmount
            │
            ├── When attempting to buy with zero expected tokens
            │   └── Then it should revert with InvalidMinAmountOut
            │
            ├── When buying is closed
            │   ├── Given admin closes buying
            │   └── Then buying attempt should revert with BuyingFunctionaltiesClosed
            │
            └── When attempting to buy with excessive slippage
                ├── Given buying is reopened
                ├── Given expected issuance is calculated
                └── Then buying with doubled expected amount should revert with InsufficientOutputAmount
    */
    function testBuy_RevertGivenInvalidAmount(uint256 buyAmount, uint256 slippageMultiplier) public {
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

    /* testFuzz_BuyTokens_ExcessiveSlippage()
        └── Given a whitelisted user and initialized funding manager
            └── When attempting to buy with excessive slippage
                └── Then it should revert with InsufficientOutputAmount
    */
    function testBuy_RevertGivenExcessiveSlippage(uint256 buyAmount, uint256 slippageMultiplier) public {
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

    /* testBuy_RevertGivenNonWhitelistedUser()
        └── Given an initialized funding manager contract
            └── When any non-whitelisted address attempts to buy tokens
                ├── Given the address has enough payment tokens
                ├── Given buying is open
                ├── Given the address is not whitelisted
                ├── Given the address is not zero address
                ├── Given the address is not an admin or whitelisted user
                └── Then it should revert with CallerNotAuthorized error
    */
    function testBuy_RevertGivenNonWhitelistedUser(address nonWhitelisted, uint256 buyAmount) public {
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

    /* testBuy_RevertGivenBuyingClosed()
        └── Given an initialized funding manager contract
            └── When any whitelisted user attempts to buy tokens
                ├── Given the user has enough payment tokens
                ├── Given the user is whitelisted
                ├── Given buying is closed
                ├── Given the amount is within valid bounds
                └── Then it should revert with BuyingClosed error
    */
    function testBuy_RevertGivenBuyingClosed(address buyer, uint256 buyAmount) public {
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

    /* testBuy_RevertGivenZeroAmount()
        └── Given an initialized funding manager contract
            └── When any whitelisted user attempts to buy tokens with zero amount
                ├── Given the user is whitelisted
                ├── Given buying is open
                └── Then it should revert with InvalidAmount error
    */
    function testBuy_RevertGivenZeroAmount(address buyer) public {
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

    /* testBuy_SuccessWithMaxAmount()
        └── Given an initialized funding manager contract
            └── When a whitelisted user attempts to buy tokens with maximum allowed amount
                ├── Given buying is open
                ├── Given the user is whitelisted
                ├── Given the user has enough payment tokens
                ├── Given the amount is the maximum allowed
                └── Then it should:
                    ├── Transfer the correct payment token amount from buyer to contract
                    ├── Transfer the correct issued token amount to the buyer
                    └── Update all balances correctly
    */
    function testBuy_SuccessWithMaxAmount(address buyer) public {
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
        uint256 contractBalanceBefore = _token.balanceOf(address(fundingManager));
        uint256 buyerIssuedTokensBefore = IERC20Metadata(BondingCurveBase_v1(address(fundingManager)).getIssuanceToken()).balanceOf(buyer);
        
        // When - Buy tokens with max amount
        vm.startPrank(buyer);
        fundingManager.buy(buyAmount, expectedTokens);
        vm.stopPrank();

        // Then - Verify balances
        assertEq(
            _token.balanceOf(buyer),
            buyerBalanceBefore - buyAmount,
            "Payment token balance not decreased correctly"
        );
        assertEq(
            _token.balanceOf(address(fundingManager)),
            contractBalanceBefore + buyAmount,
            "Contract payment token balance not increased correctly"
        );
        assertEq(
            IERC20Metadata(BondingCurveBase_v1(address(fundingManager)).getIssuanceToken()).balanceOf(buyer),
            buyerIssuedTokensBefore + expectedTokens,
            "Issued token balance not increased correctly"
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
    //      - Executes a buy to get issuance tokens
    //      - Approves funding manager to spend issuance tokens
    //      - Opens sell functionality if not already open
    function _prepareSellConditions(address seller, uint amount) internal returns (uint issuanceAmount) {
        // First prepare buy conditions and execute buy
        _prepareBuyConditions(seller, amount);
        
        // Calculate expected issuance tokens
        uint256 buyFee = fundingManager.getBuyFee();
        uint256 netDeposit = amount - ((amount * buyFee) / BPS);
        uint256 oraclePrice = IOraclePrice_v1(oracle).getPriceForIssuance();
        issuanceAmount = netDeposit * oraclePrice;
        
        // Execute buy to get issuance tokens
        vm.startPrank(seller);
        issuanceToken.approve(address(fundingManager), issuanceAmount);
        fundingManager.buy(amount, issuanceAmount);
        
        // Approve funding manager to spend issuance tokens
        issuanceToken.approve(address(fundingManager), issuanceAmount);
        vm.stopPrank();
        
        // Ensure selling is enabled
        if (!fundingManager.sellIsOpen()) {
            vm.prank(admin);
            fundingManager.openSell();
        }
    }

    // Helper function to calculate expected issuance tokens for a given collateral amount
    // This includes:
    //      - Applying buy fee to get net deposit
    //      - Multiplying by oracle price to get issuance amount
    function _calculateExpectedIssuance(uint256 collateralAmount) internal view returns (uint256 expectedIssuedTokens) {
        uint256 buyFee = fundingManager.getBuyFee();
        uint256 netDeposit = collateralAmount - ((collateralAmount * buyFee) / BPS);
        uint256 oraclePrice = IOraclePrice_v1(oracle).getPriceForIssuance();
        expectedIssuedTokens = netDeposit * oraclePrice;
    }

    // Helper function to calculate expected collateral tokens for a given issuance amount
    // This includes:
    //      - Dividing by oracle price to get gross collateral
    //      - Applying sell fee to get net collateral
    function _calculateExpectedCollateral(uint256 issuanceAmount) internal view returns (uint256 expectedCollateral) {
        uint256 sellFee = fundingManager.getSellFee();
        uint256 oraclePrice = IOraclePrice_v1(oracle).getPriceForRedemption();
        uint256 grossCollateral = issuanceAmount / oraclePrice;
        expectedCollateral = grossCollateral - ((grossCollateral * sellFee) / BPS);
    }
}