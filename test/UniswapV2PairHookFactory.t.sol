// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {UniswapV2PairHookFactory} from "../src/UniswapV2PairHookFactory.sol";
import {UniswapV2PairHookFactoryMock} from "./mocks/UniswapV2PairHookFactoryMock.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

contract UniswapV6HookFactoryTest is Test {
    UniswapV2PairHookFactoryMock factory;

    function setUp() public {
        factory = new UniswapV2PairHookFactoryMock(IPoolManager(address(0)));
    }

    function test_validPermissions() public {
        // Validate hook permissions https://github.com/Uniswap/v4-core/blob/hooks-return-delta/src/libraries/Hooks.sol#L21 in the address

        uint160 correctPermissions = (1 << 159) + (1 << 157) + (1 << 153) + (1 << 152) + (1 << 149) + (1 << 148);

        assertTrue(factory.validPermissions(address(correctPermissions)));

        // cannot add other flags
        assertFalse(factory.validPermissions(address(correctPermissions + (1 << 151))));
        assertFalse(factory.validPermissions(address(correctPermissions + (1 << 150))));
        assertFalse(factory.validPermissions(address(correctPermissions + (1 << 147))));
        assertFalse(factory.validPermissions(address(correctPermissions + (1 << 146))));

        // can add to other parts of the address
        assertTrue(factory.validPermissions(address(correctPermissions + 12342134)));

        // cannot remove any flag
        assertFalse(factory.validPermissions(address(correctPermissions - (1 << 159))));
        assertFalse(factory.validPermissions(address(correctPermissions - (1 << 157))));
        assertFalse(factory.validPermissions(address(correctPermissions - (1 << 153))));
        assertFalse(factory.validPermissions(address(correctPermissions - (1 << 152))));
    }
}
