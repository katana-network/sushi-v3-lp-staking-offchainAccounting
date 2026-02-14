// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { SushiStaker } from "../../src/SushiStaker.sol";
import { MockSushiNft } from "./MockSushiNft.sol";
import { IERC721Receiver } from "@openzeppelin-contracts-5.5.0/token/ERC721/IERC721Receiver.sol";

/**
 * @title ReentrancyAttacker
 * @notice Malicious contract that tries to send an NFT to SushiStaker during unstake callback
 */
contract ReentrancyAttacker is IERC721Receiver {
    SushiStaker public staker;
    MockSushiNft public nft;
    uint256 public attackTokenId;
    bool public shouldAttack;

    constructor(SushiStaker _staker, MockSushiNft _nft) {
        staker = _staker;
        nft = _nft;
    }

    function stakeToken(uint256 tokenId) external {
        nft.approve(address(staker), tokenId);
        staker.stake(tokenId);
    }

    function unstakeWithAttack(uint256 tokenId, uint256 _attackTokenId) external {
        attackTokenId = _attackTokenId;
        shouldAttack = true;
        staker.unstake(tokenId);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external override returns (bytes4) {
        if (shouldAttack) {
            shouldAttack = false;
            // Try to send another NFT to the staker during the unstake callback
            nft.safeTransferFrom(address(this), address(staker), attackTokenId);
        }
        return IERC721Receiver.onERC721Received.selector;
    }
}
