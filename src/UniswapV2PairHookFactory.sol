// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IUniswapV2PairHookFactory} from "./interfaces/IUniswapV2PairHookFactory.sol";
import {V2PairHook} from "./V2PairHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/libraries/PoolKey.sol";

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
        return (bytes20(hookAddress)[0] == FIRST_BYTE && bytes20(hookAddress)[1] >> 4  == THIRD_NIBBLE);
    }

    function parameters() external view returns (address token0, address token1, IPoolManager _poolManager) {
        (token0, token1) = readTransientStorage();
        _poolManager = poolManager;
    }

    function writeTransientStorage(address token0, address token1) internal {
        assembly {
            tstore(TOKEN_0_SLOT, token0)
            tstore(TOKEN_1_SLOT, token1)
        }
    }

    function readTransientStorage() internal view returns (address token0, address token1) {
        assembly {
            token0 := tload(TOKEN_0_SLOT)
            token1 := tload(TOKEN_1_SLOT)
        }
    }

    function createHook(bytes32 _salt, address _tokenA, address _tokenB) external returns (address hook) {
        // Validate tokenA and tokenB are not the same address
        if (_tokenA == _tokenB) {
            revert IdenticalAddresses();
        }
        // Validate tokenA and tokenB are not the zero address
        if (_tokenA == address(0) || _tokenB == address(0)) {
            revert ZeroAddress();
        }

        // sort the tokens
        (address token0, address token1) = _tokenA < _tokenB ? (_tokenA, _tokenB) : (_tokenB, _tokenA);
        // Validate the pair does not already exist
        if (getPair[token0][token1] != address(0) || getPair[token1][token0] != address(0)) {
            revert PairExists();
        }

        // write to transient storage: poolManager, token0, token1
        writeTransientStorage(token0, token1);
        // deploy hook (expect callback to parameters)
        hook = new V2PairHook{salt: _salt}();
        address hookAddress = address(hook);
        if (!validPermissions(hookAddress)) {
            revert InvalidPermissions();
        }

        getPair[token0][token1] = hookAddress;
        getPair[token1][token0] = hookAddress; // populate mapping in the reverse direction
        allPairs.push(hookAddress);

        // call v4 initialize pool
        // fee and tickspacing are irrelevant, so set to 0 and 1
        PoolKey memory key = PoolKey({token0: token0, token1: token1, fee: 0, tickSpacing: 1, hooks: hook});

        poolManager.initialize(key, 1, hook);

        emit HookCreated(token0, token1, hookAddress, allPairs.length);
    }
}
