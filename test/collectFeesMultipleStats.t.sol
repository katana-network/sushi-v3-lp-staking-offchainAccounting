// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { SushiStaker } from "../src/SushiStaker.sol";
import { SushiStakerTestBase } from "./utils/SushiStakerTestBase.sol";

/**
 * @title CollectFeesMultipleStatsTest
 * @notice Tests for the collectFeesMultipleStats() view function
 */
contract CollectFeesMultipleStatsTest is SushiStakerTestBase {
    /**
     * @notice Test stats with empty array
     */
    function test_CollectFeesMultipleStats_EmptyArray() public view {
        uint256[] memory tokenIds = new uint256[](0);

        SushiStaker.FeeStats memory stats = staker.collectFeesMultipleStats(tokenIds);

        assertEq(stats.totalTokensOwed0, 0);
        assertEq(stats.totalTokensOwed1, 0);
        assertEq(stats.stakedTokensCount, 0);
        assertEq(stats.unstakedTokensCount, 0);
        assertEq(stats.totalLiquidity, 0);
        assertEq(stats.unstakedTokenIds.length, 0);
    }

    /**
     * @notice Test stats with single staked token
     */
    function test_CollectFeesMultipleStats_SingleStakedToken() public {
        uint256 tokenId = _mintNft(alice);

        vm.startPrank(alice);
        mockNft.approve(address(staker), tokenId);
        staker.stake(tokenId);
        vm.stopPrank();

        // Add pending fees
        mockNft.addPendingFees(tokenId, 100 ether, 50 ether);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        SushiStaker.FeeStats memory stats = staker.collectFeesMultipleStats(tokenIds);

        assertEq(stats.totalTokensOwed0, 100 ether);
        assertEq(stats.totalTokensOwed1, 50 ether);
        assertEq(stats.stakedTokensCount, 1);
        assertEq(stats.unstakedTokensCount, 0);
        assertEq(stats.totalLiquidity, LIQUIDITY);
        assertEq(stats.unstakedTokenIds.length, 0);
    }

    /**
     * @notice Test stats with multiple staked tokens
     */
    function test_CollectFeesMultipleStats_MultipleStakedTokens() public {
        uint256 tokenId1 = mockNft.mint(alice, token0, token1, FEE, TICK_LOWER, TICK_UPPER, LIQUIDITY);
        uint256 tokenId2 = mockNft.mint(alice, token0, token1, FEE, TICK_LOWER, TICK_UPPER, LIQUIDITY * 2);
        uint256 tokenId3 = mockNft.mint(bob, token0, token1, FEE, TICK_LOWER, TICK_UPPER, LIQUIDITY * 3);

        // Stake all tokens
        vm.startPrank(alice);
        mockNft.approve(address(staker), tokenId1);
        mockNft.approve(address(staker), tokenId2);
        staker.stake(tokenId1);
        staker.stake(tokenId2);
        vm.stopPrank();

        vm.startPrank(bob);
        mockNft.approve(address(staker), tokenId3);
        staker.stake(tokenId3);
        vm.stopPrank();

        // Add different fees to each position
        mockNft.addPendingFees(tokenId1, 100 ether, 50 ether);
        mockNft.addPendingFees(tokenId2, 200 ether, 100 ether);
        mockNft.addPendingFees(tokenId3, 300 ether, 150 ether);

        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2;
        tokenIds[2] = tokenId3;

        SushiStaker.FeeStats memory stats = staker.collectFeesMultipleStats(tokenIds);

        assertEq(stats.totalTokensOwed0, 600 ether); // 100 + 200 + 300
        assertEq(stats.totalTokensOwed1, 300 ether); // 50 + 100 + 150
        assertEq(stats.stakedTokensCount, 3);
        assertEq(stats.unstakedTokensCount, 0);
        assertEq(stats.totalLiquidity, LIQUIDITY + LIQUIDITY * 2 + LIQUIDITY * 3); // 1M + 2M + 3M = 6M
        assertEq(stats.unstakedTokenIds.length, 0);
    }

    /**
     * @notice Test stats with mixed staked and unstaked tokens
     */
    function test_CollectFeesMultipleStats_MixedStakedAndUnstaked() public {
        uint256 tokenId1 = _mintNft(alice);
        uint256 tokenId2 = _mintNft(alice);
        uint256 tokenId3 = _mintNft(bob);

        // Only stake tokenId1 and tokenId3
        vm.startPrank(alice);
        mockNft.approve(address(staker), tokenId1);
        staker.stake(tokenId1);
        vm.stopPrank();

        vm.startPrank(bob);
        mockNft.approve(address(staker), tokenId3);
        staker.stake(tokenId3);
        vm.stopPrank();

        // Add fees (tokenId2 is not staked)
        mockNft.addPendingFees(tokenId1, 100 ether, 50 ether);
        mockNft.addPendingFees(tokenId2, 999 ether, 999 ether); // Should not be counted
        mockNft.addPendingFees(tokenId3, 200 ether, 100 ether);

        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2; // Not staked
        tokenIds[2] = tokenId3;

        SushiStaker.FeeStats memory stats = staker.collectFeesMultipleStats(tokenIds);

        assertEq(stats.totalTokensOwed0, 300 ether); // Only from staked tokens
        assertEq(stats.totalTokensOwed1, 150 ether); // Only from staked tokens
        assertEq(stats.stakedTokensCount, 2);
        assertEq(stats.unstakedTokensCount, 1);
        assertEq(stats.totalLiquidity, LIQUIDITY * 2);

        // Verify unstaked token ID is correctly identified
        assertEq(stats.unstakedTokenIds.length, 1);
        assertEq(stats.unstakedTokenIds[0], tokenId2);
    }

    /**
     * @notice Test stats with all unstaked tokens
     */
    function test_CollectFeesMultipleStats_AllUnstaked() public {
        uint256 tokenId1 = _mintNft(alice);
        uint256 tokenId2 = _mintNft(bob);

        // Add fees but don't stake
        mockNft.addPendingFees(tokenId1, 100 ether, 50 ether);
        mockNft.addPendingFees(tokenId2, 200 ether, 100 ether);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2;

        SushiStaker.FeeStats memory stats = staker.collectFeesMultipleStats(tokenIds);

        assertEq(stats.totalTokensOwed0, 0); // No staked tokens
        assertEq(stats.totalTokensOwed1, 0); // No staked tokens
        assertEq(stats.stakedTokensCount, 0);
        assertEq(stats.unstakedTokensCount, 2);
        assertEq(stats.totalLiquidity, 0);

        // Verify all unstaked token IDs are returned
        assertEq(stats.unstakedTokenIds.length, 2);
        assertEq(stats.unstakedTokenIds[0], tokenId1);
        assertEq(stats.unstakedTokenIds[1], tokenId2);
    }

    /**
     * @notice Test stats with staked tokens but no fees
     */
    function test_CollectFeesMultipleStats_NoFees() public {
        uint256 tokenId1 = _mintNft(alice);
        uint256 tokenId2 = _mintNft(bob);

        vm.startPrank(alice);
        mockNft.approve(address(staker), tokenId1);
        staker.stake(tokenId1);
        vm.stopPrank();

        vm.startPrank(bob);
        mockNft.approve(address(staker), tokenId2);
        staker.stake(tokenId2);
        vm.stopPrank();

        // No fees added

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2;

        SushiStaker.FeeStats memory stats = staker.collectFeesMultipleStats(tokenIds);

        assertEq(stats.totalTokensOwed0, 0);
        assertEq(stats.totalTokensOwed1, 0);
        assertEq(stats.stakedTokensCount, 2);
        assertEq(stats.unstakedTokensCount, 0);
        assertEq(stats.totalLiquidity, LIQUIDITY * 2);
        assertEq(stats.unstakedTokenIds.length, 0);
    }
}
