// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { SushiStaker } from "../src/SushiStaker.sol";
import { SushiStakerTestBase } from "./utils/SushiStakerTestBase.sol";

/**
 * @title SetGaugeVoterTest
 * @notice Tests for the setGaugeVoter() function
 */
contract SetGaugeVoterTest is SushiStakerTestBase {
    /**
     * @notice Test owner can set a new gauge voter
     */
    function test_setGaugeVoter() public {
        address newGaugeVoter = makeAddr("newGaugeVoter");

        vm.prank(owner);
        vm.expectEmit();
        emit SushiStaker.GaugeVoterUpdated(address(mockGaugeVoter), newGaugeVoter);

        staker.setGaugeVoter(newGaugeVoter);

        assertEq(staker.getGaugeVoter(), newGaugeVoter);
    }

    /**
     * @notice Test revert when non-owner calls setGaugeVoter
     */
    function test_revertWhen_setGaugeVoterNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        staker.setGaugeVoter(makeAddr("newGaugeVoter"));
    }

    /**
     * @notice Test revert when setting gauge voter to zero address
     */
    function test_revertWhen_setGaugeVoterZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(SushiStaker.SushiStakerZeroAddress.selector);
        staker.setGaugeVoter(address(0));
    }
}
