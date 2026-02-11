// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { SushiStaker } from "../src/SushiStaker.sol";
import { ProxyAdmin } from "@openzeppelin-contracts-5.5.0/proxy/transparent/ProxyAdmin.sol";
import {
    TransparentUpgradeableProxy
} from "@openzeppelin-contracts-5.5.0/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ERC20 } from "@openzeppelin-contracts-5.5.0/token/ERC20/ERC20.sol";
import { ERC721 } from "@openzeppelin-contracts-5.5.0/token/ERC721/ERC721.sol";
import { Test } from "forge-std/Test.sol";

/**
 * @title MockERC20
 * @notice Mock ERC20 for testing
 */
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title MockSushiNft
 * @notice Mock ERC721 with positions() and collect() for testing
 */
contract MockSushiNft is ERC721 {
    uint256 private _tokenIdCounter;

    struct Position {
        uint96 nonce;
        address operator;
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }

    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    mapping(uint256 => Position) public positions;
    mapping(uint256 => uint256) public pendingFees0;
    mapping(uint256 => uint256) public pendingFees1;

    MockERC20 public immutable MOCK_TOKEN_0;
    MockERC20 public immutable MOCK_TOKEN_1;

    constructor() ERC721("SushiSwap V3 Positions", "SUSHI-V3-POS") {
        MOCK_TOKEN_0 = new MockERC20("Token0", "TK0");
        MOCK_TOKEN_1 = new MockERC20("Token1", "TK1");
    }

    function mint(
        address to,
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) external returns (uint256) {
        uint256 tokenId = _tokenIdCounter++;
        _mint(to, tokenId);

        positions[tokenId] = Position({
            nonce: 0,
            operator: address(0),
            token0: token0,
            token1: token1,
            fee: fee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidity: liquidity,
            feeGrowthInside0LastX128: 0,
            feeGrowthInside1LastX128: 0,
            tokensOwed0: 0,
            tokensOwed1: 0
        });

        return tokenId;
    }

    function addPendingFees(uint256 tokenId, uint256 amount0, uint256 amount1) external {
        pendingFees0[tokenId] += amount0;
        pendingFees1[tokenId] += amount1;
    }

    function collect(CollectParams calldata params) external returns (uint256 amount0, uint256 amount1) {
        amount0 = pendingFees0[params.tokenId];
        amount1 = pendingFees1[params.tokenId];

        if (amount0 > params.amount0Max) amount0 = params.amount0Max;
        if (amount1 > params.amount1Max) amount1 = params.amount1Max;

        pendingFees0[params.tokenId] -= amount0;
        pendingFees1[params.tokenId] -= amount1;

        if (amount0 > 0) {
            MOCK_TOKEN_0.mint(params.recipient, amount0);
        }
        if (amount1 > 0) {
            MOCK_TOKEN_1.mint(params.recipient, amount1);
        }

        return (amount0, amount1);
    }

    function getToken0() external view returns (address) {
        return address(MOCK_TOKEN_0);
    }

    function getToken1() external view returns (address) {
        return address(MOCK_TOKEN_1);
    }
}

/**
 * @title MockFactory
 * @notice Mock factory for testing
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

/**
 * @title MockPool
 * @notice Mock pool for testing
 */
contract MockPool {
    uint160 public mockSecondsPerLiquidity = 1_000_000;

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

/**
 * @title MockGaugeVoter
 * @notice Mock gauge voter for testing
 */
contract MockGaugeVoter {
    uint256 public epochId = 1;

    function setEpochId(uint256 _epochId) external {
        epochId = _epochId;
    }
}

/**
 * @title SushiStakerTest
 * @notice Test suite for SushiStaker contract
 */
contract SushiStakerTest is Test {
    SushiStaker public implementation;
    SushiStaker public staker;
    ProxyAdmin public proxyAdmin;
    TransparentUpgradeableProxy public proxy;
    MockSushiNft public mockNft;
    MockFactory public mockFactory;
    MockPool public mockPool;
    MockGaugeVoter public mockGaugeVoter;

    address public owner = makeAddr("owner");
    address public feeCollector = makeAddr("feeCollector");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    address public token0;
    address public token1;
    uint24 public constant FEE = 3000;
    int24 public constant TICK_LOWER = -100;
    int24 public constant TICK_UPPER = 100;
    uint128 public constant LIQUIDITY = 1_000_000;

    function setUp() public {
        // Deploy mocks
        mockNft = new MockSushiNft();
        mockFactory = new MockFactory();
        mockPool = new MockPool();
        mockGaugeVoter = new MockGaugeVoter();

        token0 = mockNft.getToken0();
        token1 = mockNft.getToken1();

        // Setup factory to return pool
        mockFactory.setPool(token0, token1, FEE, address(mockPool));

        // Deploy implementation
        implementation = new SushiStaker();

        // Deploy ProxyAdmin
        proxyAdmin = new ProxyAdmin(owner);

        // Encode initialization data
        bytes memory initData = abi.encodeWithSelector(
            SushiStaker.initialize.selector,
            address(mockNft),
            address(mockFactory),
            feeCollector,
            address(mockGaugeVoter),
            owner
        );

        // Deploy proxy
        proxy = new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), initData);

        // Get staker instance
        staker = SushiStaker(address(proxy));
    }

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

        vm.expectRevert(SushiStaker.SushiStakerZeroAddress.selector);
        new TransparentUpgradeableProxy(address(newImpl), address(newAdmin), initData);
    }

    function test_RevertWhen_InitializeWithZeroGaugeVoter() public {
        SushiStaker newImpl = new SushiStaker();
        ProxyAdmin newAdmin = new ProxyAdmin(owner);

        bytes memory initData = abi.encodeWithSelector(
            SushiStaker.initialize.selector, address(mockNft), address(mockFactory), feeCollector, address(0), owner
        );

        vm.expectRevert(SushiStaker.SushiStakerZeroAddress.selector);
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
        vm.expectRevert(SushiStaker.SushiStakerZeroAddress.selector);
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

        vm.expectRevert(SushiStaker.SushiStakerZeroLiquidity.selector);
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
        vm.expectRevert(SushiStaker.SushiStakerNotTokenStaker.selector);
        staker.unstake(tokenId);
    }

    function test_RevertWhen_UnstakeNotStaked() public {
        uint256 tokenId = mockNft.mint(alice, token0, token1, FEE, TICK_LOWER, TICK_UPPER, LIQUIDITY);

        // Alice tries to unstake a token that was never staked
        vm.prank(alice);
        vm.expectRevert(SushiStaker.SushiStakerTokenNotStaked.selector);
        staker.unstake(tokenId);
    }
}
