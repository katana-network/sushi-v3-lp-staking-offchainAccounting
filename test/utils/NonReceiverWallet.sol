// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { SushiStaker } from "../../src/SushiStaker.sol";
import { IERC721 } from "@openzeppelin-contracts-5.5.0/token/ERC721/IERC721.sol";

/**
 * @title NonReceiverWallet
 * @notice A smart wallet that does NOT implement IERC721Receiver.
 *         Simulates a contract that received its NFT via _mint (not _safeMint),
 *         so it never needed onERC721Received. Used to test that unstake uses
 *         transferFrom instead of safeTransferFrom.
 */
contract NonReceiverWallet {
    SushiStaker public immutable staker;
    IERC721 public immutable nft;

    constructor(SushiStaker _staker, IERC721 _nft) {
        staker = _staker;
        nft = _nft;
    }

    function approveAndStake(uint256 tokenId) external {
        nft.approve(address(staker), tokenId);
        staker.stake(tokenId);
    }

    function unstake(uint256 tokenId) external {
        staker.unstake(tokenId);
    }
}
