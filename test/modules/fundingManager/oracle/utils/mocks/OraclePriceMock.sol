// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import "@lm/interfaces/IOraclePrice_v1.sol";
import "@oz/utils/introspection/ERC165.sol";

contract OraclePriceMock is IOraclePrice_v1, ERC165 {
    uint256 private _priceForIssuance;
    uint256 private _priceForRedemption;

    constructor() {
        _priceForIssuance = 1e18;  // Default price 1:1
        _priceForRedemption = 1e18; // Default price 1:1
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IOraclePrice_v1).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function setPriceForIssuance(uint256 price_) external {
        if (price_ == 0) revert OraclePrice__ZeroPrice();
        _priceForIssuance = price_;
    }

    function setPriceForRedemption(uint256 price_) external {
        if (price_ == 0) revert OraclePrice__ZeroPrice();
        _priceForRedemption = price_;
    }

    function getPriceForIssuance() external view returns (uint256) {
        if (_priceForIssuance == 0) revert OraclePrice__ZeroPrice();
        return _priceForIssuance;
    }

    function getPriceForRedemption() external view returns (uint256) {
        if (_priceForRedemption == 0) revert OraclePrice__ZeroPrice();
        return _priceForRedemption;
    }
}
