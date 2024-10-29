// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {ILM_PC_MigrateLiquidity_UniswapV2_v1} from
    "@lm/interfaces/ILM_PC_MigrateLiquidity_UniswapV2_v1.sol";
import {IERC20PaymentClientBase_v1} from
    "@lm/abstracts/ERC20PaymentClientBase_v1.sol";

// Internal Dependencies
import {
    ERC20PaymentClientBase_v1,
    Module_v1
} from "@lm/abstracts/ERC20PaymentClientBase_v1.sol";
import {IFM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";

// External Interfaces
import {IUniswapV2Router02} from "@uniperi/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "@unicore/interfaces/IUniswapV2Factory.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IERC20Issuance_v1} from "src/external/token/IERC20Issuance_v1.sol";

// External Dependencies
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

interface BondingCurve is IBondingCurveBase_v1 {
    /// @notice Transfer a specified amount of Tokens to a designated receiver address.
    /// @dev    This function MUST be restricted to be called only by the {Orchestrator_v1}.
    /// @dev    This function CAN update internal user balances to account for the new token balance.
    /// @param  to The address that will receive the tokens.
    /// @param  amount The amount of tokens to be transfered.
    function transferOrchestratorToken(address to, uint amount) external;
}

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

    //--------------------------------------------------------------------------
    // Modifiers

    modifier notExecuted() {
        if (_currentMigration.executed) {
            revert Module__LM_PC_MigrateLiquidity__AlreadyExecuted();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    /// @dev Address of collateral token
    address private _collateralToken;

    /// @dev Address of the funding manager
    address private _fundingManager;

    /// @dev Address of the issuance token
    address private _issuanceToken;

    // @dev BondingCurve instance
    BondingCurve private _bondingCurve;

    /// @dev State of the current migration
    LiquidityMigrationConfig private _currentMigration;

    //--------------------------------------------------------------------------
    // Initialization

    /// @inheritdoc Module_v1
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) external override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata);

        _fundingManager = address(orchestrator().fundingManager());

        _collateralToken = address(orchestrator().fundingManager().token());

        _bondingCurve = BondingCurve(_fundingManager);

        _issuanceToken = address(_bondingCurve.getIssuanceToken());

        (_currentMigration) = abi.decode(configData, (LiquidityMigrationConfig));
    }

    //--------------------------------------------------------------------------
    // View Functions

    /// @inheritdoc ILM_PC_MigrateLiquidity_UniswapV2_v1
    function getMigrationConfig()
        external
        view
        returns (LiquidityMigrationConfig memory)
    {
        return _currentMigration;
    }

    /// @inheritdoc ILM_PC_MigrateLiquidity_UniswapV2_v1
    function isMigrationReady() public view returns (bool) {
        // Check if migration has been executed
        if (_currentMigration.executed) {
            return false;
        }

        if (
            IERC20(_collateralToken).balanceOf(_fundingManager)
                < _currentMigration.collateralMigrateThreshold
        ) {
            return false;
        }

        return true;
    }

    //--------------------------------------------------------------------------
    // Mutating Functions

    /// @inheritdoc ILM_PC_MigrateLiquidity_UniswapV2_v1
    function configureMigration(LiquidityMigrationConfig calldata migration)
        external
        returns (bool)
    {
        if (migration.collateralMigrateThreshold == 0) {
            revert Module__LM_PC_MigrateLiquidity__InvalidParameters();
        }

        if (
            migration.dexRouterAddress == address(0)
                || migration.dexFactoryAddress == address(0)
        ) {
            revert Module__LM_PC_MigrateLiquidity__InvalidDEXAddresses();
        }

        _currentMigration.collateralMigrateThreshold =
            migration.collateralMigrateThreshold;
        _currentMigration.dexRouterAddress = migration.dexRouterAddress;
        _currentMigration.dexFactoryAddress = migration.dexFactoryAddress;
        _currentMigration.closeBuyOnThreshold = migration.closeBuyOnThreshold;
        _currentMigration.closeSellOnThreshold = migration.closeSellOnThreshold;

        emit MigrationConfigured(
            migration.collateralMigrationAmount,
            migration.collateralMigrateThreshold
        );

        return true;
    }

    /// @inheritdoc ILM_PC_MigrateLiquidity_UniswapV2_v1
    function executeMigration() external notExecuted {
        if (!isMigrationReady()) {
            revert Module__LM_PC_MigrateLiquidity__ThresholdNotReached();
        }

        // Get the UniswapV2 Router and Factory interfaces
        IUniswapV2Router02 router =
            IUniswapV2Router02(_currentMigration.dexRouterAddress);
        IUniswapV2Factory factory =
            IUniswapV2Factory(_currentMigration.dexFactoryAddress);

        // Get token addresses from the payment processor
        address tokenA = address(_collateralToken);
        address tokenB = address(_issuanceToken);

        // Transfer collateral tokens to this contract
        _bondingCurve.transferOrchestratorToken(
            address(this), _currentMigration.collateralMigrationAmount
        );

        // Calculate issuance migration amount
        uint issuanceMigrationAmount = _bondingCurve.calculatePurchaseReturn(
            _currentMigration.collateralMigrationAmount
        );

        // Mint issuance tokens to be used as liquidity
        IERC20Issuance_v1(_issuanceToken).mint(
            address(this), issuanceMigrationAmount
        );

        // Approve router to spend tokens
        IERC20(tokenA).approve(
            _currentMigration.dexRouterAddress,
            _currentMigration.collateralMigrationAmount
        );
        IERC20(tokenB).approve(
            _currentMigration.dexRouterAddress, issuanceMigrationAmount
        );

        // Create the pair if it doesn't exist
        address pair = factory.getPair(tokenA, tokenB);
        if (pair == address(0)) {
            pair = factory.createPair(tokenA, tokenB);
        }

        // Add liquidity
        (uint amountA, uint amountB, uint lpTokensCreated) = router.addLiquidity(
            tokenA,
            tokenB,
            _currentMigration.collateralMigrationAmount,
            issuanceMigrationAmount,
            _currentMigration.collateralMigrationAmount * 95 / 100, // 5% slippage tolerance
            issuanceMigrationAmount * 95 / 100, // 5% slippage tolerance
            address(this),
            block.timestamp + 15 minutes
        );

        _currentMigration.executed = true;

        emit MigrationExecuted(lpTokensCreated);
    }
}
