// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

interface IUniswapV2PairHookFactory {
    event HookCreated(address indexed token0, address indexed token1, address pair, uint);
    function createHook(address tokenA, address tokenB) external returns (address hook);
    function parameters() external view returns (address token0, address token1, IPoolManager poolManager);
}