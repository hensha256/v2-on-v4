// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// V4 core
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
// Solmate
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
// Local
import {Math} from "./libraries/Math.sol";
import {UnsafeMath} from "./libraries/UnsafeMath.sol";
import {IV2PairHookDeployer} from "./interfaces/IV2PairHookDeployer.sol";
import {BaseHook} from "./BaseHook.sol";

contract V2PairHook is BaseHook, ERC20 {
    using SafeTransferLib for ERC20;
    using UnsafeMath for uint256;

    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;
    ERC20 public immutable token0;
    ERC20 public immutable token1;

    error BalanceOverflow();
    error InsufficientLiquidityMinted();
    error InsufficientLiquidityBurnt();

    // TODO 6909 integ
    // TODO reserves 128
    // TODO delete v2 submodule
    // TODO swap function
    // TODO combine all hooks to 1

    uint112 private reserve0;
    uint112 private reserve1;
    uint256 public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

    // TODO lock???

    constructor() ERC20("Uniswap V4-V2", "UNI-V4-V2", 18) {
        (token0, token1, poolManager) = IV2PairHookDeployer(msg.sender).parameters();
    }

    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
    }

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    // update reserves
    function _update(uint256 balance0, uint256 balance1) private {
        if (balance0 > type(uint112).max || balance1 > type(uint112).max) revert BalanceOverflow();
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        emit Sync(reserve0, reserve1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function mint(address to) external returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1) = getReserves();
        uint256 _totalSupply = totalSupply;

        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity = Math.min((amount0 * _totalSupply).unsafeDiv(_reserve0), (amount1 * _totalSupply).unsafeDiv(_reserve1));
        }
        if (liquidity == 0) revert InsufficientLiquidityMinted();
        _mint(to, liquidity);

        _update(balance0, balance1);
        emit Mint(msg.sender, amount0, amount1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function burn(address to) external returns (uint256 amount0, uint256 amount1) {
        ERC20 _token0 = token0; // gas savings
        ERC20 _token1 = token1; // gas savings
        uint256 _totalSupply = totalSupply; // gas savings

        uint256 balance0 = _token0.balanceOf(address(this));
        uint256 balance1 = _token1.balanceOf(address(this));
        uint256 liquidity = balanceOf[address(this)];

        amount0 = (liquidity * balance0).unsafeDiv(_totalSupply); // using balances ensures pro-rata distribution
        amount1 = (liquidity * balance1).unsafeDiv(_totalSupply); // using balances ensures pro-rata distribution
        if (amount0 == 0 || amount1 == 0) revert InsufficientLiquidityBurnt();

        _burn(address(this), liquidity);
        _token0.safeTransfer(to, amount0);
        _token1.safeTransfer(to, amount1);
        balance0 = _token0.balanceOf(address(this));
        balance1 = _token1.balanceOf(address(this));

        _update(balance0, balance1);
        emit Burn(msg.sender, amount0, amount1, to);
    }

    // force balances to match reserves
    function skim(address to) external {
        ERC20 _token0 = token0; // gas savings
        ERC20 _token1 = token1; // gas savings
        _token0.safeTransfer(to, _token0.balanceOf(address(this)) - reserve0);
        _token1.safeTransfer(to, _token1.balanceOf(address(this)) - reserve1);
    }

    // force reserves to match balances
    function sync() external {
        _update(token0.balanceOf(address(this)), token1.balanceOf(address(this)));
    }

    // TODO
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
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
}
