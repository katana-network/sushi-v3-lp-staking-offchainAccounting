// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { SushiStaker } from "../src/SushiStaker.sol";
import { MockERC20 } from "./utils/MockERC20.sol";
import { ReentrancyAttacker } from "./utils/ReentrancyAttacker.sol";
import { SushiStakerTestBase } from "./utils/SushiStakerTestBase.sol";

/**
 * @title UnstakeTest
 * @notice Tests for the unstake() function
 */
contract UnstakeTest is SushiStakerTestBase {
    /**
     * @notice Test successful unstaking with event emission
     */
    function test_unstakeSuccess() public {
        uint256 tokenId = _mintNft(alice);

        vm.startPrank(alice);
        mockNft.approve(address(staker), tokenId);
        staker.stake(tokenId);

        mockPool.setMockSecondsPerLiquidity(2_000_000);

        vm.expectEmit();
        emit SushiStaker.TokenUnstaked(
            alice, tokenId, address(mockPool), TICK_LOWER, TICK_UPPER, LIQUIDITY, 2_000_000, block.timestamp
        );

        staker.unstake(tokenId);
        vm.stopPrank();

        assertEq(staker.getStaker(tokenId), address(0));
        assertEq(staker.isStaked(tokenId), false);
        assertEq(mockNft.ownerOf(tokenId), alice);
    }

    /**
     * @notice Test accumulated fees go to feeCollector on unstake
     */
    function test_unstakeCollectsFeesToFeeCollector() public {
        uint256 tokenId = _mintNft(alice);

        vm.startPrank(alice);
        mockNft.approve(address(staker), tokenId);
        staker.stake(tokenId);
        vm.stopPrank();

        // Simulate fee accumulation while staked
        uint256 stakedFee0 = 200 ether;
        uint256 stakedFee1 = 100 ether;
        mockNft.addPendingFees(tokenId, stakedFee0, stakedFee1);

        uint256 feeCollectorBalance0Before = MockERC20(token0).balanceOf(feeCollector);
        uint256 feeCollectorBalance1Before = MockERC20(token1).balanceOf(feeCollector);

        // Alice unstakes (fees should go to feeCollector)
        vm.prank(alice);
        staker.unstake(tokenId);

        // Verify feeCollector received the staked fees
        assertEq(MockERC20(token0).balanceOf(feeCollector), feeCollectorBalance0Before + stakedFee0);
        assertEq(MockERC20(token1).balanceOf(feeCollector), feeCollectorBalance1Before + stakedFee1);

        // Verify alice got her NFT back
        assertEq(mockNft.ownerOf(tokenId), alice);
    }

    /**
     * @notice Test revert when non-staker tries to unstake
     */
    function test_revertWhen_unstakeNotStaker() public {
        uint256 tokenId = _mintNft(alice);

        vm.startPrank(alice);
        mockNft.approve(address(staker), tokenId);
        staker.stake(tokenId);
        vm.stopPrank();

        // Bob tries to unstake Alice's token
        vm.prank(bob);
        vm.expectRevert(SushiStaker.SushiStakerNotTokenStaker.selector);
        staker.unstake(tokenId);
    }

    /**
     * @notice Test revert when unstaking a token that was never staked
     */
    function test_revertWhen_unstakeTokenNotStaked() public {
        uint256 tokenId = _mintNft(alice);

        vm.prank(alice);
        vm.expectRevert(SushiStaker.SushiStakerTokenNotStaked.selector);
        staker.unstake(tokenId);
    }

    /**
     * @notice Test that sending an NFT to staker during unstake callback reverts
     * @dev Regression test: without the _staking flag fix, onERC721Received would
     *      silently accept NFTs during unstake (reentrancy guard entered), leaving
     *      them stuck in the contract with no staking record.
     */
    function test_revertWhen_reentrancySendNftDuringUnstake() public {
        ReentrancyAttacker attacker = new ReentrancyAttacker(staker, mockNft);

        // Mint two NFTs to the attacker contract
        uint256 stakedTokenId = _mintNft(address(attacker));
        uint256 attackTokenId = _mintNft(address(attacker));

        // Attacker stakes the first NFT
        attacker.stakeToken(stakedTokenId);
        assertEq(staker.isStaked(stakedTokenId), true);

        // Attacker unstakes — callback tries to send the second NFT to staker
        // This should revert because onERC721Received rejects transfers during reentrancy
        vm.expectRevert(SushiStaker.SushiStakerInvalidNFTContract.selector);
        attacker.unstakeWithAttack(stakedTokenId, attackTokenId);
    }
}
