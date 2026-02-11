// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/**
 * @title MockFactory
 * @notice Mock Uniswap V3 Factory for testing
 */
contract MockFactory {
    mapping(address => mapping(address => mapping(uint24 => address))) public pools;

    function setPool(address token0, address token1, uint24 fee, address pool) external {
        pools[token0][token1][fee] = pool;
        pools[token1][token0][fee] = pool;
    }

    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address) {
        return pools[tokenA][tokenB][fee];
    }
}
