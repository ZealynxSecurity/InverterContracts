// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal
import {ILM_ManualExternalPriceSetter_v1} from
    "@lm/interfaces/ILM_ManualExternalPriceSetter_v1.sol";
import {Module_v1} from "src/modules/base/Module_v1.sol";
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IOraclePrice_v1} from "@lm/interfaces/IOraclePrice_v1.sol";

// External
import {IERC20Metadata} from "@oz/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

/**
 * @title   Manual External Price Oracle Implementation
 *
 * @notice  This contract provides a manual price feed mechanism for token
 *          operations, allowing authorized users to set and update prices
 *          for both issuance (buying) and redemption (selling) operations.
 *
 * @dev     This contract inherits functionalities from:
 *              - Module_v1
 *          The contract maintains two separate price feeds:
 *              1. Issuance price for token minting/buying.
 *              2. Redemption price for token burning/selling.
 *          Both prices are manually set by the contract owner and must be
 *          non-zero values.
 *
 *          Price Context:
 *              - Prices are stored internally with 18 decimals for consistent
 *                math.
 *              - When setting prices: Input values should be in collateral
 *                token decimals.
 *              - When getting prices: Output values will be in issuance
 *                token decimals.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer
 *                          to our Security Policy at security.inverter.network
 *                          or email us directly!
 *
 * @custom:version  v1.0.0
 *
 * @custom:standard-version v1.0.0
 *
 * @author  Zealynx Security
 */
