// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {UniswapV2PairHookFactory} from "../../src/UniswapV2PairHookFactory.sol";

contract UniswapV2PairHookFactoryMock is UniswapV2PairHookFactory {
    constructor(address _poolManager) UniswapV2PairHookFactory(_poolManager) {}

    function validPermissions_external(address hookAddress) external pure returns (bool) {
        return validPermissions(hookAddress);
    }
}
