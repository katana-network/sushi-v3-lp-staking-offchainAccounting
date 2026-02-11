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

    /// @notice Add pending fees directly to tokensOwed (simulates fee accrual)
    /// @dev In production, fees are calculated from pool state. This is a test helper.
    function addPendingFees(uint256 tokenId, uint256 amount0, uint256 amount1) external {
        Position storage position = positions[tokenId];

        // Ensure values fit in uint128 before casting
        require(amount0 <= type(uint128).max, "Amount0 overflow");
        require(amount1 <= type(uint128).max, "Amount1 overflow");

        // casting to 'uint128' is safe because we checked above
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 fee0 = uint128(amount0);
        // casting to 'uint128' is safe because we checked above
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 fee1 = uint128(amount1);

        // Check for overflow on addition
        require(position.tokensOwed0 <= type(uint128).max - fee0, "TokensOwed0 overflow");
        require(position.tokensOwed1 <= type(uint128).max - fee1, "TokensOwed1 overflow");

        position.tokensOwed0 += fee0;
        position.tokensOwed1 += fee1;
    }

    function collect(CollectParams calldata params) external returns (uint256 amount0, uint256 amount1) {
        Position storage position = positions[params.tokenId];

        // Determine how much to collect (min of requested and available)
        amount0 = params.amount0Max > position.tokensOwed0 ? position.tokensOwed0 : params.amount0Max;
        amount1 = params.amount1Max > position.tokensOwed1 ? position.tokensOwed1 : params.amount1Max;

        // casting to 'uint128' is safe because amount0/1 are capped by tokensOwed0/1 which are uint128
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 collect0 = uint128(amount0);
        // casting to 'uint128' is safe because amount1 is capped by tokensOwed1 which is uint128
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 collect1 = uint128(amount1);

        // Decrease tokensOwed by collected amount
        position.tokensOwed0 -= collect0;
        position.tokensOwed1 -= collect1;

        // Mint tokens to recipient (simulates transferring from pool)
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
