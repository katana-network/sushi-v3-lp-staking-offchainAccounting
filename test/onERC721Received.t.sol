// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { SushiStaker } from "../src/SushiStaker.sol";
import { MockERC20 } from "./utils/MockERC20.sol";
import { SushiStakerTestBase } from "./utils/SushiStakerTestBase.sol";
import { ERC721 } from "@openzeppelin-contracts-5.5.0/token/ERC721/ERC721.sol";

/**
 * @title MockotherNft
 * @notice A different NFT contract for testing InvalidNFTContract revert
 */
contract MockotherNft is ERC721 {
    uint256 private _tokenIdCounter;

    constructor() ERC721("Other NFT", "OTHER") { }

    function mint(address to) external returns (uint256) {
        uint256 tokenId = _tokenIdCounter++;
        _mint(to, tokenId);
        return tokenId;
    }
}

/**
 * @title OnERC721ReceivedTest
 * @notice Tests for the onERC721Received() auto-staking functionality
 */
contract OnERC721ReceivedTest is SushiStakerTestBase {
    /**
     * @notice Test NFT sent via safeTransferFrom is automatically staked
     */
    function test_DirectTransferAutoStakes() public {
        uint256 tokenId = _mintNft(alice);

        // Alice sends NFT directly to staker via safeTransferFrom
        vm.prank(alice);
        mockNft.safeTransferFrom(alice, address(staker), tokenId);

        // Verify staking state
        assertEq(staker.isStaked(tokenId), true);
        assertEq(staker.getStaker(tokenId), alice);
        assertEq(staker.getStakeTimestamp(tokenId), block.timestamp);
        assertEq(mockNft.ownerOf(tokenId), address(staker));
    }

    /**
     * @notice Test TokenStaked event is emitted on direct transfer
     */
    function test_DirectTransferEmitsEvent() public {
        uint256 tokenId = _mintNft(alice);

        vm.expectEmit(true, true, false, true);
        emit SushiStaker.TokenStaked(
            alice,
            tokenId,
            address(mockPool),
            TICK_LOWER,
            TICK_UPPER,
            LIQUIDITY,
            1_000_000, // mockSecondsPerLiquidity
            block.timestamp
        );

        vm.prank(alice);
        mockNft.safeTransferFrom(alice, address(staker), tokenId);
    }

    /**
     * @notice Test pre-stake fees are collected and sent to sender on direct transfer
     */
    function test_DirectTransferCollectsFees() public {
        uint256 tokenId = _mintNft(alice);

        // Add pending fees
        uint256 preFee0 = 100 ether;
        uint256 preFee1 = 50 ether;
        mockNft.addPendingFees(tokenId, preFee0, preFee1);

        uint256 aliceBalance0Before = MockERC20(token0).balanceOf(alice);
        uint256 aliceBalance1Before = MockERC20(token1).balanceOf(alice);

        // Direct transfer
        vm.prank(alice);
        mockNft.safeTransferFrom(alice, address(staker), tokenId);

        // Verify alice received fees
        assertEq(MockERC20(token0).balanceOf(alice), aliceBalance0Before + preFee0);
        assertEq(MockERC20(token1).balanceOf(alice), aliceBalance1Before + preFee1);
    }

    /**
     * @notice Test revert when position has zero liquidity on direct transfer
     */
    function test_DirectTransferRevertsZeroLiquidity() public {
        uint256 tokenId = _mintNft(alice, 0);

        vm.prank(alice);
        vm.expectRevert(SushiStaker.ZeroLiquidity.selector);
        mockNft.safeTransferFrom(alice, address(staker), tokenId);
    }

    /**
     * @notice Test revert when NFT is from wrong contract
     */
    function test_DirectTransferRevertsWrongNFT() public {
        MockotherNft otherNft = new MockotherNft();
        uint256 tokenId = otherNft.mint(alice);

        vm.prank(alice);
        vm.expectRevert(SushiStaker.InvalidNFTContract.selector);
        otherNft.safeTransferFrom(alice, address(staker), tokenId);
    }

    /**
     * @notice Test revert when from is address(0) (prevents minting to contract)
     * @dev This is a hypothetical case since ERC721 doesn't normally allow minting
     *      with a transfer-like callback where from=0, but we test the guard anyway
     */
    function test_DirectTransferRevertsFromZeroAddress() public {
        // This test verifies the guard exists, though in practice this case
        // is hard to trigger since minting doesn't go through safeTransferFrom
        // We test by calling onERC721Received directly (simulating a malicious call)

        uint256 tokenId = _mintNft(alice);

        // Simulate a call from the NFT contract with from=address(0)
        vm.prank(address(mockNft));
        vm.expectRevert(SushiStaker.ZeroAddress.selector);
        staker.onERC721Received(address(0), address(0), tokenId, "");
    }

    /**
     * @notice Test unstaking after staking via direct transfer
     */
    function test_UnstakeAfterDirectTransfer() public {
        uint256 tokenId = _mintNft(alice);

        // Stake via direct transfer
        vm.prank(alice);
        mockNft.safeTransferFrom(alice, address(staker), tokenId);

        // Verify staked
        assertEq(staker.isStaked(tokenId), true);
        assertEq(staker.getStaker(tokenId), alice);

        // Unstake
        vm.prank(alice);
        staker.unstake(tokenId);

        // Verify unstaked
        assertEq(staker.isStaked(tokenId), false);
        assertEq(staker.getStaker(tokenId), address(0));
        assertEq(mockNft.ownerOf(tokenId), alice);
    }

    /**
     * @notice Test that stake() and direct transfer produce equivalent results
     */
    function test_StakeAndDirectTransferEquivalent() public {
        uint256 tokenId1 = _mintNft(alice);
        uint256 tokenId2 = _mintNft(bob);

        // Alice stakes via stake()
        vm.startPrank(alice);
        mockNft.approve(address(staker), tokenId1);
        staker.stake(tokenId1);
        vm.stopPrank();

        // Bob stakes via direct transfer
        vm.prank(bob);
        mockNft.safeTransferFrom(bob, address(staker), tokenId2);

        // Both should have same state structure
        assertEq(staker.isStaked(tokenId1), staker.isStaked(tokenId2));
        assertEq(staker.getStaker(tokenId1), alice);
        assertEq(staker.getStaker(tokenId2), bob);
        assertEq(mockNft.ownerOf(tokenId1), address(staker));
        assertEq(mockNft.ownerOf(tokenId2), address(staker));
    }

    /**
     * @notice Test that fees go to the correct recipient in both staking methods
     */
    function test_FeesGoToCorrectRecipient() public {
        uint256 tokenId1 = _mintNft(alice);
        uint256 tokenId2 = _mintNft(bob);

        // Add pre-stake fees to both
        mockNft.addPendingFees(tokenId1, 100 ether, 50 ether);
        mockNft.addPendingFees(tokenId2, 200 ether, 100 ether);

        uint256 aliceBalance0Before = MockERC20(token0).balanceOf(alice);
        uint256 bobBalance0Before = MockERC20(token0).balanceOf(bob);

        // Alice stakes via stake()
        vm.startPrank(alice);
        mockNft.approve(address(staker), tokenId1);
        staker.stake(tokenId1);
        vm.stopPrank();

        // Bob stakes via direct transfer
        vm.prank(bob);
        mockNft.safeTransferFrom(bob, address(staker), tokenId2);

        // Each should receive their own fees
        assertEq(MockERC20(token0).balanceOf(alice), aliceBalance0Before + 100 ether);
        assertEq(MockERC20(token0).balanceOf(bob), bobBalance0Before + 200 ether);
    }
}
