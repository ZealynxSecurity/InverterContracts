// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import {LM_ManualExternalPriceSetter_v1} from
    "@lm/LM_ManualExternalPriceSetter_v1.sol";

contract LM_ManualExternalPriceSetter_v1_Exposed is
    LM_ManualExternalPriceSetter_v1
{
    function exposed_normalizePrice(uint price_, uint8 tokenDecimals_)
        external
        pure
        returns (uint)
    {
        return _normalizePrice(price_, tokenDecimals_);
    }

    function exposed_denormalizePrice(uint price_, uint8 tokenDecimals_)
        external
        view
        returns (uint)
    {
        return _denormalizePrice(price_, tokenDecimals_);
    }
}
