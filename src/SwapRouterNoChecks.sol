// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {CurrencySettleTake} from "@uniswap/v4-core/src/libraries/CurrencySettleTake.sol";
import {IV4Router} from "./IV4Router.sol";
import {PathKey} from "./PathKey.sol";

contract SwapRouterNoChecks is IV4Router {
    using CurrencyLibrary for Currency;
    using CurrencySettleTake for Currency;
    using Hooks for IHooks;

    IPoolManager public immutable poolManager;

    constructor(IPoolManager _manager) {
        poolManager = _manager;
    }

    error NoSwapOccurred();

    struct CallbackData {
        address sender;
        PoolKey key;
        IPoolManager.SwapParams params;
    }

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'UniswapV2Router: EXPIRED');
        _;
    }

    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        _v4Swap(
            IV4Router.SwapType.ExactInput,
            abi.encode(IV4Router.ExactInputParams({
                currencyIn: CurrencyLibrary.NATIVE,
                path: path,
                recipient: to,
                amountIn: msg.value,
                amountOutMinimum: uint128(amountOutMin)
            }))
        );
    }

    function _v4Swap(SwapType swapType, bytes memory params) internal {
        poolManager.unlock(abi.encode(SwapInfo(swapType, msg.sender, params)));
    }

    function unlockCallback(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(poolManager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        BalanceDelta delta = poolManager.swap(data.key, data.params, new bytes(0));

        if(data.params.zeroForOne) {
            data.key.currency0.settle(poolManager, data.sender, uint256(int256(-delta.amount0())), false);
            data.key.currency1.take(poolManager, data.sender, uint256(int256(delta.amount1())), false);
        } else {
            data.key.currency1.settle(poolManager, data.sender, uint256(int256(-delta.amount1())), false);
            data.key.currency0.take(poolManager, data.sender, uint256(int256(delta.amount0())), false);
        }
    }

    function _fetchBalances(Currency currency, address user, address deltaHolder)
        internal
        view
        returns (uint256 userBalance, uint256 poolBalance, int256 delta)
    {
        userBalance = currency.balanceOf(user);
        poolBalance = currency.balanceOf(address(poolManager));
        delta = poolManager.currencyDelta(deltaHolder, currency);
    }
}