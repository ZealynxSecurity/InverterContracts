// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

//--------------------------------------------------------------------------
// Imports

// Internal
import { IOraclePrice_v1 } from "./interfaces/IOraclePrice_v1.sol";
import { IManualExternalPriceSetter_v1 } from "./interfaces/IManualExternalPriceSetter_v1.sol";
import { Module_v1 } from "src/modules/base/Module_v1.sol";
import { IOrchestrator_v1 } from "src/orchestrator/interfaces/IOrchestrator_v1.sol";

// External

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

contract ManualExternalPriceSetter_v1 is IManualExternalPriceSetter_v1, Module_v1, IOraclePrice_v1 {
    //--------------------------------------------------------------------------
    // Constants

    bytes32 public constant PRICE_SETTER_ROLE = "PRICE_SETTER_ROLE";

    //--------------------------------------------------------------------------
    // State Variables

    /// @notice The price for issuing tokens
    uint256 private _issuancePrice;

    /// @notice The price for redeeming tokens
    uint256 private _redemptionPrice;

    /// @dev Storage gap for upgradeable contracts
    uint256[50] private __gap;

    //--------------------------------------------------------------------------
    // Initialization

    /// @inheritdoc Module_v1
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata_,
        bytes memory configData_
    ) external override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata_);
    }

    //--------------------------------------------------------------------------
    // Interface Support

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IManualExternalPriceSetter_v1).interfaceId ||
               super.supportsInterface(interfaceId);
    }

    //--------------------------------------------------------------------------
    // Functions

    /// @inheritdoc IManualExternalPriceSetter_v1
    function setIssuancePrice(uint256 price_) external onlyModuleRole(PRICE_SETTER_ROLE) {
        if (price_ == 0) revert ExternalPriceSetter__InvalidPrice();
        _issuancePrice = price_;
        emit PriceSet(price_);
    }

    /// @inheritdoc IManualExternalPriceSetter_v1
    function setRedemptionPrice(uint256 price_) external onlyModuleRole(PRICE_SETTER_ROLE) {
        if (price_ == 0) revert ExternalPriceSetter__InvalidPrice();
        _redemptionPrice = price_;
        emit PriceSet(price_);
    }

    /// @inheritdoc IOraclePrice_v1
    function getPriceForIssuance() external view returns (uint256) {
        return _issuancePrice;
    }

    /// @inheritdoc IOraclePrice_v1
    function getPriceForRedemption() external view returns (uint256) {
        return _redemptionPrice;
    }
}