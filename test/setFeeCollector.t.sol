// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { SushiStaker } from "../src/SushiStaker.sol";
import { SushiStakerTestBase } from "./utils/SushiStakerTestBase.sol";

/**
 * @title SetFeeCollectorTest
 * @notice Tests for the setFeeCollector() function
 */
contract SetFeeCollectorTest is SushiStakerTestBase {
    /**
     * @notice Test owner can set a new fee collector
     */
    function test_setFeeCollector() public {
        address newFeeCollector = makeAddr("newFeeCollector");

        vm.prank(owner);
        vm.expectEmit();
        emit SushiStaker.FeeCollectorUpdated(feeCollector, newFeeCollector);

        staker.setFeeCollector(newFeeCollector);

        assertEq(staker.feeCollector(), newFeeCollector);
    }

    /**
     * @notice Test revert when non-owner calls setFeeCollector
     */
    function test_revertWhen_setFeeCollectorNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        staker.setFeeCollector(makeAddr("newFeeCollector"));
    }

    /**
     * @notice Test revert when setting fee collector to zero address
     */
    function test_revertWhen_setFeeCollectorZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(SushiStaker.SushiStakerZeroAddress.selector);
        staker.setFeeCollector(address(0));
    }
}
