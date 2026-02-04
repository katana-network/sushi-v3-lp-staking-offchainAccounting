// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {SushiStakerTestBase} from "./utils/SushiStakerTestBase.sol";
import {SushiStaker} from "../src/SushiStaker.sol";
import {MockERC20} from "./utils/MockERC20.sol";

/**
 * @title StakeTest
 * @notice Tests for the stake() function
 */
contract StakeTest is SushiStakerTestBase {
    /**
     * @notice Test successful staking via stake()
     */
    function test_StakeSuccess() public {
        uint256 tokenId = _mintNFT(alice);

        vm.startPrank(alice);
        mockNFT.approve(address(staker), tokenId);
        staker.stake(tokenId);
        vm.stopPrank();

        // Verify staking state
        assertEq(staker.isStaked(tokenId), true);
        assertEq(staker.getStaker(tokenId), alice);
        assertEq(staker.getStakeTimestamp(tokenId), block.timestamp);
        assertEq(mockNFT.ownerOf(tokenId), address(staker));
    }

    /**
     * @notice Test TokenStaked event is emitted with correct data
     */
    function test_StakeEmitsEvent() public {
        uint256 tokenId = _mintNFT(alice);

        vm.startPrank(alice);
        mockNFT.approve(address(staker), tokenId);

        vm.expectEmit(true, true, false, true);
        emit SushiStaker.TokenStaked(
            alice,
            tokenId,
            address(mockPool),
            TICK_LOWER,
            TICK_UPPER,
            LIQUIDITY,
            1000000, // mockSecondsPerLiquidity
            block.timestamp
        );

        staker.stake(tokenId);
        vm.stopPrank();
    }

    /**
     * @notice Test pre-stake fees are collected and sent to staker
     */
    function test_StakeCollectsPreStakeFees() public {
        uint256 tokenId = _mintNFT(alice);

        // Add pending fees before staking
        uint256 preFee0 = 100 ether;
        uint256 preFee1 = 50 ether;
        mockNFT.addPendingFees(tokenId, preFee0, preFee1);

        uint256 aliceBalance0Before = MockERC20(token0).balanceOf(alice);
        uint256 aliceBalance1Before = MockERC20(token1).balanceOf(alice);

        vm.startPrank(alice);
        mockNFT.approve(address(staker), tokenId);
        staker.stake(tokenId);
        vm.stopPrank();

        // Verify alice received the pre-stake fees
        assertEq(MockERC20(token0).balanceOf(alice), aliceBalance0Before + preFee0);
        assertEq(MockERC20(token1).balanceOf(alice), aliceBalance1Before + preFee1);
    }

    /**
     * @notice Test revert when caller doesn't own the NFT
     */
    function test_StakeRevertsNotTokenOwner() public {
        uint256 tokenId = _mintNFT(alice);

        // Bob tries to stake Alice's token
        vm.prank(bob);
        vm.expectRevert(SushiStaker.NotTokenOwner.selector);
        staker.stake(tokenId);
    }

    /**
     * @notice Test revert when position has zero liquidity
     */
    function test_StakeRevertsZeroLiquidity() public {
        uint256 tokenId = _mintNFT(alice, 0);

        vm.startPrank(alice);
        mockNFT.approve(address(staker), tokenId);

        vm.expectRevert(SushiStaker.ZeroLiquidity.selector);
        staker.stake(tokenId);
        vm.stopPrank();
    }

    /**
     * @notice Test unstaking after staking via stake()
     */
    function test_UnstakeAfterStake() public {
        uint256 tokenId = _mintNFT(alice);

        // Stake
        vm.startPrank(alice);
        mockNFT.approve(address(staker), tokenId);
        staker.stake(tokenId);

        // Unstake
        staker.unstake(tokenId);
        vm.stopPrank();

        // Verify state
        assertEq(staker.isStaked(tokenId), false);
        assertEq(staker.getStaker(tokenId), address(0));
        assertEq(mockNFT.ownerOf(tokenId), alice);
    }
}
