// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { SushiStaker } from "../../src/SushiStaker.sol";
import { MockFactory } from "./MockFactory.sol";
import { MockGaugeVoter } from "./MockGaugeVoter.sol";
import { MockPool } from "./MockPool.sol";
import { MockSushiNft } from "./MockSushiNft.sol";
import { ProxyAdmin } from "@openzeppelin-contracts-5.5.0/proxy/transparent/ProxyAdmin.sol";
import {
    TransparentUpgradeableProxy
} from "@openzeppelin-contracts-5.5.0/proxy/transparent/TransparentUpgradeableProxy.sol";
import { Test } from "forge-std/Test.sol";

/**
 * @title SushiStakerTestBase
 * @notice Base test contract with common setup for SushiStaker tests
 */
abstract contract SushiStakerTestBase is Test {
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

    function setUp() public virtual {
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

    /**
     * @dev Helper function to mint an NFT position
     */
    function _mintNft(address to, uint128 liquidity) internal returns (uint256) {
        return mockNft.mint(to, token0, token1, FEE, TICK_LOWER, TICK_UPPER, liquidity);
    }

    /**
     * @dev Helper function to mint an NFT position with default liquidity
     */
    function _mintNft(address to) internal returns (uint256) {
        return _mintNft(to, LIQUIDITY);
    }
}
