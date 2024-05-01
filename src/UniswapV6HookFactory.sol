// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IUniswapV6HookFactory} from "./IUniswapV6HookFactory.sol";
import {V2Hook} from "./V2Hook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

contract UniswapV2Factory is IUniswapV6HookFactory {

    error InvalidPermissions();
    error IdenticalAddresses();
    error ZeroAddress();
    error PairExists();

    bytes1 constant FIRST_BYTE = 0x23;
    bytes1 constant SECOND_BYTE_MASK = 0xC0;
    bytes32 constant TOKEN_0_SLOT = 0x3cad5d3ec16e143a33da68c00099116ef328a882b65607bec5b2431267934a20;
    bytes32 constant TOKEN_1_SLOT = 0x5b610e8e1835afecdd154863369b91f55612defc17933f83f4425533c435a248;

    IPoolManager public immutable poolManager;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event HookCreated(address indexed token0, address indexed token1, address pair, uint);

    constructor(address _feeToSetter, address _poolManager) public {
        feeToSetter = _feeToSetter;
        poolManager = IPoolManager(_poolManager);
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function validPermissions(address hookAddress) internal pure returns (bool) {
        return (
            bytes20(hookAddress)[0] == FIRST_BYTE && 
            bytes20(hookAddress)[1] & SECOND_BYTE_MASK == SECOND_BYTE_MASK
        );
    }

    function parameters() external view returns (address token0, address token1, IPoolManager poolManager){
        (token0, token1) = readTransientStorage();
        poolManager = poolManager;       
    }

    function writeTransientStorage(address token0, address token1) internal {
        uint256 uint_token0 = uint256(uint160(token0));
        uint256 uint_token1 = uint256(uint160(token1));
        assembly {
            tstore(TOKEN_0_SLOT, uint_token0)
            tstore(TRANSIENT_ADDRESS_1, uint_token1)
        }
    }

    function readTransientStorage() internal returns (address token0, address token1){
        uint256 uint_token0;
        uint256 uint_token1;
        assembly {
            uint_token0 := tload(TOKEN_0_SLOT)
            uint_token1 := tload(TRANSIENT_ADDRESS_1)
        }
        token0 = address(uint160(uint_token0));
        token1 = address(uint160(uint_token1));
    }

    function createHook(uint256 _salt, address _tokenA, address _tokenB) external returns (address hook) {

        // Validate tokenA and tokenB are not the same address
        if(tokenA == tokenB) {
            revert IdenticalAddresses();
        }
        // Validate tokenA and tokenB are not the zero address
        if(tokenA == address(0) || tokenB == address(0)) {
            revert ZeroAddress();
        }

        // sort the tokens
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        // Validate the pair does not already exist
        if(getPair[token0][token1] != address(0) || getPair[token1][token0] != address(0)) {
            revert PairExists();
        }

        // write to transient storage: poolManager, token0, token1
        writeTransientStorage(token0, token1);
        // deploy hook (expect callback to parameters)
        address deployAddress = new V2Hook{salt: _salt}();
        // delete the transient storage

        // Validate hook permissions https://github.com/Uniswap/v4-core/blob/hooks-return-delta/src/libraries/Hooks.sol#L21 in the address
        
        /* 
            maybe (probably not) uint256 internal constant BEFORE_INITIALIZE_FLAG = 1 << 159; 
            Will definitely need 
    
            uint256 internal constant BEFORE_ADD_LIQUIDITY_FLAG = 1 << 157; // (Bit 157)
            uint256 internal constant BEFORE_SWAP_FLAG = 1 << 153; // (Bit 153)
            uint256 internal constant AFTER_SWAP_FLAG = 1 << 152; // (Bit 152)

            uint256 internal constant BEFORE_SWAP_RETURNS_DELTA_FLAG = 1 << 149;
            uint256 internal constant AFTER_SWAP_RETURNS_DELTA_FLAG = 1 << 148;
            First byte would be 
            0010 0011
            0x23 
            Second byte would be 
            1100 xxxx
            0xCX
        */

        if(
            bytes20(deployAddress)[0] != FIRST_BYTE || 
            bytes20(deployAddress)[1] & SECOND_BYTE_MASK != SECOND_BYTE_MASK
        ) {
            revert InvalidPermissions();
        }
       
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);

        emit HookCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, 'UniswapV2: FORBIDDEN');
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, 'UniswapV2: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }
}