// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Local
import {V2PairHook} from "../src/V2PairHook.sol";
import {AddLiquidityRouter} from "./mocks/AddLiquidityRouter.sol";
// Solmate
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
// Forge
import {Test, console2} from "forge-std/Test.sol";
// V4
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

contract V2PairHookTest is Test {
    uint160 public constant SQRT_RATIO_1_1 = 79228162514264337593543950336;

    V2PairHook hook;
    Currency currency0;
    Currency currency1;
    PoolManager manager;
    AddLiquidityRouter liquidityRouter;

    function parameters() external view returns (Currency, Currency, IPoolManager) {
        return (currency0, currency1, manager);
    }

    function deployMintAndApprove2Currencies() internal {
        MockERC20 tokenA = new MockERC20("TEST", "TEST", 18);
        tokenA.mint(address(this), 2 ** 255);
        tokenA.approve(address(liquidityRouter), type(uint256).max);
        Currency currencyA = Currency.wrap(address(tokenA));

        MockERC20 tokenB = new MockERC20("TEST2", "TEST2", 18);
        tokenB.mint(address(this), 2 ** 255);
        tokenB.approve(address(liquidityRouter), type(uint256).max);
        Currency currencyB = Currency.wrap(address(tokenB));

        (currency0, currency1) = address(tokenA) < address(tokenB) ? (currencyA, currencyB) : (currencyB, currencyA);
    }

    function setUp() public {
        manager = new PoolManager(500000);
        liquidityRouter = new AddLiquidityRouter(manager);

        deployMintAndApprove2Currencies();

        // The constructor will call back and fetch the manager and currencies
        address hookAddr = address(uint160((1 << 159) + (1 << 157) + (1 << 153) + (1 << 152) + (1 << 149) + (1 << 148)));
        V2PairHook impl = new V2PairHook();
        vm.etch(hookAddr, address(impl).code);
        hook = V2PairHook(hookAddr);
    }

    function test_hookAddress_isValid() public view {
        hook.validateHookAddress();
    }

    function test_initialize_succeeds() public {
        PoolKey memory key = PoolKey({currency0: currency0, currency1: currency1, fee: 0, tickSpacing: 1, hooks: hook});

        manager.initialize(key, SQRT_RATIO_1_1, "");
    }

    function test_mint_liquidity() public {
        PoolKey memory key = PoolKey({currency0: currency0, currency1: currency1, fee: 0, tickSpacing: 1, hooks: hook});
        manager.initialize(key, SQRT_RATIO_1_1, "");

        uint256 balanceBefore = hook.balanceOf(address(this));
        uint256 liquidity = liquidityRouter.addLiquidity(hook, 1e18, 1e18);
        uint256 balanceAfter = hook.balanceOf(address(this));

        assertEq(balanceBefore + liquidity, balanceAfter);
        assertGt(liquidity, 0);
    }
}
