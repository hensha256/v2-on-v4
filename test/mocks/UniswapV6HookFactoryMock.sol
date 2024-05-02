// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {UniswapV6HookFactory} from "../../src/UniswapV6HookFactory.sol";

contract UniswapV6HookFactoryMock is UniswapV6HookFactory {
    constructor(address _poolManager) UniswapV6HookFactory(_poolManager) {}
    function validPermissions_external(address hookAddress) external view returns (bool) {
        return validPermissions(hookAddress);
    }
}