// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {IERC20Metadata} from
    "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IOraclePrice_v1} from
    "src/modules/fundingManager/oracle/interfaces/IOraclePrice_v1.sol";
import {LM_ManualExternalPriceSetter_v1} from
    "src/modules/fundingManager/oracle/LM_ManualExternalPriceSetter_v1.sol";
import {LM_ManualExternalPriceSetter_v1_Exposed} from
    "test/modules/fundingManager/oracle/utils/mocks/LM_ManualExternalPriceSetter_v1_exposed.sol";
import {ILM_ManualExternalPriceSetter_v1} from
    "src/modules/fundingManager/oracle/interfaces/ILM_ManualExternalPriceSetter_v1.sol";
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {MockERC20} from
    "test/modules/fundingManager/oracle/utils/mocks/MockERC20.sol";
import {AuthorizerV1Mock} from "test/utils/mocks/modules/AuthorizerV1Mock.sol";
import {OrchestratorV1Mock} from
    "test/utils/mocks/orchestrator/OrchestratorV1Mock.sol";

import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "test/modules/ModuleTest.sol";
import {Clones} from "@oz/proxy/Clones.sol";
import {OZErrors} from "test/utils/errors/OZErrors.sol";
import {Module_v1} from "src/modules/base/Module_v1.sol";

