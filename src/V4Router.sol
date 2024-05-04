// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {CurrencySettleTake} from "@uniswap/v4-core/src/libraries/CurrencySettleTake.sol";

import {V2PairHook} from "./V2PairHook.sol";
import {Test, console2} from "forge-std/Test.sol";

contract V4Router is Test, IUnlockCallback {
    using CurrencyLibrary for Currency;
    using CurrencySettleTake for Currency;
    using Hooks for IHooks;

    IPoolManager public immutable poolManager;
    V2PairHook public immutable hook;

    error InsufficientOutputReceived();

    constructor(IPoolManager _manager, V2PairHook _hook) {
        hook = _hook;
        poolManager = _manager;
    }

    error NoSwapOccurred();

    struct CallbackData {
        address sender;
        PoolKey key;
        IPoolManager.SwapParams params;
    }

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "UniswapV2Router: EXPIRED");
        _;
    }

    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline)
        external
        payable
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        require(path[0] == address(0));
        uint256 amountOut = abi.decode(poolManager.unlock(abi.encode(amountOutMin, msg.value, path, to)), (uint256));
        amounts = new uint256[](1);
        amounts[0] = amountOut;
    }

    function unlockCallback(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(poolManager));

        (uint256 amountOutMin, uint256 amountIn, address[] memory path, address to) =
            abi.decode(rawData, (uint256, uint256, address[], address));

        require(path.length == 2);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(path[0]),
            currency1: Currency.wrap(path[1]),
            fee: 0,
            tickSpacing: 1,
            hooks: hook
        });

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -int256(amountIn), sqrtPriceLimitX96: 0});

        BalanceDelta delta = poolManager.swap(key, params, "");

        uint256 amountOut = uint256(int256(delta.amount1()));
        if (amountOut < amountOutMin) revert InsufficientOutputReceived();

        CurrencyLibrary.NATIVE.settle(poolManager, address(this), amountIn, false);
        key.currency1.take(poolManager, to, amountOut, false);
        return abi.encode(amountOut);
    }
}
