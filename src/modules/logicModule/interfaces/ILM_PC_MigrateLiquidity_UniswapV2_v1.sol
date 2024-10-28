// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IERC20PaymentClientBase_v1} from
    "@lm/interfaces/IERC20PaymentClientBase_v1.sol";

interface ILM_PC_MigrateLiquidity_UniswapV2_v1 is IERC20PaymentClientBase_v1 {
    //--------------------------------------------------------------------------
    // Structs

    /// @notice Struct used to store information about a liquidity migration.
    /// @param  initialMintAmount Amount of tokens to mint initially and hold for liquidity.
    /// @param  transitionThreshold The point at which the curve triggers migration.
    /// @param  dexRouterAddress Address of the UniswapV2 router contract.
    /// @param  dexFactoryAddress Address of the UniswapV2 factory contract.
    /// @param  closeBuyOnThreshold Whether to close buying when threshold is reached.
    /// @param  closeSellOnThreshold Whether to close selling when threshold is reached.
    /// @param  executed Whether the migration has been executed.
    struct LiquidityMigration {
        uint initialMintAmount;
        uint transitionThreshold;
        address dexRouterAddress;
        address dexFactoryAddress;
        bool closeBuyOnThreshold;
        bool closeSellOnThreshold;
        bool executed;
    }

    //--------------------------------------------------------------------------
    // Errors

    /// @notice Thrown when migration parameters are invalid
    error Module__LM_PC_MigrateLiquidity__InvalidParameters();

    /// @notice Thrown when migration has already been executed
    error Module__LM_PC_MigrateLiquidity__AlreadyExecuted();

    /// @notice Thrown when threshold has not been reached
    error Module__LM_PC_MigrateLiquidity__ThresholdNotReached();

    /// @notice Thrown when DEX addresses are invalid
    error Module__LM_PC_MigrateLiquidity__InvalidDEXAddresses();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a new migration is configured
    /// @param  migrationId The ID of the migration configuration
    /// @param  initialMintAmount Amount of tokens initially minted
    /// @param  transitionThreshold The threshold point
    event MigrationConfigured(
        uint indexed migrationId,
        uint initialMintAmount,
        uint transitionThreshold
    );

    /// @notice Event emitted when migration is executed
    /// @param  migrationId The ID of the executed migration
    /// @param  lpTokensCreated Amount of LP tokens created
    event MigrationExecuted(uint indexed migrationId, uint lpTokensCreated);

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Configures a new liquidity migration
    /// @param  initialMintAmount Amount of tokens to mint initially
    /// @param  transitionThreshold Point at which to trigger migration
    /// @param  dexRouterAddress UniswapV2 router address
    /// @param  dexFactoryAddress UniswapV2 factory address
    /// @param  closeBuyOnThreshold Whether to close buying at threshold
    /// @param  closeSellOnThreshold Whether to close selling at threshold
    /// @return migrationId The ID of the configured migration
    function configureMigration(
        uint initialMintAmount,
        uint transitionThreshold,
        address dexRouterAddress,
        address dexFactoryAddress,
        bool closeBuyOnThreshold,
        bool closeSellOnThreshold
    ) external returns (uint migrationId);

    /// @notice Executes the configured migration when threshold is reached
    /// @param  migrationId The ID of the migration to execute
    function executeMigration(uint migrationId) external;

    /// @notice Gets the migration configuration
    /// @param  migrationId The ID of the migration
    /// @return The migration configuration
    function getMigrationConfig(uint migrationId)
        external
        view
        returns (LiquidityMigration memory);

    /// @notice Checks if a migration is ready to execute
    /// @param  migrationId The ID of the migration
    /// @return bool Whether the migration can be executed
    function isMigrationReady(uint migrationId) external view returns (bool);
}
