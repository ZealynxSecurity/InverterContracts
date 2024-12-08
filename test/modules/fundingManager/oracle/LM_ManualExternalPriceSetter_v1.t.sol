// // SPDX-License-Identifier: UNLICENSED
// pragma solidity 0.8.23;

// import {Test} from "forge-std/Test.sol";
// import {LM_ManualExternalPriceSetter_v1} from
//     "src/modules/fundingManager/oracle/LM_ManualExternalPriceSetter_v1.sol";
// import {LM_ManualExternalPriceSetter_v1_Exposed} from
//     "test/modules/fundingManager/oracle/utils/mocks/LM_ManualExternalPriceSetter_v1_exposed.sol";
// import {ILM_ManualExternalPriceSetter_v1} from
//     "src/modules/fundingManager/oracle/interfaces/ILM_ManualExternalPriceSetter_v1.sol";
// import {IOrchestrator_v1} from
//     "src/orchestrator/interfaces/IOrchestrator_v1.sol";
// import {IModule_v1} from "src/modules/base/IModule_v1.sol";
// import {MockERC20} from
//     "test/modules/fundingManager/oracle/utils/mocks/MockERC20.sol";
// import {AuthorizerV1Mock} from "test/utils/mocks/modules/AuthorizerV1Mock.sol";
// import {OrchestratorV1Mock} from
//     "test/utils/mocks/orchestrator/OrchestratorV1Mock.sol";

// contract LM_ManualExternalPriceSetter_v1_Test is Test {
//     LM_ManualExternalPriceSetter_v1_Exposed priceSetter;
//     AuthorizerV1Mock authorizer;
//     OrchestratorV1Mock orchestrator;

//     address admin;
//     address priceSetter_;
//     address user;

//     MockERC20 inputToken;
//     MockERC20 outputToken;

//     bytes32 constant PRICE_SETTER_ROLE = "PRICE_SETTER_ROLE";
//     uint8 constant INTERNAL_DECIMALS = 18;
//     // Orchestrator_v1 Constants
//     uint internal constant _ORCHESTRATOR_ID = 1;

//     // Module Constants
//     uint constant MAJOR_VERSION = 1;
//     uint constant MINOR_VERSION = 0;
//     uint constant PATCH_VERSION = 0;
//     string constant URL = "https://github.com/organization/module";
//     string constant TITLE = "Module";

//     IModule_v1.Metadata _METADATA = IModule_v1.Metadata(
//         MAJOR_VERSION, MINOR_VERSION, PATCH_VERSION, URL, TITLE
//     );

//     function setUp() public {
//         admin = makeAddr("admin");
//         priceSetter_ = makeAddr("priceSetter");
//         user = makeAddr("user");

//         vm.startPrank(admin);

//         // Create mock tokens with different decimals
//         inputToken = new MockERC20(6); // Like USDC
//         outputToken = new MockERC20(18); // Like most ERC20s

//         // Setup orchestrator and authorizer
//         orchestrator = new OrchestratorV1Mock(address(0));
//         authorizer = new AuthorizerV1Mock();

//         address initialAuth = admin;

//         authorizer.init(
//             IOrchestrator_v1(orchestrator), _METADATA, abi.encode(initialAuth)
//         );

//         // Setup price setter
//         priceSetter = new LM_ManualExternalPriceSetter_v1_Exposed();
//         bytes memory configData =
//             abi.encode(address(inputToken), address(outputToken));

//         priceSetter.init(orchestrator, _METADATA, configData);

//         // Grant price setter role
//         authorizer.grantRole(PRICE_SETTER_ROLE, priceSetter_);

//         vm.stopPrank();
//     }

//     /*  Test: init
//         └── When: initializing with valid parameters
//             └── Then: input and output token decimals should be set correctly
//     */
//     function testInit_GivenValidParams() public {
//         vm.startPrank(admin);

//         LM_ManualExternalPriceSetter_v1_Exposed newPriceSetter =
//             new LM_ManualExternalPriceSetter_v1_Exposed();

//         bytes memory configData =
//             abi.encode(address(inputToken), address(outputToken));
//         IModule_v1.Metadata memory metadata = IModule_v1.Metadata({
//             majorVersion: 1,
//             minorVersion: 0,
//             patchVersion: 0,
//             url: "https://inverter.network",
//             title: "Manual Price Setter"
//         });

