// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

//--------------------------------------------------------------------------
// Imports

// Internal
import {IOraclePrice_v1} from
    "src/modules/fundingManager/oracle/interfaces/IOraclePrice_v1.sol";
import {ILM_ManualExternalPriceSetter_v1} from
    "src/modules/fundingManager/oracle/interfaces/ILM_ManualExternalPriceSetter_v1.sol";
import {Module_v1} from "src/modules/base/Module_v1.sol";
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title   Manual External Price Oracle Implementation
 *
 * @notice  This contract provides a manual price feed mechanism for token
 *          operations, allowing authorized users to set and update prices for
 *          both issuance (buying) and redemption (selling) operations.
 *
 * @dev     This contract inherits functionalities from:
 *              - Module_v1
 *          The contract maintains two separate price feeds:
 *              1. Issuance price for token minting/buying
 *              2. Redemption price for token burning/selling
 *          Both prices are manually set by the contract owner and must be
 *          non-zero values.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @author  Zealynx Security
 */
contract LM_ManualExternalPriceSetter_v1 is
    ILM_ManualExternalPriceSetter_v1,
    IOraclePrice_v1,
    Module_v1
{
    //--------------------------------------------------------------------------
    // Constants

    bytes32 public constant PRICE_SETTER_ROLE = "PRICE_SETTER_ROLE";
    uint8 private constant INTERNAL_DECIMALS = 18;

    //--------------------------------------------------------------------------
    // State Variables

    /// @notice The price for issuing tokens (normalized to INTERNAL_DECIMALS)
    uint256 private _issuancePrice;

    /// @notice The price for redeeming tokens (normalized to INTERNAL_DECIMALS)
    uint256 private _redemptionPrice;

    /// @notice Decimals of the input token
    uint8 private _inputTokenDecimals;

    /// @notice Decimals of the output token
    uint8 private _outputTokenDecimals;

    /// @dev Storage gap for upgradeable contracts
    uint[50] private __gap;

    //--------------------------------------------------------------------------
    // Initialization

    /// @inheritdoc Module_v1
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata_,
        bytes memory configData_
    ) external override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata_);

        // Decode input and output token addresses from configData_
        (address inputToken, address outputToken) = abi.decode(
            configData_,
            (address, address)
        );

        // Store token decimals for price normalization
        _inputTokenDecimals = IERC20Metadata(inputToken).decimals();
        _outputTokenDecimals = IERC20Metadata(outputToken).decimals();
    }

    //--------------------------------------------------------------------------
    // Interface Support

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override
        returns (bool)
    {
        return interfaceId == type(ILM_ManualExternalPriceSetter_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }

    //--------------------------------------------------------------------------
    // External Functions

    /// @inheritdoc ILM_ManualExternalPriceSetter_v1
    function setIssuancePrice(uint256 price_)
        external
        onlyModuleRole(PRICE_SETTER_ROLE)
    {
        if (price_ == 0) revert Module__LM_ExternalPriceSetter__InvalidPrice();
        
        // Normalize price to internal decimal precision
        _issuancePrice = _normalizePrice(price_, _inputTokenDecimals);
        emit PriceSet(price_);
        emit IssuancePriceSet(price_);
    }

    /// @inheritdoc ILM_ManualExternalPriceSetter_v1
    function setRedemptionPrice(uint price_)
        external
        onlyModuleRole(PRICE_SETTER_ROLE)
    {
        if (price_ == 0) revert Module__LM_ExternalPriceSetter__InvalidPrice();
        
        // Normalize price to internal decimal precision
        _redemptionPrice = _normalizePrice(price_, _outputTokenDecimals);
        emit PriceSet(price_);
        emit RedemptionPriceSet(price_);
    }

    /// @inheritdoc IOraclePrice_v1
    function getPriceForIssuance() external view returns (uint) {
        if (_issuancePrice == 0) revert Module__LM_ExternalPriceSetter__InvalidPrice();
        // Convert from internal precision to output token precision
        return _denormalizePrice(_issuancePrice, _outputTokenDecimals);
    }

    /// @inheritdoc IOraclePrice_v1
    function getPriceForRedemption() external view returns (uint) {
        if (_redemptionPrice == 0) revert Module__LM_ExternalPriceSetter__InvalidPrice();
        // Convert from internal precision to output token precision
        return _denormalizePrice(_redemptionPrice, _outputTokenDecimals);
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @notice Normalizes a price from token decimals to internal decimals
    /// @param price_ The price to normalize
    /// @param tokenDecimals_ The decimals of the token the price is denominated in
    /// @return The normalized price with INTERNAL_DECIMALS precision
    function _normalizePrice(
        uint256 price_,
        uint8 tokenDecimals_
    ) internal pure returns (uint256) {
        if (tokenDecimals_ == INTERNAL_DECIMALS) return price_;
        
        if (tokenDecimals_ > INTERNAL_DECIMALS) {
            return price_ / (10 ** (tokenDecimals_ - INTERNAL_DECIMALS));
        } else {
            return price_ * (10 ** (INTERNAL_DECIMALS - tokenDecimals_));
        }
    }

    /// @notice Denormalizes a price from internal decimals to token decimals
    /// @param price_ The price to denormalize
    /// @param tokenDecimals_ The target token decimals
    /// @return The denormalized price with tokenDecimals_ precision
    function _denormalizePrice(
        uint256 price_,
        uint8 tokenDecimals_
    ) internal pure returns (uint256) {
        if (tokenDecimals_ == INTERNAL_DECIMALS) return price_;
        
        if (tokenDecimals_ > INTERNAL_DECIMALS) {
            return price_ * (10 ** (tokenDecimals_ - INTERNAL_DECIMALS));
        } else {
            return price_ / (10 ** (INTERNAL_DECIMALS - tokenDecimals_));
        }
    }
}
