// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

interface IUniswapV2PairHookFactory {
    event HookCreated(address indexed token0, address indexed token1, address pair);

    function createHook(bytes32 salt, address tokenA, address tokenB) external returns (IHooks hook);
    function getPair(address tokenA, address tokenB) external returns (address hook);
    function parameters() external view returns (Currency currency0, Currency currency1, IPoolManager poolManager);
}
