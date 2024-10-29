// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// Internal Dependencies
import {Module_v1} from "src/modules/base/Module_v1.sol";
import {
    E2ETest,
    IOrchestratorFactory_v1,
    IOrchestrator_v1
} from "test/e2e/E2ETest.sol";
// Uniswap Dependencies
import {IUniswapV2Factory} from "@ex/interfaces/uniswap/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "@ex/interfaces/uniswap/IUniswapV2Pair.sol";
import {IUniswapV2Router02} from "@ex/interfaces/uniswap/IUniswapV2Router02.sol";
// SuT
import {
    FM_BC_Bancor_Redeeming_VirtualSupply_v1,
    IFM_BC_Bancor_Redeeming_VirtualSupply_v1
} from "@fm/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {
    LM_PC_MigrateLiquidity_UniswapV2_v1,
    ILM_PC_MigrateLiquidity_UniswapV2_v1
} from "@lm/LM_PC_MigrateLiquidity_UniswapV2_v1.sol";
import {FM_Rebasing_v1} from "@fm/rebasing/FM_Rebasing_v1.sol";
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";
import {ERC20Issuance_v1} from "src/external/token/ERC20Issuance_v1.sol";

contract MigrateLiquidityE2ETest is E2ETest {
    // Module Configurations
    IOrchestratorFactory_v1.ModuleConfig[] moduleConfigurations;

    // Constants
    uint constant COLLATERAL_MIGRATION_THRESHOLD = 1000e18;
    uint constant COLLATERAL_MIGRATION_AMOUNT = 1000e18;
    uint constant BUY_FROM_FUNDING_MANAGER_AMOUNT = 1000e18;
    ERC20Issuance_v1 issuanceToken;
    // Uniswap
    address uniswapFactoryAddress = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address uniswapRouterAddress = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    IUniswapV2Factory uniswapFactory;
    IUniswapV2Router02 uniswapRouter;

    function setUp() public override {
        //--------------------------------------------------------------------------
        // Setup
        //--------------------------------------------------------------------------
        super.setUp();

        // Step 0: Make global addresses persistent
        vm.makePersistent(address(token));
        vm.makePersistent(address(formula));

        // Step 1: Create both forks first
        uint anvilFork = vm.createFork("http://localhost:8545");
        uint mainnetFork = vm.createFork("https://rpc.ankr.com/eth", 17_480_237);

        // Step 2: Select mainnet fork and set up Uniswap contracts
        vm.selectFork(mainnetFork);
        uniswapFactory = IUniswapV2Factory(uniswapFactoryAddress);
        uniswapRouter = IUniswapV2Router02(uniswapRouterAddress);

        // Step 3: Create the contract state on mainnet fork
        bytes memory factoryCode = address(uniswapFactory).code;
        bytes memory routerCode = address(uniswapRouter).code;

        // Step 4: Switch to Anvil fork and etch the contracts
        vm.selectFork(anvilFork);
        vm.etch(uniswapFactoryAddress, factoryCode);
        vm.etch(uniswapRouterAddress, routerCode);

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
                    ILM_PC_MigrateLiquidity_UniswapV2_v1
                        .LiquidityMigrationConfig({
                        collateralMigrationAmount: COLLATERAL_MIGRATION_AMOUNT,
                        collateralMigrateThreshold: COLLATERAL_MIGRATION_THRESHOLD,
                        dexRouterAddress: address(uniswapRouter),
                        closeBuyOnThreshold: true,
                        closeSellOnThreshold: false
                    })
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

        // Test Lifecycle
        //--------------------------------------------------------------------------

        // 1. Set FundingManager as Minter
        issuanceToken.setMinter(address(fundingManager), true);

        // 1.1. Set Migration Manager As Minter
        issuanceToken.setMinter(address(migrationManager), true);

        // 2. Mint Collateral To Buy From the FundingManager
        token.mint(address(this), BUY_FROM_FUNDING_MANAGER_AMOUNT);

        // 3. Calculate Minimum Amount Out
        uint buf_minAmountOut = fundingManager.calculatePurchaseReturn(
            BUY_FROM_FUNDING_MANAGER_AMOUNT
        ); // buffer variable to store the minimum amount out on calls to the buy and sell functions

        // 4. Buy from the FundingManager
        vm.startPrank(address(this));
        {
            // 4.1. Approve tokens to fundingManager.
            token.approve(
                address(fundingManager), BUY_FROM_FUNDING_MANAGER_AMOUNT
            );
            // 4.2. Deposit tokens, i.e. fund the fundingmanager.
            fundingManager.buy(
                BUY_FROM_FUNDING_MANAGER_AMOUNT, buf_minAmountOut
            );
            // 4.3. After the deposit, check that the user has received them
            assertTrue(
                issuanceToken.balanceOf(address(this)) > 0,
                "User should have received issuance tokens after deposit"
            );
        }
        vm.stopPrank();

        // 5. Check no pool exists yet
        address pairAddress =
            uniswapFactory.getPair(address(token), address(issuanceToken));

        assertEq(pairAddress, address(0), "Pool should not exist yet");

        // 6. Set migration manager instance
        ILM_PC_MigrateLiquidity_UniswapV2_v1.LiquidityMigrationConfig memory
            migration = migrationManager.getMigrationConfig();

        // 7. Execute migration
        vm.startPrank(address(this));
        migrationManager.executeMigration();
        vm.stopPrank();

        bool executed = migrationManager.getExecuted();

        // 8. Verify pool creation and liquidity
        pairAddress =
            uniswapFactory.getPair(address(token), address(issuanceToken));
        assertTrue(pairAddress != address(0), "Pool should exist");

        // 9.1. Get pair
        IUniswapV2Pair pair = IUniswapV2Pair(pairAddress);

        // 9.2. Get reserves
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();

        // 9.3. Verify reserves based on token ordering
        if (pair.token0() == address(token)) {
            assertGt(reserve0, 0, "Token reserves should be positive");
            assertGt(reserve1, 0, "IssuanceToken reserves should be positive");
        } else {
            assertGt(reserve0, 0, "IssuanceToken reserves should be positive");
            assertGt(reserve1, 0, "Token reserves should be positive");
        }

        // 10. Verify migration completion
        migration = migrationManager.getMigrationConfig();
        assertTrue(executed, "Migration should be marked as executed");
    }
}
