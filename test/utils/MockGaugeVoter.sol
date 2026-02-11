// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/**
 * @title MockGaugeVoter
 * @notice Mock GaugeVoter for testing
 */
contract MockGaugeVoter {
    uint256 public epochId = 1;

    function setEpochId(uint256 _epochId) external {
        epochId = _epochId;
    }
}
