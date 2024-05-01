// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

interface IUniswapV6HookFactory {
    event HookCreated(address indexed token0, address indexed token1, address pair, uint);
    function createHook(address tokenA, address tokenB) external returns (address hook);
}