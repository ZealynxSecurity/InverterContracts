// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {Module_v1} from "src/modules/base/Module_v1.sol";

import {
    E2ETest,
    IOrchestratorFactory_v1,
    IOrchestrator_v1
} from "test/e2e/E2ETest.sol";

// SuT
import {
    FM_BC_Bancor_Redeeming_VirtualSupply_v1,
    IFM_BC_Bancor_Redeeming_VirtualSupply_v1
} from
    "test/modules/fundingManager/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.t.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
import {
    LM_PC_MigrateLiquidity_UniswapV2_v1,
    ILM_PC_MigrateLiquidity_UniswapV2_v1
} from "@lm/LM_PC_MigrateLiquidity_UniswapV2_v1.sol";
import {FM_Rebasing_v1} from "@fm/rebasing/FM_Rebasing_v1.sol";
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";
import {ERC20Issuance_v1} from "src/external/token/ERC20Issuance_v1.sol";

// Uniswap Dependencies
import {IUniswapV2Factory} from "@unicore/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "@unicore/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router02} from "@uniperi/interfaces/IUniswapV2Router02.sol";
import {UniswapV2Factory} from "@unicore/UniswapV2Factory.sol";
import {UniswapV2Router02} from "@uniperi/UniswapV2Router02.sol";
import {WETH9} from "@uniperi/test/WETH9.sol";

contract MigrateLiquidityE2ETest is E2ETest {
    // Module Configurations
    IOrchestratorFactory_v1.ModuleConfig[] moduleConfigurations;

    // Uniswap contracts
    UniswapV2Factory uniswapFactory;
    UniswapV2Router02 uniswapRouter;
    WETH9 weth;

    // Constants
    uint constant COLLATERAL_MIGRATION_THRESHOLD = 1000e18;
    uint constant BUY_AMOUNT = 1000e18;

    ERC20Issuance_v1 issuanceToken;

    // Handle Setup
    function setUp() public override {
        // Setup common E2E framework
        super.setUp();

        // Deploy Uniswap contracts
        weth = new WETH9();
        uniswapFactory = new UniswapV2Factory(address(this));
        uniswapRouter =
            new UniswapV2Router02(address(uniswapFactory), address(weth));

        // Set Up Modules

        // FundingManager
        setUpBancorVirtualSupplyBondingCurveFundingManager();

        // BancorFormula 'formula' is instantiated in the E2EModuleRegistry

        issuanceToken = new ERC20Issuance_v1(
            "Bonding Curve Token", "BCT", 18, type(uint).max - 1, address(this)
        );

        IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties memory
            bc_properties = IFM_BC_Bancor_Redeeming_VirtualSupply_v1
                .BondingCurveProperties({
                formula: address(formula),
                reserveRatioForBuying: 333_333,
                reserveRatioForSelling: 333_333,
                buyFee: 0,
                sellFee: 0,
                buyIsOpen: true,
                sellIsOpen: true,
                initialIssuanceSupply: 10,
                initialCollateralSupply: 30
            });

        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                bancorVirtualSupplyBondingCurveFundingManagerMetadata,
                abi.encode(address(issuanceToken), bc_properties, token)
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
        setUpSimplePaymentProcessor();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                simplePaymentProcessorMetadata, bytes("")
            )
        );

        // Migration Module
        setUpLM_PC_MigrateLiquidity_UniswapV2_v1();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                LM_PC_MigrateLiquidity_UniswapV2_v1Metadata,
                abi.encode(
                    BUY_AMOUNT,
                    COLLATERAL_MIGRATION_THRESHOLD,
                    address(uniswapRouter),
                    address(uniswapFactory),
                    true, // closeBuyOnThreshold
                    false // closeSellOnThreshold
                )
            )
        );
    }

    // Test
    function test_e2e_MigrateLiquidityLifecycle() public {
        //--------------------------------------------------------------------------
        // Orchestrator Initialization
        //--------------------------------------------------------------------------

        // Set WorkflowConfig
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig =
        IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });

        // Set Orchestrator
        IOrchestrator_v1 orchestrator =
            _create_E2E_Orchestrator(workflowConfig, moduleConfigurations);

        // Set FundingManager
        FM_BC_Bancor_Redeeming_VirtualSupply_v1 fundingManager =
        FM_BC_Bancor_Redeeming_VirtualSupply_v1(
            address(orchestrator.fundingManager())
        );

        // Set Minter
        issuanceToken.setMinter(address(fundingManager), true);

        // Mint Collateral To Buy From the FundingManager
        token.mint(address(this), BUY_AMOUNT);
        uint buf_minAmountOut =
            fundingManager.calculatePurchaseReturn(BUY_AMOUNT); // buffer variable to store the minimum amount out on calls to the buy and sell functions

        // Buy from the FundingManager
        vm.startPrank(address(this));
        {
            // Approve tokens to fundingManager.
            token.approve(address(fundingManager), BUY_AMOUNT);

            // Deposit tokens, i.e. fund the fundingmanager.
            fundingManager.buy(BUY_AMOUNT, buf_minAmountOut);

            // After the deposit, received some amount of receipt tokens
            // from the fundingmanager.
            assertTrue(issuanceToken.balanceOf(address(this)) > 0);
        }
        vm.stopPrank();

        // Find and Set Migration Manager
        LM_PC_MigrateLiquidity_UniswapV2_v1 migrationManager;
        address[] memory modulesList = orchestrator.listModules();
        for (uint i; i < modulesList.length; ++i) {
            if (
                ERC165Upgradeable(modulesList[i]).supportsInterface(
                    type(ILM_PC_MigrateLiquidity_UniswapV2_v1).interfaceId
                )
            ) {
                migrationManager =
                    LM_PC_MigrateLiquidity_UniswapV2_v1(modulesList[i]);
                break;
            }
        }

        // Set Migration Manager As Minter
        issuanceToken.setMinter(address(migrationManager), true);

        // Verify Migration Manager configuration
        ILM_PC_MigrateLiquidity_UniswapV2_v1.LiquidityMigrationConfig memory
            migration = migrationManager.getMigrationConfig();

        assertEq(
            migration.collateralMigrateThreshold, COLLATERAL_MIGRATION_THRESHOLD
        );
        assertEq(migration.dexRouterAddress, address(uniswapRouter));
        assertEq(migration.dexFactoryAddress, address(uniswapFactory));
        assertTrue(migration.closeBuyOnThreshold);
        assertFalse(migration.closeSellOnThreshold);
        assertFalse(migration.executed);

        // Check no pool exists yet
        address pairAddress =
            uniswapFactory.getPair(address(token), address(weth));
        assertEq(pairAddress, address(0), "Pool should not exist yet");

        // Execute migration
        vm.startPrank(address(this));
        migrationManager.executeMigration();
        vm.stopPrank();

        // Verify pool creation and liquidity
        pairAddress = uniswapFactory.getPair(address(token), address(weth));
        assertTrue(pairAddress != address(0), "Pool should exist");

        IUniswapV2Pair pair = IUniswapV2Pair(pairAddress);
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();

        // Verify reserves based on token ordering
        if (pair.token0() == address(token)) {
            assertGt(reserve0, 0, "Token reserves should be positive");
            assertGt(reserve1, 0, "WETH reserves should be positive");
        } else {
            assertGt(reserve0, 0, "WETH reserves should be positive");
            assertGt(reserve1, 0, "Token reserves should be positive");
        }

        // Verify migration completion
        migration = migrationManager.getMigrationConfig();
        assertTrue(migration.executed, "Migration should be marked as executed");
    }
}
