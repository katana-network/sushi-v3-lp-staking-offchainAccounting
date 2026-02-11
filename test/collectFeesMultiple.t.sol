// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { MockERC20 } from "./utils/MockERC20.sol";
import { SushiStakerTestBase } from "./utils/SushiStakerTestBase.sol";

/**
 * @title CollectFeesMultipleTest
 * @notice Tests for the collectFeesMultiple() function
 */
contract CollectFeesMultipleTest is SushiStakerTestBase {
    /**
     * @notice Test collecting fees from multiple staked positions
     */
    function test_collectFeesMultipleSuccess() public {
        uint256 tokenId1 = _mintNft(alice);
        uint256 tokenId2 = _mintNft(alice);
        uint256 tokenId3 = _mintNft(bob);

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

        // Add fees to all positions
        mockNft.addPendingFees(tokenId1, 100 ether, 50 ether);
        mockNft.addPendingFees(tokenId2, 150 ether, 75 ether);
        mockNft.addPendingFees(tokenId3, 200 ether, 100 ether);

        uint256 feeCollectorBalance0Before = MockERC20(token0).balanceOf(feeCollector);
        uint256 feeCollectorBalance1Before = MockERC20(token1).balanceOf(feeCollector);

        // Anyone can call collectFeesMultiple
        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2;
        tokenIds[2] = tokenId3;

        vm.prank(makeAddr("anyone"));
        staker.collectFeesMultiple(tokenIds);

        // Verify feeCollector received all fees
        uint256 expectedFee0 = 100 ether + 150 ether + 200 ether;
        uint256 expectedFee1 = 50 ether + 75 ether + 100 ether;

        assertEq(MockERC20(token0).balanceOf(feeCollector), feeCollectorBalance0Before + expectedFee0);
        assertEq(MockERC20(token1).balanceOf(feeCollector), feeCollectorBalance1Before + expectedFee1);
    }

    /**
     * @notice Test that unstaked tokens are skipped during batch collection
     */
    function test_collectFeesMultipleSkipsUnstakedTokens() public {
        uint256 tokenId1 = _mintNft(alice);
        uint256 tokenId2 = _mintNft(bob); // Not staked

        vm.startPrank(alice);
        mockNft.approve(address(staker), tokenId1);
        staker.stake(tokenId1);
        vm.stopPrank();

        // Add fees to both
        mockNft.addPendingFees(tokenId1, 100 ether, 50 ether);
        mockNft.addPendingFees(tokenId2, 200 ether, 100 ether);

        uint256 feeCollectorBalance0Before = MockERC20(token0).balanceOf(feeCollector);

        // Try to collect from both (should only collect from staked)
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2; // Not staked, should be skipped

        staker.collectFeesMultiple(tokenIds);

        // Only tokenId1 fees should be collected
        assertEq(MockERC20(token0).balanceOf(feeCollector), feeCollectorBalance0Before + 100 ether);
    }
}
