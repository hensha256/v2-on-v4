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

    bytes1 constant FIRST_BYTE = 0x23;
    bytes1 constant THIRD_NIBBLE = 0x0C;
    bytes32 constant TOKEN_0_SLOT = 0x3cad5d3ec16e143a33da68c00099116ef328a882b65607bec5b2431267934a20;
    bytes32 constant TOKEN_1_SLOT = 0x5b610e8e1835afecdd154863369b91f55612defc17933f83f4425533c435a248;

    IPoolManager public immutable poolManager;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    constructor(address _poolManager) {
        poolManager = IPoolManager(_poolManager);
    }

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    function validPermissions(address hookAddress) internal pure returns (bool) {
        return (bytes20(hookAddress)[0] == FIRST_BYTE && bytes20(hookAddress)[1] >> 4 == THIRD_NIBBLE);
    }

    function parameters() external view returns (Currency token0, Currency token1, IPoolManager _poolManager) {
        (token0, token1) = _getParameters();
        _poolManager = poolManager;
    }

    function _setParameters(address token0, address token1) internal {
        assembly {
            tstore(TOKEN_0_SLOT, token0)
            tstore(TOKEN_1_SLOT, token1)
        }
    }

    function _getParameters() internal view returns (Currency token0, Currency token1) {
        assembly {
            token0 := tload(TOKEN_0_SLOT)
            token1 := tload(TOKEN_1_SLOT)
        }
    }

    function createHook(bytes32 _salt, address _tokenA, address _tokenB) external returns (IHooks hook) {
        // Validate tokenA and tokenB are not the same address
        if (_tokenA == _tokenB) revert IdenticalAddresses();

        // Validate tokenA and tokenB are not the zero address
        if (_tokenA == address(0) || _tokenB == address(0)) revert ZeroAddress();

        // sort the tokens
        (address token0, address token1) = _tokenA < _tokenB ? (_tokenA, _tokenB) : (_tokenB, _tokenA);
        // Validate the pair does not already exist
        if (getPair[token0][token1] != address(0)) revert PairExists();

        // write to transient storage: token0, token1
        _setParameters(token0, token1);

        // deploy hook (expect callback to parameters)
        hook = new V2PairHook{salt: _salt}();
        address hookAddress = address(hook);

        if (!validPermissions(hookAddress)) revert InvalidPermissions();

        // only write the tokens in order
        getPair[token0][token1] = hookAddress;

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