//         newPriceSetter.init(orchestrator, metadata, configData);

//         // Check that decimals are set correctly through price normalization test
//         uint testPrice = 1_000_000; // 1 USDC
//         uint normalizedPrice =
//             newPriceSetter.exposed_normalizePrice(testPrice, 6);
//         assertEq(normalizedPrice, 1_000_000_000_000_000_000); // 1e18 (normalized to 18 decimals)

//         vm.stopPrank();
//     }

//     /*  Test: normalizePrice
//         └── When: normalizing prices with different decimal precisions
//             └── Then: should correctly adjust to internal decimal precision
//     */
//     function testNormalizePrice_GivenValidPrice(uint price) public {
//         vm.assume(price < type(uint).max / 10 ** 18); // Prevent overflow

//         uint8 decimals = 6; // USDC-like decimals
//         uint normalizedPrice =
//             priceSetter.exposed_normalizePrice(price, decimals);
//         uint denormalizedPrice =
//             priceSetter.exposed_denormalizePrice(normalizedPrice, decimals);

//         assertEq(
//             price,
//             denormalizedPrice,
//             "Price should remain the same after normalization and denormalization"
//         );
//     }

//     /*  Test: setIssuancePrice
//         └── When: called by authorized price setter
//             └── Then: should update the issuance price
//             └── Then: should emit IssuancePriceSet event
//     */
//     function testSetIssuancePrice_GivenValidPrice(uint price) public {
//         vm.assume(price > 0);
//         vm.assume(price < type(uint).max / 10 ** 18); // Prevent overflow

//         vm.prank(priceSetter_);
//         vm.expectEmit(false, false, false, true);
//         emit ILM_ManualExternalPriceSetter_v1.IssuancePriceSet(price);
//         priceSetter.setIssuancePrice(price);
//     }

//     /*  Test: setRedemptionPrice
//         └── When: called by authorized price setter
//             └── Then: should update the redemption price
//             └── Then: should emit RedemptionPriceSet event
//     */
//     function testSetRedemptionPrice_GivenValidPrice(uint price) public {
//         vm.assume(price > 0);
//         vm.assume(price < type(uint).max / 10 ** 18); // Prevent overflow

//         vm.prank(priceSetter_);
//         vm.expectEmit(false, false, false, true);
//         emit ILM_ManualExternalPriceSetter_v1.RedemptionPriceSet(price);
//         priceSetter.setRedemptionPrice(price);
//     }

//     /*  Test: setPrice
//         └── When: attempting to set a zero price
//             └── Then: should revert with InvalidPrice error
//     */
//     function testSetPrice_revertGivenZeroPrice() public {
//         vm.startPrank(priceSetter_);

//         vm.expectRevert(
//             ILM_ManualExternalPriceSetter_v1
//                 .Module__LM_ExternalPriceSetter__InvalidPrice
//                 .selector
//         );
//         priceSetter.setIssuancePrice(0);

//         vm.expectRevert(
//             ILM_ManualExternalPriceSetter_v1
//                 .Module__LM_ExternalPriceSetter__InvalidPrice
//                 .selector
//         );
//         priceSetter.setRedemptionPrice(0);

//         vm.stopPrank();
//     }

//     /*  Test: setPrice
//         └── When: called by unauthorized address
//             └── Then: should revert with appropriate role error
//     */
//     function testSetPrice_revertGivenUnauthorizedCaller(address unauthorized)
//         public
//     {
//         vm.assume(unauthorized != admin);
//         vm.assume(unauthorized != priceSetter_);

//         vm.startPrank(unauthorized);

//         bytes32 role = PRICE_SETTER_ROLE;
//         bytes memory revertData = abi.encodeWithSignature(
//             "Module__MissingRole(bytes32,address)", role, unauthorized
//         );

//         vm.expectRevert(revertData);
//         priceSetter.setIssuancePrice(1_000_000);

//         vm.expectRevert(revertData);
//         priceSetter.setRedemptionPrice(1_000_000);

//         vm.stopPrank();
//     }
// }
