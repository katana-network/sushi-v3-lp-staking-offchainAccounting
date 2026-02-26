// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { SushiStaker } from "../src/SushiStaker.sol";
import { MockERC20 } from "./utils/MockERC20.sol";
import { NonReceiverWallet } from "./utils/NonReceiverWallet.sol";
import { ReentrancyAttacker } from "./utils/ReentrancyAttacker.sol";
import { SushiStakerTestBase } from "./utils/SushiStakerTestBase.sol";
import { IERC721 } from "@openzeppelin-contracts-5.5.0/token/ERC721/IERC721.sol";

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
     * @notice Test that unstake uses transferFrom (not safeTransferFrom), so
     *         onERC721Received is never called on the recipient during unstake.
     * @dev The ReentrancyAttacker sets shouldAttack=true before calling unstake.
     *      If onERC721Received were triggered, shouldAttack would be flipped to false
     *      and the attacker would send a second NFT. With transferFrom, the callback
     *      never fires, so shouldAttack remains true and the second NFT stays put.
     */
    function test_unstakeDoesNotTriggerERC721ReceiverHook() public {
        ReentrancyAttacker attacker = new ReentrancyAttacker(staker, mockNft);

        // Mint two NFTs to the attacker contract
        uint256 stakedTokenId = _mintNft(address(attacker));
        uint256 secondTokenId = _mintNft(address(attacker));

        // Stake the first NFT
        attacker.stakeToken(stakedTokenId);
        assertEq(staker.isStaked(stakedTokenId), true);

        // Unstake — attacker arms the callback, but transferFrom won't trigger it
        attacker.unstakeWithAttack(stakedTokenId, secondTokenId);

        // The unstaked NFT should be fully returned
        assertEq(staker.isStaked(stakedTokenId), false);
        assertEq(staker.getStaker(stakedTokenId), address(0));
        assertEq(mockNft.ownerOf(stakedTokenId), address(attacker));

        // The callback never fired, so shouldAttack was never flipped
        assertEq(attacker.shouldAttack(), true);

        // The second NFT was never sent to the staker
        assertEq(staker.isStaked(secondTokenId), false);
        assertEq(mockNft.ownerOf(secondTokenId), address(attacker));
    }

    /**
     * @notice Test that a contract without IERC721Receiver can unstake successfully.
     * @dev A smart wallet that received its NFT via _mint (not _safeMint) doesn't implement
     *      onERC721Received. Using safeTransferFrom in unstake would permanently lock the NFT.
     *      With transferFrom, unstake succeeds regardless.
     */
    function test_unstakeSucceedsForContractWithoutERC721Receiver() public {
        NonReceiverWallet wallet = new NonReceiverWallet(staker, IERC721(address(mockNft)));

        // Mint NFT directly to the wallet (via _mint, not _safeMint)
        uint256 tokenId = _mintNft(address(wallet));
        assertEq(mockNft.ownerOf(tokenId), address(wallet));

        // Stake via the wallet — safeTransferFrom to SushiStaker works (staker implements IERC721Receiver)
        wallet.approveAndStake(tokenId);
        assertEq(staker.isStaked(tokenId), true);
        assertEq(staker.getStaker(tokenId), address(wallet));

        // Unstake — would revert with safeTransferFrom since wallet has no onERC721Received
        wallet.unstake(tokenId);

        // Verify successful unstake
        assertEq(staker.isStaked(tokenId), false);
        assertEq(staker.getStaker(tokenId), address(0));
        assertEq(mockNft.ownerOf(tokenId), address(wallet));
    }
}
