// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {SushiStaker} from "../../src/SushiStaker.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {MockSushiNFT} from "./MockSushiNFT.sol";
import {MockFactory} from "./MockFactory.sol";
import {MockPool} from "./MockPool.sol";
import {MockERC20} from "./MockERC20.sol";
import {MockGaugeVoter} from "./MockGaugeVoter.sol";

/**
 * @title SushiStakerTestBase
 * @notice Base test contract with common setup for SushiStaker tests
 */
abstract contract SushiStakerTestBase is Test {
    SushiStaker public implementation;
    SushiStaker public staker;
    ProxyAdmin public proxyAdmin;
    TransparentUpgradeableProxy public proxy;
    MockSushiNFT public mockNFT;
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
    uint128 public constant LIQUIDITY = 1000000;

    function setUp() public virtual {
        // Deploy mocks
        mockNFT = new MockSushiNFT();
        mockFactory = new MockFactory();
        mockPool = new MockPool();
        mockGaugeVoter = new MockGaugeVoter();

        token0 = mockNFT.getToken0();
        token1 = mockNFT.getToken1();

        // Setup factory to return pool
        mockFactory.setPool(token0, token1, FEE, address(mockPool));

        // Deploy implementation
        implementation = new SushiStaker();

        // Deploy ProxyAdmin
        proxyAdmin = new ProxyAdmin(owner);

        // Encode initialization data
        bytes memory initData = abi.encodeWithSelector(
            SushiStaker.initialize.selector, address(mockNFT), address(mockFactory), feeCollector, address(mockGaugeVoter), owner
        );

        // Deploy proxy
        proxy = new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), initData);

        // Get staker instance
        staker = SushiStaker(address(proxy));
    }

    /**
     * @dev Helper function to mint an NFT position
     */
    function _mintNFT(address to, uint128 liquidity) internal returns (uint256) {
        return mockNFT.mint(to, token0, token1, FEE, TICK_LOWER, TICK_UPPER, liquidity);
    }

    /**
     * @dev Helper function to mint an NFT position with default liquidity
     */
    function _mintNFT(address to) internal returns (uint256) {
        return _mintNFT(to, LIQUIDITY);
    }
}
