// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import {Test, console} from "forge-std/Test.sol"; // @todo remove
import {LM_ManualExternalPriceSetter_v1} from
    "src/modules/logicModule/LM_ManualExternalPriceSetter_v1.sol";
import {ILM_ManualExternalPriceSetter_v1} from
    "@lm/interfaces/ILM_ManualExternalPriceSetter_v1.sol";
import {LM_ManualExternalPriceSetter_v1} from
    "src/modules/logicModule/LM_ManualExternalPriceSetter_v1.sol";
import {ERC20Decimals_Mock} from "test/utils/mocks/ERC20Decimals_Mock.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
import {AuthorizerV1Mock} from "test/utils/mocks/modules/AuthorizerV1Mock.sol";
import {Clones} from "@oz/proxy/Clones.sol";
import {OZErrors} from "test/utils/errors/OZErrors.sol";
import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "test/modules/ModuleTest.sol";

/**
 * @title LM_ManualExternalPriceSetter_v1_Test
 * @notice Test contract for LM_ManualExternalPriceSetter_v1
 */
contract LM_ManualExternalPriceSetter_v1_Test is ModuleTest {
    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════
    // Storage
    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════

    LM_ManualExternalPriceSetter_v1 priceSetter;

    address admin;
    address priceSetter_;
    address user;

    ERC20Decimals_Mock inputToken;
    ERC20Mock outputToken;

    bytes32 constant PRICE_SETTER_ROLE = "PRICE_SETTER_ROLE";
    uint8 constant INTERNAL_DECIMALS = 18;
    string constant TOKEN_NAME = "MOCK USDC";
    string constant TOKEN_SYMBOL = "M-USDC";

    // Module Constants
    uint constant MAJOR_VERSION = 1;
    uint constant MINOR_VERSION = 0;
    uint constant PATCH_VERSION = 0;
    string constant URL = "https://github.com/organization/module"; // @todo update with module information
    string constant TITLE = "Module";

    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════
    // Setup
    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════

    function setUp() public {
        admin = makeAddr("admin");
        priceSetter_ = makeAddr("priceSetter");
        user = makeAddr("user");

        vm.startPrank(admin);

        // Create mock tokens with different decimals
        inputToken = new ERC20Decimals_Mock(TOKEN_NAME, TOKEN_SYMBOL, 6); // Like USDC
        outputToken = _token; // Like most ERC20s

        // Setup price setter
        address impl = address(new LM_ManualExternalPriceSetter_v1());
        priceSetter = LM_ManualExternalPriceSetter_v1(Clones.clone(impl));

        bytes memory configData =
            abi.encode(address(inputToken), address(outputToken));

        _setUpOrchestrator(priceSetter);

        priceSetter.init(_orchestrator, _METADATA, configData);

        // Grant price setter role
        bytes32 roleId =
            _authorizer.generateRoleId(address(priceSetter), PRICE_SETTER_ROLE);
        _authorizer.grantRole(roleId, priceSetter_);

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════
    // Initialization Tests
    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════

    /* testInit()
        Tests initialization of the oracle contract
        
        Tree structure:
        └── Given a newly deployed oracle contract
            └── When checking the orchestrator address
                └── Then it should match the provided orchestrator
    */
    function testInit() public override(ModuleTest) {
        assertEq(
            address(priceSetter.orchestrator()),
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
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        priceSetter.init(
            _orchestrator,
            _METADATA,
            abi.encode(address(inputToken), address(outputToken))
        );
    }

    /* testSupportsInterface_GivenValidInterface()
        └── Given the contract interface
            └── When checking interface support
                └── Then it should support ILM_ManualExternalPriceSetter_v1
    */
    function testSupportsInterface_GivenValidInterface() public {
        assertTrue(
            priceSetter.supportsInterface(
                type(ILM_ManualExternalPriceSetter_v1).interfaceId
            )
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════
    // Token Configuration Tests
    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════

    /* testTokenProperties_GivenTokensWithDifferentDecimals()
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
    function testTokenProperties_GivenTokensWithDifferentDecimals() public {
        // Test input token (USDC mock)
        assertEq(inputToken.decimals(), 6, "Input token should have 6 decimals");
        assertEq(
            inputToken.name(),
            TOKEN_NAME,
            "Input token should have correct name"
        );
        assertEq(
            inputToken.symbol(),
            TOKEN_SYMBOL,
            "Input token should have correct symbol"
        );
        assertEq(
            inputToken.totalSupply(),
            0,
            "Input token should have 0 initial supply"
        );

        // Test output token (TOKEN mock)
        assertEq(
            outputToken.decimals(), 18, "Output token should have 18 decimals"
        );
        assertEq(
            outputToken.name(),
            "Mock Token",
            "Output token should have correct name"
        );
        assertEq(
            outputToken.symbol(),
            "MOCK",
            "Output token should have correct symbol"
        );
        assertEq(
            outputToken.totalSupply(),
            0,
            "Output token should have 0 initial supply"
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════
    // Price Management Tests
    // ═══════════════════════════════════════════════════════════════════════════════════════════════════════

    /* testInitialSetup_GivenNoSetPrices()
        └── Given no prices have been set
            ├── When querying issuance price
            │   └── Then it should revert with InvalidPrice
            └── When querying redemption price
                └── Then it should revert with InvalidPrice
    */
    function testInitialSetup_GivenNoSetPrices() public {
        // Verify initial prices revert
        vm.startPrank(priceSetter_);
        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__LM_ExternalPriceSetter__InvalidPrice()"
            )
        );
        priceSetter.setIssuancePrice(0);

        vm.startPrank(priceSetter_);
        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__LM_ExternalPriceSetter__InvalidPrice()"
            )
        );
        priceSetter.setIssuanceAndRedemptionPrice(0, 0);
    }

    /* testSetIssuancePrice_GivenUnauthorizedUser()
        ├── Given a non-authorized user and random price
        │   └── When setting issuance price
        │       └── Then it should revert with NotPriceSetter
        ├── Given an authorized price setter
        │   ├── When setting a zero price
        │   │   └── Then it should revert with InvalidPrice
        │   └── When setting a valid random price
        │       └── Then the price should be set and normalized correctly
    */
    function testSetIssuancePrice_GivenUnauthorizedUser(
        uint price,
        address unauthorizedUser
    ) public {
        // Assume valid unauthorized user
        vm.assume(unauthorizedUser != address(0));
        vm.assume(unauthorizedUser != address(this));
        vm.assume(unauthorizedUser != priceSetter_);

        price = bound(price, 1, 1_000_000_000_000 * 1e6);

        // Test unauthorized access with random price
        vm.startPrank(unauthorizedUser);
        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__CallerNotAuthorized(bytes32,address)",
                _authorizer.generateRoleId(
                    address(priceSetter), PRICE_SETTER_ROLE
                ),
                unauthorizedUser
            )
        );
        priceSetter.setIssuancePrice(price);
        vm.stopPrank();

        // Test zero price with authorized user
        vm.startPrank(priceSetter_);
        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__LM_ExternalPriceSetter__InvalidPrice()"
            )
        );
        priceSetter.setIssuancePrice(0);

        // Test valid price setting with random price
        priceSetter.setIssuancePrice(price);
        // Price should be normalized from 6 decimals to 18 decimals
        assertEq(
            priceSetter.getPriceForIssuance(),
            price,
            "Issuance price not set correctly"
        );

        vm.stopPrank();
    }

    /* testSetRedemptionPrice_GivenUnauthorizedUser()
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
    function testSetRedemptionPrice_GivenUnauthorizedUser(
        uint price,
        address unauthorizedUser
    ) public {
        // Assume valid unauthorized user
        vm.assume(unauthorizedUser != address(0));
        vm.assume(unauthorizedUser != address(this));
        vm.assume(unauthorizedUser != priceSetter_);

        price = bound(price, 1e6, 1_000_000_000_000 * 1e6);

        // Test unauthorized access
        vm.startPrank(unauthorizedUser);
        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__CallerNotAuthorized(bytes32,address)",
                _authorizer.generateRoleId(
                    address(priceSetter), PRICE_SETTER_ROLE
                ),
                unauthorizedUser
            )
        );
        priceSetter.setRedemptionPrice(price);
        vm.stopPrank();

        // Test zero price with authorized user
        vm.startPrank(priceSetter_);
        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__LM_ExternalPriceSetter__InvalidPrice()"
            )
        );
        priceSetter.setRedemptionPrice(0);

        // Test valid price setting
        priceSetter.setRedemptionPrice(price);
        assertEq(
            priceSetter.getPriceForRedemption(),
            price,
            "Redemption price not set correctly"
        );

        // Test price independence by setting a different issuance price
        uint issuancePrice = price; // Convert to 6 decimals for issuance
        priceSetter.setIssuancePrice(issuancePrice);

        // Verify both prices maintain their values independently
        assertEq(
            priceSetter.getPriceForRedemption(),
            price,
            "Redemption price changed unexpectedly"
        );
        assertEq(
            priceSetter.getPriceForIssuance(),
            issuancePrice,
            "Issuance price not set correctly"
        );

        vm.stopPrank();
    }
}
