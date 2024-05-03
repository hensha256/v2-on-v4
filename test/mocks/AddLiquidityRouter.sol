// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {V2PairHook} from "../../src/V2PairHook.sol";
import {CurrencySettleTake} from "@uniswap/v4-core/src/libraries/CurrencySettleTake.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";

contract AddLiquidityRouter is IUnlockCallback {
    using CurrencySettleTake for Currency;
    using CurrencyLibrary for Currency;

    IPoolManager immutable manager;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    function addLiquidity(V2PairHook hook, uint256 amount0, uint256 amount1)
        external
        payable
        returns (uint256 liquidity)
    {
        manager.unlock(abi.encode(msg.sender, hook, amount0, amount1));

        return hook.mint(msg.sender);
    }

    function unlockCallback(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        (address caller, V2PairHook hook, uint256 amount0, uint256 amount1) =
            abi.decode(rawData, (address, V2PairHook, uint256, uint256));

        Currency currency0 = hook.currency0();
        Currency currency1 = hook.currency1();

        currency0.settle(manager, caller, amount0, false);
        currency1.settle(manager, caller, amount1, false);

        manager.mint(address(hook), currency0.toId(), amount0);
        manager.mint(address(hook), currency1.toId(), amount1);
    }
}
