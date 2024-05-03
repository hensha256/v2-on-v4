// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// V4 core
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
// Local
import {IUniswapV2PairHookFactory} from "./interfaces/IUniswapV2PairHookFactory.sol";
import {V2PairHook} from "./V2PairHook.sol";

contract UniswapV2PairHookFactory is IUniswapV2PairHookFactory {
    error InvalidPermissions();
    error IdenticalAddresses();
    error ZeroAddress();
    error PairExists();

    // Mask to extract the first 14 bits of the address
    uint160 constant FLAG_MASK = uint160(address(0xFffC000000000000000000000000000000000000));
    // A pair needs 10100011001100 - beforeInit, beforeAdd, beforeSwap, afterSwap, beforeSwapDelta, and afterSwapDelta
    uint160 constant PAIR_FLAGS = uint160(address(0xA330000000000000000000000000000000000000));

    bytes32 constant TOKEN_0_SLOT = 0x3cad5d3ec16e143a33da68c00099116ef328a882b65607bec5b2431267934a20;
    bytes32 constant TOKEN_1_SLOT = 0x5b610e8e1835afecdd154863369b91f55612defc17933f83f4425533c435a248;

    IPoolManager public immutable poolManager;

    // pairs, always stored token0 -> token1 -> pair, where token0 < token1
    mapping(address => mapping(address => address)) internal _pairs;

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
    }

    function _validPermissions(address hookAddress) internal pure returns (bool) {
        return (uint160(hookAddress) & FLAG_MASK) == PAIR_FLAGS;
    }

    function parameters() external view returns (Currency currency0, Currency currency1, IPoolManager _poolManager) {
        (currency0, currency1) = _getParameters();
        _poolManager = poolManager;
    }

    function getPair(address tokenA, address tokenB) external view returns (address) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return _pairs[token0][token1];
    }

    function _setParameters(address token0, address token1) internal {
        assembly {
            tstore(TOKEN_0_SLOT, token0)
            tstore(TOKEN_1_SLOT, token1)
        }
    }

    function _getParameters() internal view returns (Currency currency0, Currency currency1) {
        assembly {
            currency0 := tload(TOKEN_0_SLOT)
            currency1 := tload(TOKEN_1_SLOT)
        }
    }

    function createHook(bytes32 salt, address tokenA, address tokenB) external returns (IHooks hook) {
        // Validate tokenA and tokenB are not the same address
        if (tokenA == tokenB) revert IdenticalAddresses();

        // Validate tokenA and tokenB are not the zero address
        if (tokenA == address(0) || tokenB == address(0)) revert ZeroAddress();

        // sort the tokens
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        // Validate the pair does not already exist
        if (_pairs[token0][token1] != address(0)) revert PairExists();

        // write to transient storage: token0, token1
        _setParameters(token0, token1);

        // deploy hook (expect callback to parameters)
        hook = new V2PairHook{salt: salt}();
        address hookAddress = address(hook);

        if (!_validPermissions(hookAddress)) revert InvalidPermissions();

        // only write the tokens in order
        _pairs[token0][token1] = hookAddress;

        // call v4 initialize pool
        // fee and tickspacing are meaningless, they're set to 0 and 1 for all V2 Pair Hooks
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 0,
            tickSpacing: 1,
            hooks: hook
        });

        poolManager.initialize(key, 1, "");

        emit HookCreated(token0, token1, hookAddress);
    }
}
