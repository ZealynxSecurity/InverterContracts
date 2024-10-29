// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IERC20PaymentClientBase_v1} from
    "@lm/interfaces/IERC20PaymentClientBase_v1.sol";

interface ILM_PC_MigrateLiquidity_UniswapV2_v1 is IERC20PaymentClientBase_v1 {
    //--------------------------------------------------------------------------
    // Structs

    /// @notice Struct used to store information about a liquidity migration.
    /// @param  collateralMigrationAmount Amount of collateral tokens to migrate.
    /// @param  collateralMigrateThreshold The point at which the curve triggers migration.
    /// @param  dexRouterAddress Address of the UniswapV2 router contract.
    /// @param  closeBuyOnThreshold Whether to close buying when threshold is reached.
    /// @param  closeSellOnThreshold Whether to close selling when threshold is reached.
    struct LiquidityMigrationConfig {
        uint collateralMigrationAmount;
        uint collateralMigrateThreshold;
        address dexRouterAddress;
    }

    /// @notice Struct used to inform about the result of a liquidity migration.
    /// @param  pairAddress Address of the created pair
    /// @param  lpTokensCreated Amount of LP tokens created
    /// @param  token0 Address of the first token
    /// @param  token1 Address of the second token
    /// @param  amount0 Amount of the first token
    /// @param  amount1 Amount of the second token
    struct LiquidityMigrationResult {
        address pairAddress;
        uint lpTokensCreated;
        address token0;
        address token1;
        uint amount0;
        uint amount1;
    }

    //--------------------------------------------------------------------------
    // Errors

    /// @notice Thrown when migration parameters are invalid
    error Module__LM_PC_MigrateLiquidity__InvalidParameters();

    /// @notice Thrown when migration has already been executed
    error Module__LM_PC_MigrateLiquidity__AlreadyExecuted();

    /// @notice Thrown when threshold has not been reached
    error Module__LM_PC_MigrateLiquidity__ThresholdNotReached();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a new migration is configured
    /// @param  collateralMigrationAmount Amount of tokens which will be migrated
    /// @param  collateralMigrateThreshold The threshold point to trigger migration
    event MigrationConfigured(
        uint collateralMigrationAmount, uint collateralMigrateThreshold
    );

    /// @notice Event emitted when migration is executed
    /// @param  result The result of the migration
    event MigrationExecuted(LiquidityMigrationResult result);

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Gets the executed flag
    /// @return bool Whether the migration has been executed
    function getExecuted() external view returns (bool);

    /// @notice Executes the configured migration when threshold is reached
    function executeMigration()
        external
        returns (LiquidityMigrationResult memory);

    /// @notice Gets the migration configuration
    /// @return The migration configuration
    function getMigrationConfig()
        external
        view
        returns (LiquidityMigrationConfig memory);

    /// @notice Checks if a migration is ready to execute
    /// @return bool Whether the migration can be executed
    function isMigrationReady() external view returns (bool);
}
