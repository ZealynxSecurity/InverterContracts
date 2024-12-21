// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
 * @title Invalid Oracle Mock
 * @notice A mock contract that implements ERC165 but not IOraclePrice_v1
 */
contract InvalidOracleMock is ERC165 {
    /// @notice Override supportsInterface to return true for ERC165 but false for IOraclePrice_v1
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(ERC165).interfaceId || super.supportsInterface(interfaceId);
    }
}
