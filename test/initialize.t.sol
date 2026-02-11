// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { SushiStaker } from "../src/SushiStaker.sol";
import { SushiStakerTestBase } from "./utils/SushiStakerTestBase.sol";
import { ProxyAdmin } from "@openzeppelin-contracts-5.5.0/proxy/transparent/ProxyAdmin.sol";
import {
    TransparentUpgradeableProxy
} from "@openzeppelin-contracts-5.5.0/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @title InitializeTest
 * @notice Tests for initialization and EIP-7201 storage layout
 */
contract InitializeTest is SushiStakerTestBase {
    /**
     * @notice Verify EIP-7201 namespaced storage location
     */
    function test_eip7201StorageLocation() public pure {
        bytes32 namespaceHash = keccak256("sushistaker.storage.main");
        uint256 intermediate = uint256(namespaceHash) - 1;
        bytes32 encodedHash = keccak256(abi.encode(intermediate));
        bytes32 expected = encodedHash & ~bytes32(uint256(0xff));

        bytes32 actual = bytes32(uint256(0xb440148b1c334507c0052c0f23ea4ea76d9ce3c5acb0c2d6dee0a0b55e066300));

        assertEq(actual, expected, "Storage location does not match EIP-7201 calculation");
    }

    /**
     * @notice Test all state is correctly set after initialization
     */
    function test_initializeSuccess() public view {
        assertEq(staker.sushiNft(), address(mockNft));
        assertEq(staker.factory(), address(mockFactory));
        assertEq(staker.feeCollector(), feeCollector);
        assertEq(staker.getGaugeVoter(), address(mockGaugeVoter));
        assertEq(staker.owner(), owner);
    }

    /**
     * @notice Test revert when feeCollector is zero address
     */
    function test_revertWhen_initializeZeroFeeCollector() public {
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

    /**
     * @notice Test revert when gaugeVoter is zero address
     */
    function test_revertWhen_initializeZeroGaugeVoter() public {
        SushiStaker newImpl = new SushiStaker();
        ProxyAdmin newAdmin = new ProxyAdmin(owner);

        bytes memory initData = abi.encodeWithSelector(
            SushiStaker.initialize.selector, address(mockNft), address(mockFactory), feeCollector, address(0), owner
        );

        vm.expectRevert(SushiStaker.SushiStakerZeroAddress.selector);
        new TransparentUpgradeableProxy(address(newImpl), address(newAdmin), initData);
    }
}
