// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {UniswapV2PairHookFactory} from "../../src/UniswapV2PairHookFactory.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

contract UniswapV2PairHookFactoryMock is UniswapV2PairHookFactory {
    constructor(IPoolManager _poolManager) UniswapV2PairHookFactory(_poolManager) {}

    function validPermissions(address hookAddress) external pure returns (bool) {
        return _validPermissions(hookAddress);
    }

    function setPair(address token0, address token1, address pair) external {
        _pairs[token0][token1] = pair;
    }
}