contract LM_ManualExternalPriceSetter_v1 is
    ILM_ManualExternalPriceSetter_v1,
    Module_v1
{
    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override
        returns (bool)
    {
        return interfaceId == type(ILM_ManualExternalPriceSetter_v1).interfaceId
            || interfaceId == type(IOraclePrice_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }

    // -------------------------------------------------------------------------
    // Constants

    /// @notice Role identifier for accounts authorized to set prices.
    /// @dev    This role should be granted to trusted price feeders only.
    bytes32 public constant PRICE_SETTER_ROLE = "PRICE_SETTER_ROLE";

    /// @notice Number of decimal places used for internal price
    ///         representation
    /// @dev    All prices are normalized to this precision for consistent
    ///         calculations regardless of input/output token decimals.
    uint8 private constant INTERNAL_DECIMALS = 18;

    // -------------------------------------------------------------------------
    // State Variables

    /// @notice The price for issuing tokens (normalized to
    ///         INTERNAL_DECIMALS).
    uint private _issuancePrice;

    /// @notice The price for redeeming tokens (normalized to
    ///         INTERNAL_DECIMALS).
    uint private _redemptionPrice;

    /// @notice Decimals of the collateral token (e.g., USDC with 6 decimals).
    /// @dev    This is the token used to pay/buy with.
    uint8 private _collateralTokenDecimals;

    /// @notice Decimals of the issuance token (e.g., ISS with 18 decimals).
    /// @dev    This is the token being bought/sold.
    uint8 private _issuanceTokenDecimals;

    // -------------------------------------------------------------------------
    // Initialization

    /// @inheritdoc Module_v1
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata_,
        bytes memory configData_
    ) external override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata_);

        // Decode collateral and issuance token addresses from configData_.
        (address collateralToken, address issuanceToken) =
            abi.decode(configData_, (address, address));

        // Store token decimals for price normalization.
        _collateralTokenDecimals = IERC20Metadata(collateralToken).decimals();
        _issuanceTokenDecimals = IERC20Metadata(issuanceToken).decimals();
    }

    // -------------------------------------------------------------------------
    // External Functions

    /// @inheritdoc ILM_ManualExternalPriceSetter_v1
    function setIssuancePrice(uint price_)
        external
        onlyModuleRole(PRICE_SETTER_ROLE)
    {
        if (price_ == 0) revert Module__LM_ExternalPriceSetter__InvalidPrice();

        // Normalize price to internal decimal precision
        _issuancePrice = _normalizePrice(price_, _collateralTokenDecimals);
        emit IssuancePriceSet(price_);
    }

    /// @inheritdoc ILM_ManualExternalPriceSetter_v1
    function setRedemptionPrice(uint price_)
        external
        onlyModuleRole(PRICE_SETTER_ROLE)
    {
        if (price_ == 0) revert Module__LM_ExternalPriceSetter__InvalidPrice();

        // Normalize price to internal decimal precision.
        _redemptionPrice = _normalizePrice(price_, _issuanceTokenDecimals);
        emit RedemptionPriceSet(price_);
    }

    /// @inheritdoc ILM_ManualExternalPriceSetter_v1
    function setIssuanceAndRedemptionPrice(
        uint issuancePrice_,
        uint redemptionPrice_
    ) external onlyModuleRole(PRICE_SETTER_ROLE) {
        if (issuancePrice_ == 0 || redemptionPrice_ == 0) {
            revert Module__LM_ExternalPriceSetter__InvalidPrice();
        }

        // Normalize and set both prices atomically
        _issuancePrice =
            _normalizePrice(issuancePrice_, _collateralTokenDecimals);
        _redemptionPrice =
            _normalizePrice(redemptionPrice_, _issuanceTokenDecimals);

        // Emit events
        emit IssuancePriceSet(issuancePrice_);
        emit RedemptionPriceSet(redemptionPrice_);
    }

    /// @notice Gets current price for token issuance (buying tokens).
    /// @return price_ Current price in 18 decimals (collateral tokens per 1
    ///         issuance token).
    /// @dev    Example: If price is 2 USDC/ISS, returns 2e18 (2 USDC needed for
    ///         1 ISS).
    function getPriceForIssuance() external view returns (uint) {
        // Convert from internal precision to output token precision.
        return _denormalizePrice(_issuancePrice, _issuanceTokenDecimals);
    }

    /// @notice Gets current price for token redemption (selling tokens).
    /// @return price_ Current price in 18 decimals (collateral tokens per 1
    ///         issuance token).
    /// @dev    Example: If price is 1.9 USDC/ISS, returns 1.9e18 (1.9 USDC
    ///         received for 1 ISS).
    function getPriceForRedemption() external view returns (uint) {
        // Convert from internal precision to output token precision.
        return _denormalizePrice(_redemptionPrice, _issuanceTokenDecimals);
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @notice Normalizes a price from token decimals to internal decimals.
    /// @param  price_ The price to normalize.
    /// @param  tokenDecimals_ The decimals of the token the price is
    ///         denominated in.
    /// @return The normalized price with INTERNAL_DECIMALS precision.
    function _normalizePrice(uint price_, uint8 tokenDecimals_)
        internal
        pure
        returns (uint)
    {
        if (tokenDecimals_ == INTERNAL_DECIMALS) return price_;

        if (tokenDecimals_ > INTERNAL_DECIMALS) {
            return price_ / (10 ** (tokenDecimals_ - INTERNAL_DECIMALS));
        } else {
            return price_ * (10 ** (INTERNAL_DECIMALS - tokenDecimals_));
        }
    }

    /// @notice Denormalizes a price from internal decimals to token decimals.
    /// @param  price_ The price to denormalize.
    /// @param  tokenDecimals_ The target token decimals.
    /// @return The denormalized price with tokenDecimals_ precision.
    function _denormalizePrice(uint price_, uint8 tokenDecimals_)
        internal
        pure
        returns (uint)
    {
        if (tokenDecimals_ == INTERNAL_DECIMALS) return price_;

        if (tokenDecimals_ > INTERNAL_DECIMALS) {
            return price_ * (10 ** (tokenDecimals_ - INTERNAL_DECIMALS));
        } else {
            return price_ / (10 ** (INTERNAL_DECIMALS - tokenDecimals_));
        }
    }

    /// @dev    Storage gap for upgradeable contracts.
    uint[50] private __gap;
}
