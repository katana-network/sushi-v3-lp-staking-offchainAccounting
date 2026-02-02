// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title MockPool
 * @notice Mock Uniswap V3 Pool for testing
 */
contract MockPool {
    uint160 public mockSecondsPerLiquidity = 1000000;

    function setMockSecondsPerLiquidity(uint160 value) external {
        mockSecondsPerLiquidity = value;
    }

    function snapshotCumulativesInside(int24, int24)
        external
        view
        returns (int56 tickCumulativeInside, uint160 secondsPerLiquidityInsideX128, uint32 secondsInside)
    {
        return (0, mockSecondsPerLiquidity, 0);
    }
}
