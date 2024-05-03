// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// V4 core
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {CurrencySettleTake} from "@uniswap/v4-core/src/libraries/CurrencySettleTake.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
// Solmate
import {ERC20} from "solmate/src/tokens/ERC20.sol";
// Local
import {Math} from "./libraries/Math.sol";
import {UnsafeMath} from "./libraries/UnsafeMath.sol";
import {IUniswapV2PairHookFactory} from "./interfaces/IUniswapV2PairHookFactory.sol";
import {BaseHook} from "./BaseHook.sol";

contract V2PairHook is BaseHook, ERC20 {
    using UnsafeMath for uint256;
    using CurrencySettleTake for Currency;
    using CurrencyLibrary for Currency;

    error BalanceOverflow();
    error InvalidInitialization();
    error InsufficientLiquidityMinted();
    error InsufficientLiquidityBurnt();
    error AddLiquidityDirectToHook();
    error IncorrectSwapAmount();

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(uint256 amountIn, uint256 amountOut);
    event Sync(uint128 reserves0, uint128 reserves1);

    // TODO delete v2 submodule
    // TODO combine all hooks to 1 - separate wrapper for rebasing

    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;
    Currency public immutable currency0;
    Currency public immutable currency1;
    address public immutable factory;

    uint128 private reserves0;
    uint128 private reserves1;
    uint256 public kLast; // reserves0 * reserves1, as of immediately after the most recent liquidity event

    // keccak(DeltaUnspecified) - 1
    bytes32 constant DELTA_UNSPECIFIED_SLOT = 0x2e5feb220472ad9c92768617797b419bfabdc71375060ca8a1052c1ad7a5383b;

    // TODO lock???

    constructor() ERC20("Uniswap V4-V2", "UNI-V4-V2", 18) {
        (currency0, currency1, poolManager) = IUniswapV2PairHookFactory(msg.sender).parameters();
        factory = msg.sender;
    }

    function getReserves() public view returns (uint128 _reserves0, uint128 _reserves1) {
        _reserves0 = reserves0;
        _reserves1 = reserves1;
    }

    // ******************** V2 FUNCTIONS ********************

    // this low-level function should be called from a contract which performs important safety checks
    function mint(address to) external returns (uint256 liquidity) {
        (uint128 _reserves0, uint128 _reserves1) = getReserves();
        uint256 _totalSupply = totalSupply;

        // The caller has already minted 6909s on the PoolManager to this address
        uint256 balance0 = poolManager.balanceOf(address(this), CurrencyLibrary.toId(currency0));
        uint256 balance1 = poolManager.balanceOf(address(this), CurrencyLibrary.toId(currency1));
        uint256 amount0 = balance0 - _reserves0;
        uint256 amount1 = balance1 - _reserves1;

        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity =
                Math.min((amount0 * _totalSupply).unsafeDiv(_reserves0), (amount1 * _totalSupply).unsafeDiv(_reserves1));
        }
        if (liquidity == 0) revert InsufficientLiquidityMinted();
        _mint(to, liquidity);

        _update(balance0, balance1);
        emit Mint(msg.sender, amount0, amount1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function burn(address to) external returns (uint256 amount0, uint256 amount1) {
        uint256 balance0 = poolManager.balanceOf(address(this), CurrencyLibrary.toId(currency0));
        uint256 balance1 = poolManager.balanceOf(address(this), CurrencyLibrary.toId(currency1));
        uint256 liquidity = balanceOf[address(this)];

        amount0 = (liquidity * balance0).unsafeDiv(totalSupply); // using balances ensures pro-rata distribution
        amount1 = (liquidity * balance1).unsafeDiv(totalSupply); // using balances ensures pro-rata distribution
        if (amount0 == 0 || amount1 == 0) revert InsufficientLiquidityBurnt();

        _burn(address(this), liquidity);

        _burn6909s(amount0, amount1, to);
        balance0 -= amount0;
        balance1 -= amount1;

        _update(balance0, balance1);
        emit Burn(msg.sender, amount0, amount1, to);
    }

    // force balances to match reserves
    function skim(address to) external {
        currency0.transfer(to, currency0.balanceOf(address(this)) - reserves0);
        currency1.transfer(to, currency1.balanceOf(address(this)) - reserves1);
    }

    // force reserves to match balances
    function sync() external {
        _update(currency0.balanceOf(address(this)), currency1.balanceOf(address(this)));
    }

    // ******************** HOOK FUNCTIONS ********************

    function beforeInitialize(address sender, PoolKey calldata key, uint160, bytes calldata)
        external
        view
        override
        poolManagerOnly
        returns (bytes4)
    {
        // TODO think
        if (
            sender != factory || key.fee != 0 || key.tickSpacing != 1
                || Currency.unwrap(key.currency0) != Currency.unwrap(currency0)
                || Currency.unwrap(key.currency1) != Currency.unwrap(currency1)
        ) revert InvalidInitialization();
        return IHooks.beforeInitialize.selector;
    }

    // Reverts as liquidity should be added by calling `mint` on this contract
    function beforeAddLiquidity(address, PoolKey calldata, IPoolManager.ModifyLiquidityParams calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert AddLiquidityDirectToHook();
    }

    function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata)
        external
        override
        poolManagerOnly
        returns (bytes4, int128)
    {
        bool exactIn = (params.amountSpecified < 0);

        uint256 amountIn;
        uint256 amountOut;
        if (exactIn) {
            amountIn = uint256(-params.amountSpecified);
            amountOut = _getAmountOut(params.zeroForOne, amountIn);
        } else {
            amountOut = uint256(params.amountSpecified);
            amountIn = _getAmountIn(params.zeroForOne, amountOut);
        }

        (Currency inputCurrency, Currency outputCurrency) = _getInputOutput(key, params.zeroForOne);

        // take the input tokens of the swap into the pair
        poolManager.mint(address(this), CurrencyLibrary.toId(inputCurrency), amountIn);
        poolManager.burn(address(this), CurrencyLibrary.toId(outputCurrency), amountOut);

        uint256 balance0 = poolManager.balanceOf(address(this), CurrencyLibrary.toId(currency0));
        uint256 balance1 = poolManager.balanceOf(address(this), CurrencyLibrary.toId(currency1));

        // uint balance0Adjusted = balance0.mul(1000).sub(amount0In.mul(3));
        // uint balance1Adjusted = balance1.mul(1000).sub(amount1In.mul(3));
        // require(balance0Adjusted.mul(balance1Adjusted) >= uint(_reserves0).mul(_reserves1).mul(1000**2), 'UniswapV2: K');

        _update(balance0, balance1);

        // amountIn positive as hook takes it, amountOut negative as hook gives it
        int128 deltaUnspecified = exactIn ? -int128(uint128(amountOut)) : int128(uint128(amountIn));
        assembly {
            tstore(DELTA_UNSPECIFIED_SLOT, deltaUnspecified)
        }

        emit Swap(amountIn, amountOut);

        // return -amountSpecified to no-op the concentrated liquidity swap
        return (IHooks.beforeSwap.selector, int128(-params.amountSpecified));
    }

    function afterSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        external
        view
        override
        returns (bytes4, int128)
    {
        int128 deltaUnspecified;
        assembly {
            deltaUnspecified := tload(DELTA_UNSPECIFIED_SLOT)
        }
        return (IHooks.afterSwap.selector, deltaUnspecified);
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // ******************** INTERNAL FUNCTIONS ********************

    function _update(uint256 balance0, uint256 balance1) private {
        if (balance0 > type(uint128).max || balance1 > type(uint128).max) revert BalanceOverflow();
        reserves0 = uint128(balance0);
        reserves1 = uint128(balance1);
        emit Sync(reserves0, reserves1);
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function _getAmountOut(bool zeroForOne, uint256 amountIn) internal view returns (uint256 amountOut) {
        require(amountIn > 0, "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT");

        (uint256 reservesIn, uint256 reservesOut) = zeroForOne ? (reserves0, reserves1) : (reserves1, reserves0);
        require(reserves0 > 0 && reserves1 > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");

        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reservesOut;
        uint256 denominator = (reservesIn * 1000) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function _getAmountIn(bool zeroForOne, uint256 amountOut) internal view returns (uint256 amountIn) {
        require(amountOut > 0, "UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT");

        (uint256 reservesIn, uint256 reservesOut) = zeroForOne ? (reserves0, reserves1) : (reserves1, reserves0);
        require(reservesIn > 0 && reservesOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");

        uint256 numerator = reservesIn * amountOut * 1000;
        uint256 denominator = (reservesOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }

    function _getInputOutput(PoolKey calldata key, bool zeroForOne)
        internal
        pure
        returns (Currency input, Currency output)
    {
        (input, output) = zeroForOne ? (key.currency0, key.currency1) : (key.currency1, key.currency0);
    }

    // ******************** 6909 BURNING ********************

    function _burn6909s(uint256 amount0, uint256 amount1, address to) internal {
        poolManager.unlock(abi.encode(amount0, amount1, to));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        (uint256 amount0, uint256 amount1, address to) = abi.decode(data, (uint256, uint256, address));

        poolManager.burn(address(this), CurrencyLibrary.toId(currency0), amount0);
        poolManager.burn(address(this), CurrencyLibrary.toId(currency1), amount1);
        currency0.take(poolManager, to, amount0, false);
        currency1.take(poolManager, to, amount1, false);
    }
}
