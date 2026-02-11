// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { SushiStaker } from "../src/SushiStaker.sol";
import { MockERC20 } from "./utils/MockERC20.sol";
import { SushiStakerTestBase } from "./utils/SushiStakerTestBase.sol";
import { ProxyAdmin } from "@openzeppelin-contracts-5.5.0/proxy/transparent/ProxyAdmin.sol";
import {
    TransparentUpgradeableProxy
} from "@openzeppelin-contracts-5.5.0/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @title SushiStakerTest
 * @notice Test suite for SushiStaker contract
 */
contract SushiStakerTest is SushiStakerTestBase {
    // =============================================================
    //                     EIP-7201 STORAGE TESTS
    // =============================================================

    function test_EIP7201StorageLocation() public pure {
        // Calculate expected storage location per EIP-7201
        // Formula: keccak256(abi.encode(uint256(keccak256("sushistaker.storage.main")) - 1)) & ~bytes32(uint256(0xff))

        bytes32 namespaceHash = keccak256("sushistaker.storage.main");
        uint256 intermediate = uint256(namespaceHash) - 1;
        bytes32 encodedHash = keccak256(abi.encode(intermediate));
        bytes32 expected = encodedHash & ~bytes32(uint256(0xff));

        bytes32 actual = bytes32(uint256(0xb440148b1c334507c0052c0f23ea4ea76d9ce3c5acb0c2d6dee0a0b55e066300));

        assertEq(actual, expected, "Storage location does not match EIP-7201 calculation");
    }

    // =============================================================
    //                     INITIALIZATION TESTS
    // =============================================================

    function test_Initialize() public view {
        assertEq(staker.sushiNft(), address(mockNft));
        assertEq(staker.factory(), address(mockFactory));
        assertEq(staker.feeCollector(), feeCollector);
        assertEq(staker.getGaugeVoter(), address(mockGaugeVoter));
        assertEq(staker.owner(), owner);
    }

    function test_RevertWhen_InitializeWithZeroFeeCollector() public {
        SushiStaker newImpl = new SushiStaker();
        ProxyAdmin newAdmin = new ProxyAdmin(owner);

        bytes memory initData = abi.encodeWithSelector(
            SushiStaker.initialize.selector,
            address(mockNft),
            address(mockFactory),
            address(0),
            address(mockGaugeVoter),
            owner
        );

        vm.expectRevert(SushiStaker.ZeroAddress.selector);
        new TransparentUpgradeableProxy(address(newImpl), address(newAdmin), initData);
    }

    function test_RevertWhen_InitializeWithZeroGaugeVoter() public {
        SushiStaker newImpl = new SushiStaker();
        ProxyAdmin newAdmin = new ProxyAdmin(owner);

        bytes memory initData = abi.encodeWithSelector(
            SushiStaker.initialize.selector, address(mockNft), address(mockFactory), feeCollector, address(0), owner
        );

        vm.expectRevert(SushiStaker.ZeroAddress.selector);
        new TransparentUpgradeableProxy(address(newImpl), address(newAdmin), initData);
    }

    // =============================================================
    //                   FEE COLLECTION TESTS
    // =============================================================

    function test_StakeWithExistingFees() public {
        // Mint NFT to alice
        uint256 tokenId = mockNft.mint(alice, token0, token1, FEE, TICK_LOWER, TICK_UPPER, LIQUIDITY);

        // Add pending fees before staking
        uint256 preFee0 = 100 ether;
        uint256 preFee1 = 50 ether;
        mockNft.addPendingFees(tokenId, preFee0, preFee1);

        uint256 aliceBalance0Before = MockERC20(token0).balanceOf(alice);
        uint256 aliceBalance1Before = MockERC20(token1).balanceOf(alice);

        // Alice stakes (fees should be collected and sent to her)
        vm.startPrank(alice);
        mockNft.approve(address(staker), tokenId);
        staker.stake(tokenId);
        vm.stopPrank();

        // Verify alice received the pre-stake fees
        assertEq(MockERC20(token0).balanceOf(alice), aliceBalance0Before + preFee0);
        assertEq(MockERC20(token1).balanceOf(alice), aliceBalance1Before + preFee1);

        // Verify token is staked
        assertEq(staker.isStaked(tokenId), true);
        assertEq(staker.getStaker(tokenId), alice);
    }

    function test_UnstakeWithAccumulatedFees() public {
        // Mint and stake NFT
        uint256 tokenId = mockNft.mint(alice, token0, token1, FEE, TICK_LOWER, TICK_UPPER, LIQUIDITY);

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

    function test_CollectFeesMultiple() public {
        // Stake multiple positions
        uint256 tokenId1 = mockNft.mint(alice, token0, token1, FEE, TICK_LOWER, TICK_UPPER, LIQUIDITY);
        uint256 tokenId2 = mockNft.mint(alice, token0, token1, FEE, TICK_LOWER, TICK_UPPER, LIQUIDITY);
        uint256 tokenId3 = mockNft.mint(bob, token0, token1, FEE, TICK_LOWER, TICK_UPPER, LIQUIDITY);

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

    function test_CollectFeesMultipleSkipsUnstakedTokens() public {
        // Stake one position
        uint256 tokenId1 = mockNft.mint(alice, token0, token1, FEE, TICK_LOWER, TICK_UPPER, LIQUIDITY);
        uint256 tokenId2 = mockNft.mint(bob, token0, token1, FEE, TICK_LOWER, TICK_UPPER, LIQUIDITY); // Not staked

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

    function test_FeesCollectedEvent() public {
        uint256 tokenId = mockNft.mint(alice, token0, token1, FEE, TICK_LOWER, TICK_UPPER, LIQUIDITY);

        mockNft.addPendingFees(tokenId, 100 ether, 50 ether);

        vm.startPrank(alice);
        mockNft.approve(address(staker), tokenId);

        // Expect FeesCollected event on stake (epochId = 1 from mock)
        vm.expectEmit();
        emit SushiStaker.FeesCollected(tokenId, alice, 1, address(mockPool), token0, token1, 100 ether, 50 ether);

        staker.stake(tokenId);
        vm.stopPrank();
    }

    // =============================================================
    //                       ADMIN TESTS
    // =============================================================

    function test_SetFeeCollector() public {
        address newFeeCollector = makeAddr("newFeeCollector");

        vm.prank(owner);
        vm.expectEmit();
        emit SushiStaker.FeeCollectorUpdated(feeCollector, newFeeCollector);

        staker.setFeeCollector(newFeeCollector);

        assertEq(staker.feeCollector(), newFeeCollector);
    }

    function test_RevertWhen_SetFeeCollectorNotOwner() public {
        address newFeeCollector = makeAddr("newFeeCollector");

        vm.prank(alice);
        vm.expectRevert();
        staker.setFeeCollector(newFeeCollector);
    }

    function test_RevertWhen_SetFeeCollectorZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(SushiStaker.ZeroAddress.selector);
        staker.setFeeCollector(address(0));
    }

    function test_SetGaugeVoter() public {
        address newGaugeVoter = makeAddr("newGaugeVoter");

        vm.prank(owner);
        vm.expectEmit();
        emit SushiStaker.GaugeVoterUpdated(address(mockGaugeVoter), newGaugeVoter);

        staker.setGaugeVoter(newGaugeVoter);

        assertEq(staker.getGaugeVoter(), newGaugeVoter);
    }

    function test_RevertWhen_SetGaugeVoterNotOwner() public {
        address newGaugeVoter = makeAddr("newGaugeVoter");

        vm.prank(alice);
        vm.expectRevert();
        staker.setGaugeVoter(newGaugeVoter);
    }

    function test_RevertWhen_SetGaugeVoterZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(SushiStaker.ZeroAddress.selector);
        staker.setGaugeVoter(address(0));
    }

    // =============================================================
    //                    FEE STATS TESTS
    // =============================================================

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

    function test_CollectFeesMultipleStats_SingleStakedToken() public {
        uint256 tokenId = mockNft.mint(alice, token0, token1, FEE, TICK_LOWER, TICK_UPPER, LIQUIDITY);

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

    function test_CollectFeesMultipleStats_MixedStakedAndUnstaked() public {
        uint256 tokenId1 = mockNft.mint(alice, token0, token1, FEE, TICK_LOWER, TICK_UPPER, LIQUIDITY);
        uint256 tokenId2 = mockNft.mint(alice, token0, token1, FEE, TICK_LOWER, TICK_UPPER, LIQUIDITY);
        uint256 tokenId3 = mockNft.mint(bob, token0, token1, FEE, TICK_LOWER, TICK_UPPER, LIQUIDITY);

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

    function test_CollectFeesMultipleStats_AllUnstaked() public {
        uint256 tokenId1 = mockNft.mint(alice, token0, token1, FEE, TICK_LOWER, TICK_UPPER, LIQUIDITY);
        uint256 tokenId2 = mockNft.mint(bob, token0, token1, FEE, TICK_LOWER, TICK_UPPER, LIQUIDITY);

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

    function test_CollectFeesMultipleStats_NoFees() public {
        uint256 tokenId1 = mockNft.mint(alice, token0, token1, FEE, TICK_LOWER, TICK_UPPER, LIQUIDITY);
        uint256 tokenId2 = mockNft.mint(bob, token0, token1, FEE, TICK_LOWER, TICK_UPPER, LIQUIDITY);

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

    // =============================================================
    //                    EXISTING TESTS (UPDATED)
    // =============================================================

    function test_Stake() public {
        uint256 tokenId = mockNft.mint(alice, token0, token1, FEE, TICK_LOWER, TICK_UPPER, LIQUIDITY);

        vm.startPrank(alice);
        mockNft.approve(address(staker), tokenId);

        vm.expectEmit();
        emit SushiStaker.TokenStaked(
            alice, tokenId, address(mockPool), TICK_LOWER, TICK_UPPER, LIQUIDITY, 1_000_000, block.timestamp
        );

        staker.stake(tokenId);
        vm.stopPrank();

        assertEq(staker.getStaker(tokenId), alice);
        assertEq(staker.getStakeTimestamp(tokenId), block.timestamp);
        assertEq(staker.isStaked(tokenId), true);
        assertEq(mockNft.ownerOf(tokenId), address(staker));
    }

    function test_Unstake() public {
        uint256 tokenId = mockNft.mint(alice, token0, token1, FEE, TICK_LOWER, TICK_UPPER, LIQUIDITY);

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

    function test_RevertWhen_StakeZeroLiquidity() public {
        uint256 tokenId = mockNft.mint(alice, token0, token1, FEE, TICK_LOWER, TICK_UPPER, 0);

        vm.startPrank(alice);
        mockNft.approve(address(staker), tokenId);

        vm.expectRevert(SushiStaker.ZeroLiquidity.selector);
        staker.stake(tokenId);
        vm.stopPrank();
    }

    function test_RevertWhen_UnstakeNotStaker() public {
        uint256 tokenId = mockNft.mint(alice, token0, token1, FEE, TICK_LOWER, TICK_UPPER, LIQUIDITY);

        vm.startPrank(alice);
        mockNft.approve(address(staker), tokenId);
        staker.stake(tokenId);
        vm.stopPrank();

        // Bob tries to unstake Alice's token
        vm.prank(bob);
        vm.expectRevert(SushiStaker.NotTokenStaker.selector);
        staker.unstake(tokenId);
    }

    function test_RevertWhen_UnstakeNotStaked() public {
        uint256 tokenId = mockNft.mint(alice, token0, token1, FEE, TICK_LOWER, TICK_UPPER, LIQUIDITY);

        // Alice tries to unstake a token that was never staked
        vm.prank(alice);
        vm.expectRevert(SushiStaker.TokenNotStaked.selector);
        staker.unstake(tokenId);
    }
}
