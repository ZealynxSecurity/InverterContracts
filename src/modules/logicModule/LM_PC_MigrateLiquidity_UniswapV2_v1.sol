// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IAuthorizer_v1} from "@aut/IAuthorizer_v1.sol";
import {ILM_PC_MigrateLiquidity_UniswapV2_v1} from
    "@lm/interfaces/ILM_PC_MigrateLiquidity_UniswapV2_v1.sol";
import {
    IERC20PaymentClientBase_v1,
    IPaymentProcessor_v1
} from "@lm/abstracts/ERC20PaymentClientBase_v1.sol";

// Internal Dependencies
import {
    ERC20PaymentClientBase_v1,
    Module_v1
} from "@lm/abstracts/ERC20PaymentClientBase_v1.sol";

// External Dependencies
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

// Internal Libraries
import {LinkedIdList} from "src/modules/lib/LinkedIdList.sol";

contract LM_PC_MigrateLiquidity_UniswapV2_v1 is
    ILM_PC_MigrateLiquidity_UniswapV2_v1,
    ERC20PaymentClientBase_v1
{
    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC20PaymentClientBase_v1)
        returns (bool)
    {
        return interfaceId
            == type(ILM_PC_MigrateLiquidity_UniswapV2_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }

    using LinkedIdList for LinkedIdList.List;

    //--------------------------------------------------------------------------
    // Modifiers

    modifier validMigrationId(uint migrationId) {
        if (!isExistingMigrationId(migrationId)) {
            revert Module__LM_PC_MigrateLiquidity__InvalidParameters();
        }
        _;
    }

    modifier notExecuted(uint migrationId) {
        if (_migrationRegistry[migrationId].executed) {
            revert Module__LM_PC_MigrateLiquidity__AlreadyExecuted();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Constants

    /// @dev Role for configuring migrations
    bytes32 public constant MIGRATION_CONFIGURATOR_ROLE =
        "MIGRATION_CONFIGURATOR";
    /// @dev Role for executing migrations
    bytes32 public constant MIGRATION_EXECUTOR_ROLE = "MIGRATION_EXECUTOR";

    //--------------------------------------------------------------------------
    // Storage

    /// @dev Value for what the next id will be
    uint private _nextId;

    /// @dev Registry mapping ids to LiquidityMigration structs
    mapping(uint => LiquidityMigration) private _migrationRegistry;

    /// @dev List of Migration IDs
    LinkedIdList.List private _migrationList;

    /// @dev Storage gap for future upgrades
    uint[50] private __gap;

    //--------------------------------------------------------------------------
    // Initialization

    /// @inheritdoc Module_v1
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory
    ) external override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata);
        _migrationList.init();
    }

    //--------------------------------------------------------------------------
    // View Functions

    /// @inheritdoc ILM_PC_MigrateLiquidity_UniswapV2_v1
    function getMigrationConfig(uint migrationId)
        external
        view
        validMigrationId(migrationId)
        returns (LiquidityMigration memory)
    {
        return _migrationRegistry[migrationId];
    }

    /// @inheritdoc ILM_PC_MigrateLiquidity_UniswapV2_v1
    function isMigrationReady(uint migrationId)
        external
        view
        validMigrationId(migrationId)
        returns (bool)
    {
        LiquidityMigration memory migration = _migrationRegistry[migrationId];
        // Check if threshold has been reached
        // Implementation specific to curve threshold check
        return !migration.executed; // Add threshold check logic
    }

    function isExistingMigrationId(uint migrationId)
        public
        view
        returns (bool)
    {
        return _migrationList.isExistingId(migrationId);
    }

    //--------------------------------------------------------------------------
    // Mutating Functions

    /// @inheritdoc ILM_PC_MigrateLiquidity_UniswapV2_v1
    function configureMigration(
        uint initialMintAmount,
        uint transitionThreshold,
        address dexRouterAddress,
        address dexFactoryAddress,
        bool closeBuyOnThreshold,
        bool closeSellOnThreshold
    ) external onlyModuleRole(MIGRATION_CONFIGURATOR_ROLE) returns (uint) {
        if (initialMintAmount == 0 || transitionThreshold == 0) {
            revert Module__LM_PC_MigrateLiquidity__InvalidParameters();
        }

        if (dexRouterAddress == address(0) || dexFactoryAddress == address(0)) {
            revert Module__LM_PC_MigrateLiquidity__InvalidDEXAddresses();
        }

        uint migrationId = ++_nextId;
        _migrationList.addId(migrationId);

        LiquidityMigration storage migration = _migrationRegistry[migrationId];
        migration.initialMintAmount = initialMintAmount;
        migration.transitionThreshold = transitionThreshold;
        migration.dexRouterAddress = dexRouterAddress;
        migration.dexFactoryAddress = dexFactoryAddress;
        migration.closeBuyOnThreshold = closeBuyOnThreshold;
        migration.closeSellOnThreshold = closeSellOnThreshold;
        migration.executed = false;

        emit MigrationConfigured(
            migrationId, initialMintAmount, transitionThreshold
        );

        return migrationId;
    }

    /// @inheritdoc ILM_PC_MigrateLiquidity_UniswapV2_v1
    function executeMigration(uint migrationId)
        external
        onlyModuleRole(MIGRATION_EXECUTOR_ROLE)
        validMigrationId(migrationId)
        notExecuted(migrationId)
    {
        LiquidityMigration storage migration = _migrationRegistry[migrationId];

        if (!this.isMigrationReady(migrationId)) {
            revert Module__LM_PC_MigrateLiquidity__ThresholdNotReached();
        }

        // Implementation specific logic for:
        // 1. Creating liquidity pool
        // 2. Depositing tokens
        // 3. Optional curve closure

        uint lpTokensCreated = 0; // Add actual LP token calculation

        migration.executed = true;

        emit MigrationExecuted(migrationId, lpTokensCreated);
    }
}
