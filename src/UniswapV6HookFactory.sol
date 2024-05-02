// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IUniswapV6HookFactory} from "./IUniswapV6HookFactory.sol";
import {V2Hook} from "./V2Hook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

contract UniswapV6HookFactory is IUniswapV6HookFactory {
    error InvalidPermissions();
    error IdenticalAddresses();
    error ZeroAddress();
    error PairExists();

    bytes1 constant FIRST_BYTE = 0x23;
    bytes1 constant SECOND_BYTE_MASK = 0xC0;
    bytes32 constant TOKEN_0_SLOT =
        0x3cad5d3ec16e143a33da68c00099116ef328a882b65607bec5b2431267934a20;
    bytes32 constant TOKEN_1_SLOT =
        0x5b610e8e1835afecdd154863369b91f55612defc17933f83f4425533c435a248;

    IPoolManager public immutable poolManager;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    constructor(address _poolManager) {
        poolManager = IPoolManager(_poolManager);
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function validPermissions(
        address hookAddress
    ) internal pure returns (bool) {
        return (bytes20(hookAddress)[0] == FIRST_BYTE &&
            bytes20(hookAddress)[1] & SECOND_BYTE_MASK == SECOND_BYTE_MASK);
    }

    function parameters()
        external
        view
        returns (address token0, address token1, IPoolManager poolManager)
    {
        (token0, token1) = readTransientStorage();
        poolManager = poolManager;
    }

    function writeTransientStorage(address token0, address token1) internal {
        uint256 uint_token0 = uint256(uint160(token0));
        uint256 uint_token1 = uint256(uint160(token1));
        assembly {
            tstore(TOKEN_0_SLOT, uint_token0)
            tstore(TOKEN_1_SLOT, uint_token1)
        }
    }

    function readTransientStorage()
        internal
        returns (address token0, address token1)
    {
        uint256 uint_token0;
        uint256 uint_token1;
        assembly {
            uint_token0 := tload(TOKEN_0_SLOT)
            uint_token1 := tload(TOKEN_1_SLOT)
        }
        token0 = address(uint160(uint_token0));
        token1 = address(uint160(uint_token1));
    }

    function createHook(
        uint256 _salt,
        address _tokenA,
        address _tokenB
    ) external returns (address hook) {
        // Validate tokenA and tokenB are not the same address
        if (_tokenA == _tokenB) {
            revert IdenticalAddresses();
        }
        // Validate tokenA and tokenB are not the zero address
        if (_tokenA == address(0) || _tokenB == address(0)) {
            revert ZeroAddress();
        }

        // sort the tokens
        (address token0, address token1) = _tokenA < _tokenB
            ? (_tokenA, _tokenB)
            : (_tokenB, _tokenA);
        // Validate the pair does not already exist
        if (
            getPair[token0][token1] != address(0) ||
            getPair[token1][token0] != address(0)
        ) {
            revert PairExists();
        }

        // write to transient storage: poolManager, token0, token1
        writeTransientStorage(token0, token1);
        // deploy hook (expect callback to parameters)
        address deployAddress = address(new V2Hook{salt: _salt}());

        if (
            bytes20(deployAddress)[0] != FIRST_BYTE ||
            bytes20(deployAddress)[1] & SECOND_BYTE_MASK != SECOND_BYTE_MASK
        ) {
            revert InvalidPermissions();
        }

        getPair[token0][token1] = deployAddress;
        getPair[token1][token0] = deployAddress; // populate mapping in the reverse direction
        allPairs.push(deployAddress);

        emit HookCreated(token0, token1, deployAddress, allPairs.length);
    }

    function createHook(
        address tokenA,
        address tokenB
    ) external override returns (address hook) {}
}