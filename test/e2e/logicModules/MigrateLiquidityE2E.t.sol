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
    LM_PC_MigrateLiquidity_UniswapV2_v1,
    ILM_PC_MigrateLiquidity_UniswapV2_v1
} from "@lm/LM_PC_MigrateLiquidity_UniswapV2_v1.sol";
import {FM_Rebasing_v1} from "@fm/rebasing/FM_Rebasing_v1.sol";
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

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

    // Roles
    address migrationConfigurator = makeAddr("migrationConfigurator");
    address migrationExecutor = makeAddr("migrationExecutor");

    // Constants
    uint constant INITIAL_MINT_AMOUNT = 1000e18;
    uint constant TRANSITION_THRESHOLD = 500e18;
    uint constant INITIAL_LIQUIDITY = 100e18;

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
        setUpRebasingFundingManager();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                rebasingFundingManagerMetadata, abi.encode(address(token))
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
        setUpMigrationManager();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                migrationManagerMetadata, bytes("")
            )
        );
    }

    function test_e2e_MigrateLiquidityLifecycle() public {
        //--------------------------------------------------------------------------
        // Orchestrator Initialization
        //--------------------------------------------------------------------------
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig =
        IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });

        IOrchestrator_v1 orchestrator =
            _create_E2E_Orchestrator(workflowConfig, moduleConfigurations);

        FM_Rebasing_v1 fundingManager =
            FM_Rebasing_v1(address(orchestrator.fundingManager()));

        // Find Migration Manager
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

        // Grant roles
        migrationManager.grantModuleRole(
            migrationManager.MIGRATION_CONFIGURATOR_ROLE(),
            migrationConfigurator
        );
        migrationManager.grantModuleRole(
            migrationManager.MIGRATION_EXECUTOR_ROLE(), migrationExecutor
        );

        // Initial funding
        uint initialDeposit = INITIAL_LIQUIDITY * 2;
        token.mint(address(this), initialDeposit);
        token.approve(address(fundingManager), initialDeposit);
        fundingManager.deposit(initialDeposit);

        // Configure migration
        vm.startPrank(migrationConfigurator);
        uint migrationId = migrationManager.configureMigration(
            INITIAL_MINT_AMOUNT,
            TRANSITION_THRESHOLD,
            address(uniswapRouter),
            address(uniswapFactory),
            true, // closeBuyOnThreshold
            false // closeSellOnThreshold
        );
        vm.stopPrank();

        // Verify configuration
        ILM_PC_MigrateLiquidity_UniswapV2_v1.LiquidityMigration memory migration =
            migrationManager.getMigrationConfig(migrationId);

        assertEq(migration.initialMintAmount, INITIAL_MINT_AMOUNT);
        assertEq(migration.transitionThreshold, TRANSITION_THRESHOLD);
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
        vm.startPrank(migrationExecutor);
        migrationManager.executeMigration(migrationId);
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
        migration = migrationManager.getMigrationConfig(migrationId);
        assertTrue(migration.executed, "Migration should be marked as executed");
    }

    function setUpMigrationManager() internal {
        migrationManagerMetadata = Module_v1.Metadata({
            name: "Migration Manager",
            version: 1,
            author: "Inverter Network",
            description: "Manages liquidity migration to Uniswap V2",
            license: "LGPL-3.0-only"
        });
    }
}
