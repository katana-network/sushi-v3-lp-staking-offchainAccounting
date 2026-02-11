// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { MockERC20 } from "./MockERC20.sol";
import { ERC721 } from "@openzeppelin-contracts-5.5.0/token/ERC721/ERC721.sol";

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
