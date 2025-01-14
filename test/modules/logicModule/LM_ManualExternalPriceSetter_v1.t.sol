// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import {Test, console} from "forge-std/Test.sol"; // @todo remove
import {LM_ManualExternalPriceSetter_v1} from
    "src/modules/logicModule/LM_ManualExternalPriceSetter_v1.sol";
import {LM_ManualExternalPriceSetter_v1_Exposed} from
    "test/modules/logicModule/LM_ManualExternalPriceSetter_v1_exposed.sol";
import {ILM_ManualExternalPriceSetter_v1} from
    "@lm/interfaces/ILM_ManualExternalPriceSetter_v1.sol";
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

    LM_ManualExternalPriceSetter_v1_Exposed priceSetter;

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
        address impl = address(new LM_ManualExternalPriceSetter_v1_Exposed());
        priceSetter =
            LM_ManualExternalPriceSetter_v1_Exposed(Clones.clone(impl));

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
            price * 1e12,
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

    // // ═══════════════════════════════════════════════════════════════════════════════════════════════════════
    // // Price Normalization Tests
    // // ═══════════════════════════════════════════════════════════════════════════════════════════════════════

    // /* testPriceNormalization_GivenDifferentDecimals()
    //     Tests the price normalization function with different decimal configurations
        
    //     Tree structure:
    //     ├── Given a random price and decimals (1-24)
    //     │   ├── When decimals < 18
    //     │   │   ├── Then should scale up price correctly
    //     │   │   └── Then scaling should be reversible
    //     │   ├── When decimals > 18
    //     │   │   ├── Then should scale down price correctly
    //     │   │   └── Then rounding error should be within bounds
    //     │   └── When decimals = 18
    //     │       └── Then price should remain unchanged
    //     └── Given minimum price (1)
    //         ├── When decimals < 18: should scale up to 10^(18-decimals)
    //         ├── When decimals > 18: should round to 0
    //         └── When decimals = 18: should remain 1
    // */
    // function testPriceNormalization_GivenDifferentDecimals(
    //     uint price,
    //     uint8 decimals
    // ) public {
    //     vm.assume(price < type(uint).max / 1e18);
    //     decimals = uint8(bound(decimals, 1, 24));

    //     uint normalizedPrice =
    //         priceSetter.exposed_normalizePrice(price, decimals);
    //     uint scaleFactor =
    //         decimals < 18 ? 10 ** (18 - decimals) : 10 ** (decimals - 18);

    //     if (decimals < 18) {
    //         // Scaling up (e.g., USDC-6, WBTC-8)
    //         assertEq(normalizedPrice, price * scaleFactor, "Scaling up failed");
    //         assertEq(normalizedPrice / scaleFactor, price, "Not reversible");
    //     } else if (decimals > 18) {
    //         // Scaling down (tokens with more than 18 decimals)
    //         assertEq(
    //             normalizedPrice, price / scaleFactor, "Scaling down failed"
    //         );
    //         assertTrue(
    //             price - (normalizedPrice * scaleFactor) < scaleFactor,
    //             "High rounding error"
    //         );
    //     } else {
    //         // No scaling (18 decimals like ETH)
    //         assertEq(normalizedPrice, price, "Price changed unnecessarily");
    //     }

    //     // Edge case: minimum price (1)
    //     if (price == 1) {
    //         uint minPrice = priceSetter.exposed_normalizePrice(1, decimals);
    //         assertEq(
    //             minPrice,
    //             decimals < 18 ? scaleFactor : decimals > 18 ? 0 : 1,
    //             "Minimum price handling failed"
    //         );
    //     }
    // }

    // /* testPriceDenormalization_GivenDifferentDecimals()
    //     Tests price denormalization from internal (18) decimals to token decimals
        
    //     Tree structure:
    //     ├── Given a normalized price (18 decimals)
    //     │   ├── When converting to lower decimals
    //     │   │   ├── Then should scale down correctly
    //     │   │   └── Then rounding error should be within bounds
    //     │   ├── When converting to same decimals
    //     │   │   └── Then price should remain unchanged
    //     │   └── When converting to higher decimals
    //     │       └── Then should scale up correctly
    //     └── Given minimum price (1)
    //         ├── When decimals < 18: should scale down to 0 or 1
    //         ├── When decimals = 18: should remain 1
    //         └── When decimals > 18: should scale up to 10^(decimals-18)
    // */
    // function testPriceDenormalization_GivenDifferentDecimals(
    //     uint price,
    //     uint8 decimals
    // ) public {
    //     vm.assume(price < type(uint).max / 1e18);
    //     decimals = uint8(bound(decimals, 1, 24));

    //     uint denormalizedPrice =
    //         priceSetter.exposed_denormalizePrice(price, decimals);
    //     uint scaleFactor =
    //         decimals < 18 ? 10 ** (18 - decimals) : 10 ** (decimals - 18);

    //     if (decimals < 18) {
    //         // Scaling down (e.g., to USDC-6, WBTC-8)
    //         assertEq(
    //             denormalizedPrice, price / scaleFactor, "Scaling down failed"
    //         );
    //         assertTrue(
    //             price - (denormalizedPrice * scaleFactor) < scaleFactor,
    //             "High rounding error"
    //         );
    //     } else if (decimals > 18) {
    //         // Scaling up (to more than 18 decimals)
    //         assertEq(
    //             denormalizedPrice, price * scaleFactor, "Scaling up failed"
    //         );
    //         assertEq(denormalizedPrice / scaleFactor, price, "Not reversible");
    //     } else {
    //         // No scaling (18 decimals like ETH)
    //         assertEq(denormalizedPrice, price, "Price changed unnecessarily");
    //     }

    //     // Edge case: minimum price (1)
    //     if (price == 1) {
    //         uint minPrice = priceSetter.exposed_denormalizePrice(1, decimals);
    //         assertEq(
    //             minPrice,
    //             decimals < 18 ? 0 : decimals > 18 ? scaleFactor : 1,
    //             "Minimum price handling failed"
    //         );
    //     }
    // }

    // /* testPriceNormalizationCycle_GivenDifferentDecimals()
    //     Tests that normalizing and then denormalizing a price maintains the original value
    //     when possible, accounting for precision loss in certain cases.
        
    //     Tree structure:
    //     ├── Given a random price and decimals
    //     │   ├── When normalizing then denormalizing
    //     │   │   ├── Then should match original for decimals <= 18
    //     │   │   └── Then should be within error bounds for decimals > 18
    //     │   └── When denormalizing then normalizing
    //     │       ├── Then should match original if result > minimum viable price
    //     │       └── Then should be 0 if below minimum viable price
    //     └── Given minimum viable price for decimals
    //         └── When running full cycle
    //             └── Then should preserve value if possible
    // */
    // function testPriceNormalizationCycle_GivenDifferentDecimals(
    //     uint price,
    //     uint8 decimals
    // ) public {
    //     vm.assume(price < type(uint).max / 1e18);

    //     decimals = uint8(bound(decimals, 1, 18));

    //     // First cycle: normalization → denormalization
    //     uint normalized = priceSetter.exposed_normalizePrice(price, decimals);
    //     uint denormalized =
    //         priceSetter.exposed_denormalizePrice(normalized, decimals);

    //     // Price should be exactly equal after the first cycle
    //     assertEq(denormalized, price, "Price changed after normalization cycle");

    //     // For the second cycle, use the normalized price as base
    //     // since this is the format in which it's stored internally
    //     uint normalized2 =
    //         priceSetter.exposed_normalizePrice(denormalized, decimals);
    //     uint denormalized2 =
    //         priceSetter.exposed_denormalizePrice(normalized2, decimals);

    //     // Verify that the final denormalized price equals the original
    //     assertEq(
    //         denormalized2,
    //         price,
    //         "Price changed after second normalization cycle"
    //     );

    //     // Test with minimum viable price (1)
    //     uint minPrice = 1;
    //     normalized = priceSetter.exposed_normalizePrice(minPrice, decimals);
    //     denormalized =
    //         priceSetter.exposed_denormalizePrice(normalized, decimals);

    //     // Minimum viable price should be preserved exactly
    //     assertEq(denormalized, minPrice, "Minimum viable price not preserved");
    // }
}
