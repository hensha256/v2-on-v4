// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {UniswapV2PairHookFactory} from "../src/UniswapV2PairHookFactory.sol";
import {UniswapV2PairHookFactoryMock} from "./mocks/UniswapV2PairHookFactoryMock.sol";

contract UniswapV6HookFactoryTest is Test {
    UniswapV2PairHookFactoryMock factory;
    address tokenA = address(1);
    address tokenB = address(2);

    function setup() public {
        factory = new UniswapV2PairHookFactoryMock(address(this));
    }

    function test_validPermissions() public {
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
        assertTrue(factory.validPermissions_external(address(0x23C0)));
        assertTrue(factory.validPermissions_external(address(0x23C1)));
        assertFalse(factory.validPermissions_external(address(0x22C0)));
        assertFalse(factory.validPermissions_external(address(0x23F0)));
    }
}
