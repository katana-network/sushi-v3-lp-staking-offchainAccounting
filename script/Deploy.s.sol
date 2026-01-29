// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {SushiStaker} from "../src/SushiStaker.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @title DeploySushiStaker
 * @notice Deployment script for SushiStaker with TransparentUpgradeableProxy
 * @dev Run with: forge script script/Deploy.s.sol:DeploySushiStaker --rpc-url $RPC_URL --broadcast --verify
 */
contract DeploySushiStaker is Script {
    function run() external {
        // Load environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address sushiNFT = vm.envAddress("SUSHI_NFT_CONTRACT");
        address factory = vm.envAddress("FACTORY_CONTRACT");
        address feeCollector = vm.envAddress("FEE_COLLECTOR");
        address owner = vm.envAddress("OWNER_ADDRESS");

        console.log("Deploying SushiStaker...");
        console.log("SushiSwap NFT Contract:", sushiNFT);
        console.log("Factory Contract:", factory);
        console.log("Fee Collector:", feeCollector);
        console.log("Owner:", owner);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the implementation contract
        SushiStaker implementation = new SushiStaker();
        console.log("Implementation deployed at:", address(implementation));

        // Deploy ProxyAdmin
        ProxyAdmin proxyAdmin = new ProxyAdmin(owner);
        console.log("ProxyAdmin deployed at:", address(proxyAdmin));

        // Encode initialization data
        bytes memory initData = abi.encodeWithSelector(
            SushiStaker.initialize.selector,
            sushiNFT,
            factory,
            feeCollector,
            owner
        );

        // Deploy TransparentUpgradeableProxy
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            initData
        );
        console.log("Proxy deployed at:", address(proxy));

        vm.stopBroadcast();

        // Verify deployment
        SushiStaker staker = SushiStaker(address(proxy));
        console.log("Verified SushiSwap NFT:", staker.sushiNFT());
        console.log("Verified Factory:", staker.factory());
        console.log("Verified Fee Collector:", staker.feeCollector());

        console.log("\n=== Deployment Summary ===");
        console.log("Implementation:", address(implementation));
        console.log("ProxyAdmin:", address(proxyAdmin));
        console.log("Proxy (SushiStaker):", address(proxy));
    }
}

/**
 * @title UpgradeSushiStaker
 * @notice Upgrade script for SushiStaker
 * @dev Run with: forge script script/Deploy.s.sol:UpgradeSushiStaker --rpc-url $RPC_URL --broadcast --verify
 */
contract UpgradeSushiStaker is Script {
    function run() external {
        // Load environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address proxyAdminAddress = vm.envAddress("PROXY_ADMIN_ADDRESS");
        address proxyAddress = vm.envAddress("PROXY_ADDRESS");

        console.log("Upgrading SushiStaker...");
        console.log("Proxy:", proxyAddress);
        console.log("ProxyAdmin:", proxyAdminAddress);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy new implementation
        SushiStaker newImplementation = new SushiStaker();
        console.log("New implementation deployed at:", address(newImplementation));

        // Upgrade proxy to new implementation
        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddress);
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(proxyAddress),
            address(newImplementation),
            "" // No initialization data for upgrade
        );

        vm.stopBroadcast();

        console.log("\n=== Upgrade Summary ===");
        console.log("New Implementation:", address(newImplementation));
        console.log("Proxy:", proxyAddress);
    }
}