contract LM_ManualExternalPriceSetter_v1_Test is ModuleTest {
    LM_ManualExternalPriceSetter_v1_Exposed priceSetter;
    AuthorizerV1Mock authorizer;

    address admin;
    address priceSetter_;
    address user;

    MockERC20 inputToken;
    MockERC20 outputToken;

    bytes32 constant PRICE_SETTER_ROLE = "PRICE_SETTER_ROLE";
    uint8 constant INTERNAL_DECIMALS = 18;

    // Module Constants
    uint constant MAJOR_VERSION = 1;
    uint constant MINOR_VERSION = 0;
    uint constant PATCH_VERSION = 0;
    string constant URL = "https://github.com/organization/module";
    string constant TITLE = "Module";


    function setUp() public {
        admin = makeAddr("admin");
        priceSetter_ = makeAddr("priceSetter");
        user = makeAddr("user");

        vm.startPrank(admin);

        // Create mock tokens with different decimals
        inputToken = new MockERC20(6); // Like USDC
        outputToken = new MockERC20(18); // Like most ERC20s

        // Setup orchestrator and authorizer
        authorizer = new AuthorizerV1Mock();
        _authorizer = authorizer;

        // Setup price setter
        address impl = address(new LM_ManualExternalPriceSetter_v1_Exposed());
        priceSetter = LM_ManualExternalPriceSetter_v1_Exposed(Clones.clone(impl));

        bytes memory configData = abi.encode(address(inputToken), address(outputToken));

        _setUpOrchestrator(priceSetter);

        priceSetter.init(_orchestrator, _METADATA, configData);

        // Grant price setter role
        bytes32 roleId = _authorizer.generateRoleId(address(priceSetter), PRICE_SETTER_ROLE);
        _authorizer.grantRole(roleId, priceSetter_);

        vm.stopPrank();
    }

    //--------------------------------------------------------------------------
    // Test: Initialization
    
    /* testInit()
        Tests initialization of the oracle contract
        
        Tree structure:
        └── Given a newly deployed oracle contract
            └── When checking the orchestrator address
                └── Then it should match the provided orchestrator
    */
    function testInit() public override(ModuleTest) {
        assertEq(address(priceSetter.orchestrator()),address(_orchestrator),"Orchestrator not set correctly");
    }

    /* testReinitFails()
        └── Given an initialized contract
            └── When trying to initialize again
                └── Then it should revert with InvalidInitialization
    */
    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        priceSetter.init(_orchestrator, _METADATA, abi.encode(address(inputToken), address(outputToken)));
    }

    /* testSupportsInterface()
        └── Given the contract interface
            └── When checking interface support
                └── Then it should support ILM_ManualExternalPriceSetter_v1
    */
    function testSupportsInterface() public {
        assertTrue(
            priceSetter.supportsInterface(
                type(ILM_ManualExternalPriceSetter_v1).interfaceId
            )
        );
    }

    //--------------------------------------------------------------------------
    // Test: Token Configuration

    /* test_TokenProperties()
        ├── Given the input token (USDC mock)
        │   ├── When checking its decimals
        │   │   └── Then it should have 6 decimals
        │   ├── When checking its name
        │   │   └── Then it should be "Mock Token"
        │   ├── When checking its symbol
        │   │   └── Then it should be "MOCK"
        │   └── When checking its initial supply
        │       └── Then it should be 0
        └── Given the output token (TOKEN mock)
            ├── When checking its decimals
            │   └── Then it should have 18 decimals
            ├── When checking its name
            │   └── Then it should be "Mock Token"
            ├── When checking its symbol
            │   └── Then it should be "MOCK"
            └── When checking its initial supply
                └── Then it should be 0
    */
    function test_TokenProperties() public {
        // Test input token (USDC mock)
        assertEq(inputToken.decimals(), 6, "Input token should have 6 decimals");
        assertEq(inputToken.name(), "Mock Token", "Input token should have correct name");
        assertEq(inputToken.symbol(), "MOCK", "Input token should have correct symbol");
        assertEq(inputToken.totalSupply(), 0, "Input token should have 0 initial supply");
        
        // Test output token (TOKEN mock)
        assertEq(outputToken.decimals(), 18, "Output token should have 18 decimals");
        assertEq(outputToken.name(), "Mock Token", "Output token should have correct name");
        assertEq(outputToken.symbol(), "MOCK", "Output token should have correct symbol");
        assertEq(outputToken.totalSupply(), 0, "Output token should have 0 initial supply");
    }

    //--------------------------------------------------------------------------
    // Test: Price Setting and Validation

    /* test_InitialSetup()
        └── Given no prices have been set
            ├── When querying issuance price
            │   └── Then it should revert with InvalidPrice
            └── When querying redemption price
                └── Then it should revert with InvalidPrice
    */
    function test_InitialSetup() public {
        // Verify initial prices revert
        vm.expectRevert(abi.encodeWithSignature("Module__LM_ExternalPriceSetter__InvalidPrice()"));
        priceSetter.getPriceForIssuance();

        vm.expectRevert(abi.encodeWithSignature("Module__LM_ExternalPriceSetter__InvalidPrice()"));
        priceSetter.getPriceForRedemption();
    }

    /* test_SetIssuancePrice_Fuzz()
        ├── Given a non-authorized user and random price
        │   └── When setting issuance price
        │       └── Then it should revert with NotPriceSetter
        ├── Given an authorized price setter
        │   ├── When setting a zero price
        │   │   └── Then it should revert with InvalidPrice
        │   └── When setting a valid random price
        │       └── Then the price should be set and normalized correctly
    */
    function test_SetIssuancePrice_Fuzz(uint256 price, address unauthorizedUser) public {
        // Assume valid unauthorized user
        vm.assume(unauthorizedUser != address(0));
        vm.assume(unauthorizedUser != address(this));
        vm.assume(unauthorizedUser != priceSetter_);
        
        price = bound(price, 1, 1_000_000_000_000 * 1e6);

        // Test unauthorized access with random price
        vm.startPrank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSignature("Module__CallerNotAuthorized(bytes32,address)", _authorizer.generateRoleId(address(priceSetter), PRICE_SETTER_ROLE), unauthorizedUser));
        priceSetter.setIssuancePrice(price);
        vm.stopPrank();

        // Test zero price with authorized user
        vm.startPrank(priceSetter_);
        vm.expectRevert(abi.encodeWithSignature("Module__LM_ExternalPriceSetter__InvalidPrice()"));
        priceSetter.setIssuancePrice(0);

        // Test valid price setting with random price
        priceSetter.setIssuancePrice(price);
        // Price should be normalized from 6 decimals to 18 decimals
        assertEq(priceSetter.getPriceForIssuance(), price * 1e12, "Issuance price not set correctly");

        vm.stopPrank();
    }

    /* test_SetRedemptionPrice_Fuzz()
        ├── Given an unauthorized user
        │   └── When trying to set redemption price
        │       └── Then it should revert with NotPriceSetter error
        ├── Given an authorized price setter and zero price
        │   └── When setting redemption price to zero
        │       └── Then it should revert with InvalidPrice error
        ├── Given an authorized price setter and valid price
        │   └── When setting redemption price
        │       └── Then the price should be set correctly with 18 decimals
        └── Given both redemption and issuance prices are set
            └── When modifying issuance price
                ├── Then redemption price should remain unchanged
                └── Then both prices should maintain their correct decimal precision
                    ├── Redemption: 18 decimals
                    └── Issuance: 6 decimals
    */
    function test_SetRedemptionPrice_Fuzz(uint256 price, address unauthorizedUser) public {
        // Assume valid unauthorized user
        vm.assume(unauthorizedUser != address(0));
        vm.assume(unauthorizedUser != address(this));
        vm.assume(unauthorizedUser != priceSetter_);
        
        price = bound(price, 1e18, 1_000_000_000_000 * 1e18);

        // Test unauthorized access
        vm.startPrank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSignature("Module__CallerNotAuthorized(bytes32,address)", _authorizer.generateRoleId(address(priceSetter), PRICE_SETTER_ROLE), unauthorizedUser));
        priceSetter.setRedemptionPrice(price);
        vm.stopPrank();

        // Test zero price with authorized user
        vm.startPrank(priceSetter_);
        vm.expectRevert(abi.encodeWithSignature("Module__LM_ExternalPriceSetter__InvalidPrice()"));
        priceSetter.setRedemptionPrice(0);

        // Test valid price setting
        priceSetter.setRedemptionPrice(price);
        assertEq(priceSetter.getPriceForRedemption(), price, "Redemption price not set correctly");

        // Test price independence by setting a different issuance price
        uint256 issuancePrice = price / 1e12 + 1; // Convert to 6 decimals for issuance
        priceSetter.setIssuancePrice(issuancePrice);
        
        // Verify both prices maintain their values independently
        assertEq(priceSetter.getPriceForRedemption(), price, "Redemption price changed unexpectedly");
        assertEq(priceSetter.getPriceForIssuance(), issuancePrice * 1e12, "Issuance price not set correctly");

        vm.stopPrank();
    }

    /* test_PriceNormalization_Fuzz
        Tests the price normalization function with different decimal configurations
        
        Tree structure:
        ├── Given a random price and decimals (1-24)
        │   ├── When decimals < 18
        │   │   ├── Then should scale up price correctly
        │   │   └── Then scaling should be reversible
        │   ├── When decimals > 18
        │   │   ├── Then should scale down price correctly
        │   │   └── Then rounding error should be within bounds
        │   └── When decimals = 18
        │       └── Then price should remain unchanged
        └── Given minimum price (1)
            ├── When decimals < 18: should scale up to 10^(18-decimals)
            ├── When decimals > 18: should round to 0
            └── When decimals = 18: should remain 1
    */
    function test_PriceNormalization_Fuzz(uint256 price, uint8 decimals) public {
        vm.assume(price < type(uint256).max / 1e18);
        decimals = uint8(bound(decimals, 1, 24));

        uint256 normalizedPrice = priceSetter.exposed_normalizePrice(price, decimals);
        uint256 scaleFactor = decimals < 18 ? 10 ** (18 - decimals) : 10 ** (decimals - 18);

        if (decimals < 18) {
            // Scaling up (e.g., USDC-6, WBTC-8)
            assertEq(normalizedPrice, price * scaleFactor, "Scaling up failed");
            assertEq(normalizedPrice / scaleFactor, price, "Not reversible");
        } else if (decimals > 18) {
            // Scaling down (tokens with more than 18 decimals)
            assertEq(normalizedPrice, price / scaleFactor, "Scaling down failed");
            assertTrue(price - (normalizedPrice * scaleFactor) < scaleFactor, "High rounding error");
        } else {
            // No scaling (18 decimals like ETH)
            assertEq(normalizedPrice, price, "Price changed unnecessarily");
        }

        // Edge case: minimum price (1)
        if (price == 1) {
            uint256 minPrice = priceSetter.exposed_normalizePrice(1, decimals);
            assertEq(
                minPrice,
                decimals < 18 ? scaleFactor : decimals > 18 ? 0 : 1,
                "Minimum price handling failed"
            );
        }
    }
}
