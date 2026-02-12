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
     * @notice Test that sending an NFT to staker during unstake callback properly stakes it
     * @dev Regression test: a previous implementation silently accepted NFTs during unstake
     *      without creating staking records, leaving them stuck. Now onERC721Received always
     *      calls _stakeInternal, so the new NFT is properly staked.
     */
    function test_sendNftDuringUnstakeCallbackStakesProperly() public {
        ReentrancyAttacker attacker = new ReentrancyAttacker(staker, mockNft);

        // Mint two NFTs to the attacker contract
        uint256 stakedTokenId = _mintNft(address(attacker));
        uint256 newTokenId = _mintNft(address(attacker));

        // Stake the first NFT
        attacker.stakeToken(stakedTokenId);
        assertEq(staker.isStaked(stakedTokenId), true);

        // Unstake — callback sends the second NFT to staker during unstake
        attacker.unstakeWithAttack(stakedTokenId, newTokenId);

        // The unstaked NFT should be fully unstaked
        assertEq(staker.isStaked(stakedTokenId), false);
        assertEq(staker.getStaker(stakedTokenId), address(0));
        assertEq(mockNft.ownerOf(stakedTokenId), address(attacker));

        // The new NFT sent during the callback should be properly staked
        assertEq(staker.isStaked(newTokenId), true);
        assertEq(staker.getStaker(newTokenId), address(attacker));
        assertEq(mockNft.ownerOf(newTokenId), address(staker));
    }
}
