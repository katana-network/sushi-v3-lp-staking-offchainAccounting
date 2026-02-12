// SPDX-License-Identifier: MIT
pragma solidity =0.8.33;

import { IAddressGaugeVoter } from "./interfaces/IAddressGaugeVoter.sol";
import { INonfungiblePositionManager } from "./interfaces/INonfungiblePositionManager.sol";
import { Initializable } from "@openzeppelin-contracts-5.5.0/proxy/utils/Initializable.sol";
import { IERC721 } from "@openzeppelin-contracts-5.5.0/token/ERC721/IERC721.sol";
import { IERC721Receiver } from "@openzeppelin-contracts-5.5.0/token/ERC721/IERC721Receiver.sol";
import { ReentrancyGuard } from "@openzeppelin-contracts-5.5.0/utils/ReentrancyGuard.sol";
import { OwnableUpgradeable } from "@openzeppelin-contracts-upgradeable-5.5.0/access/OwnableUpgradeable.sol";
import { IUniswapV3Factory } from "@sushiswap-v3-core/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@sushiswap-v3-core/interfaces/IUniswapV3Pool.sol";

/**
 * @title SushiStaker
 * @notice A contract that allows users to stake their SushiSwap NFT positions
 * @dev Uses EIP-7201 namespaced storage for transparent proxy compatibility
 */
contract SushiStaker is Initializable, OwnableUpgradeable, ReentrancyGuard, IERC721Receiver {
    // =============================================================
    //                          ERRORS
    // =============================================================

    /// @notice Thrown when an NFT is received from a contract other than the configured SushiSwap NFT.
    error SushiStakerInvalidNFTContract();
    /// @notice Thrown when the caller does not own the NFT they are trying to stake.
    error SushiStakerNotTokenOwner();
    /// @notice Thrown when the caller is not the original staker of the NFT they are trying to unstake.
    error SushiStakerNotTokenStaker();
    /// @notice Thrown when attempting to unstake a token that is not currently staked.
    error SushiStakerTokenNotStaked();
    /// @notice Thrown when a zero address is provided where a non-zero address is required.
    error SushiStakerZeroAddress();
    /// @notice Thrown when attempting to stake a position with zero liquidity.
    error SushiStakerZeroLiquidity();

    // =============================================================
    //                          EVENTS
    // =============================================================

    /**
     * @notice Emitted when a SushiSwap V3 NFT position is staked.
     * @param user The address of the user who staked the position.
     * @param tokenId The NFT token ID of the staked position.
     * @param pool The address of the SushiSwap V3 pool the position belongs to.
     * @param tickLower The lower tick boundary of the position's price range.
     * @param tickUpper The upper tick boundary of the position's price range.
     * @param liquidity The amount of liquidity in the position at the time of staking.
     * @param secondsPerLiquidityInsideInitialX128 Seconds per liquidity inside the tick range at stake time.
     * @param timestamp The block timestamp when the position was staked.
     */
    event TokenStaked(
        address indexed user,
        uint256 indexed tokenId,
        address pool,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint160 secondsPerLiquidityInsideInitialX128,
        uint256 timestamp
    );

    /**
     * @notice Emitted when a staked SushiSwap V3 NFT position is unstaked and returned to the user.
     * @param user The address of the user who unstaked the position.
     * @param tokenId The NFT token ID of the unstaked position.
     * @param pool The address of the SushiSwap V3 pool the position belongs to.
     * @param tickLower The lower tick boundary of the position's price range.
     * @param tickUpper The upper tick boundary of the position's price range.
     * @param liquidity The amount of liquidity in the position at the time of unstaking.
     * @param secondsPerLiquidityInsideX128 Cumulative seconds per liquidity inside the tick range at unstake time.
     * @param timestamp The block timestamp when the position was unstaked.
     */
    event TokenUnstaked(
        address indexed user,
        uint256 indexed tokenId,
        address pool,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint160 secondsPerLiquidityInsideX128,
        uint256 timestamp
    );

    /**
     * @notice Emitted when trading fees are collected from a staked position.
     * @param tokenId The NFT token ID of the position fees were collected from.
     * @param recipient The address that received the collected fees.
     * @param epochId The gauge voter epoch ID at the time of fee collection, used for off-chain accounting.
     * @param pool The address of the SushiSwap V3 pool the position belongs to.
     * @param token0 The address of the pool's token0.
     * @param token1 The address of the pool's token1.
     * @param amount0 The amount of token0 fees collected.
     * @param amount1 The amount of token1 fees collected.
     */
    event FeesCollected(
        uint256 indexed tokenId,
        address indexed recipient,
        uint256 indexed epochId,
        address pool,
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1
    );

    /**
     * @notice Emitted when the fee collector address is updated by the owner.
     * @param oldCollector The previous fee collector address.
     * @param newCollector The new fee collector address.
     */
    event FeeCollectorUpdated(address indexed oldCollector, address indexed newCollector);

    /**
     * @notice Emitted when the gauge voter address is updated by the owner.
     * @param oldGaugeVoter The previous gauge voter address.
     * @param newGaugeVoter The new gauge voter address.
     */
    event GaugeVoterUpdated(address indexed oldGaugeVoter, address indexed newGaugeVoter);

    // =============================================================
    //                    EIP-7201 NAMESPACED STORAGE
    // =============================================================

    /// @custom:storage-location erc7201:sushistaker.storage.main
    struct SushiStakerStorage {
        /// @notice The SushiSwap NFT contract address
        INonfungiblePositionManager sushiNft;
        /// @notice The Uniswap V3 Factory address
        IUniswapV3Factory factory;
        /// @notice The fee collector address
        address feeCollector;
        /// @notice Mapping from token ID to staker address
        mapping(uint256 => address) tokenStaker;
        /// @notice Mapping from token ID to stake timestamp
        mapping(uint256 => uint256) stakeTimestamp;
        /// @notice The gauge voter address
        address gaugeVoter;
    }

    // keccak256(abi.encode(uint256(keccak256("sushistaker.storage.main")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant SUSHI_STAKER_STORAGE_LOCATION =
        0xb440148b1c334507c0052c0f23ea4ea76d9ce3c5acb0c2d6dee0a0b55e066300;

    /**
     * @dev Flag set during stake() to allow onERC721Received to accept the transfer without staking.
     *      Uses transient storage (EIP-1153) — automatically cleared at end of transaction.
     */
    bool private transient _staking;

    function _getSushiStakerStorage() private pure returns (SushiStakerStorage storage $) {
        assembly {
            $.slot := SUSHI_STAKER_STORAGE_LOCATION
        }
    }

    // =============================================================
    //                        CONSTRUCTOR
    // =============================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // =============================================================
    //                        INITIALIZER
    // =============================================================

    /**
     * @notice Initialize the contract
     * @param _sushiNft The SushiSwap NFT contract address
     * @param _factory The Uniswap V3 Factory address
     * @param _feeCollector The fee collector address
     * @param _gaugeVoter The gauge voter address
     * @param _owner The owner of the contract
     */
    function initialize(address _sushiNft, address _factory, address _feeCollector, address _gaugeVoter, address _owner)
        external
        initializer
    {
        if (_sushiNft == address(0)) revert SushiStakerZeroAddress();
        if (_factory == address(0)) revert SushiStakerZeroAddress();
        if (_feeCollector == address(0)) revert SushiStakerZeroAddress();
        if (_gaugeVoter == address(0)) revert SushiStakerZeroAddress();
        if (_owner == address(0)) revert SushiStakerZeroAddress();

        __Ownable_init(_owner);

        SushiStakerStorage storage $ = _getSushiStakerStorage();
        $.sushiNft = INonfungiblePositionManager(_sushiNft);
        $.factory = IUniswapV3Factory(_factory);
        $.feeCollector = _feeCollector;
        $.gaugeVoter = _gaugeVoter;

        emit FeeCollectorUpdated(address(0), _feeCollector);
        emit GaugeVoterUpdated(address(0), _gaugeVoter);
    }

    // =============================================================
    //                       EXTERNAL FUNCTIONS
    // =============================================================

    /**
     * @notice Stake a SushiSwap NFT position
     * @dev Collects any existing fees and returns them to the user before staking
     * @param tokenId The token ID to stake
     */
    function stake(uint256 tokenId) external nonReentrant {
        SushiStakerStorage storage $ = _getSushiStakerStorage();

        // Verify the NFT is from the correct contract and user owns it
        if (IERC721(address($.sushiNft)).ownerOf(tokenId) != msg.sender) revert SushiStakerNotTokenOwner();

        // Transfer NFT to this contract
        // Note: This triggers onERC721Received, which detects the _staking
        // flag and returns early without double-staking
        _staking = true;
        IERC721(address($.sushiNft)).safeTransferFrom(msg.sender, address(this), tokenId);
        _staking = false;

        // Perform staking logic
        _stakeInternal(tokenId, msg.sender, $);
    }

    /**
     * @notice Unstake a SushiSwap NFT position
     * @dev Collects accumulated fees and sends them to feeCollector before unstaking
     * @param tokenId The token ID to unstake
     */
    function unstake(uint256 tokenId) external nonReentrant {
        SushiStakerStorage storage $ = _getSushiStakerStorage();

        // Verify the token is staked
        if ($.tokenStaker[tokenId] == address(0)) revert SushiStakerTokenNotStaked();

        // Verify the caller is the original staker
        if ($.tokenStaker[tokenId] != msg.sender) revert SushiStakerNotTokenStaker();

        // Collect fees accumulated during staking and send to feeCollector
        _collectAndTransferFees(tokenId, $.feeCollector, $);

        // Emit event with position details before clearing state
        _emitUnstakeEvent(tokenId, msg.sender, $);

        // Clear staking info
        delete $.tokenStaker[tokenId];
        delete $.stakeTimestamp[tokenId];

        // Transfer NFT back to user
        IERC721(address($.sushiNft)).safeTransferFrom(address(this), msg.sender, tokenId);
    }

    /**
     * @notice Collect fees for multiple staked positions
     * @dev Can be called by anyone. Fees are sent to feeCollector
     * @param tokenIds Array of token IDs to collect fees for
     */
    function collectFeesMultiple(uint256[] calldata tokenIds) external nonReentrant {
        SushiStakerStorage storage $ = _getSushiStakerStorage();

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];

            // Only collect fees for staked tokens
            if ($.tokenStaker[tokenId] != address(0)) {
                _collectAndTransferFees(tokenId, $.feeCollector, $);
            }
        }
    }

    // =============================================================
    //                    INTERNAL FUNCTIONS
    // =============================================================

    /**
     * @dev Internal function to collect fees and transfer to recipient
     * @param tokenId The token ID to collect fees for
     * @param recipient The address to receive the fees
     * @param $ Storage pointer
     */
    function _collectAndTransferFees(uint256 tokenId, address recipient, SushiStakerStorage storage $) private {
        // Get token addresses from position
        (,, address token0, address token1, uint24 fee,,,,,,,) = $.sushiNft.positions(tokenId);

        // Collect all available fees directly to recipient
        (uint256 amount0, uint256 amount1) = $.sushiNft
            .collect(
                INonfungiblePositionManager.CollectParams({
                    tokenId: tokenId, recipient: recipient, amount0Max: type(uint128).max, amount1Max: type(uint128).max
                })
            );

        // Emit event if any fees were collected
        if (amount0 > 0 || amount1 > 0) {
            uint256 epochId = IAddressGaugeVoter($.gaugeVoter).epochId();
            address pool = $.factory.getPool(token0, token1, fee);
            emit FeesCollected(tokenId, recipient, epochId, pool, token0, token1, amount0, amount1);
        }
    }

    /**
     * @dev Internal function to record staking state and emit event
     * @param tokenId The token ID being staked
     * @param staker The address to record as the staker
     * @param $ Storage pointer
     */
    function _stakeInternal(uint256 tokenId, address staker, SushiStakerStorage storage $) private {
        // Collect any existing fees and send to staker
        _collectAndTransferFees(tokenId, staker, $);

        // Record staking info
        $.tokenStaker[tokenId] = staker;
        $.stakeTimestamp[tokenId] = block.timestamp;

        // Emit event with position details
        _emitStakeEvent(tokenId, staker, $);
    }

    /**
     * @dev Internal function to emit stake event with position details
     */
    function _emitStakeEvent(uint256 tokenId, address user, SushiStakerStorage storage $) private {
        (,, address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper, uint128 liquidity,,,,) =
            $.sushiNft.positions(tokenId);

        // Verify position has liquidity
        if (liquidity == 0) revert SushiStakerZeroLiquidity();

        // Get pool address
        address pool = $.factory.getPool(token0, token1, fee);

        // Get secondsPerLiquidityInsideX128
        (, uint160 secondsPerLiquidityInsideInitialX128,) =
            IUniswapV3Pool(pool).snapshotCumulativesInside(tickLower, tickUpper);

        emit TokenStaked(
            user, tokenId, pool, tickLower, tickUpper, liquidity, secondsPerLiquidityInsideInitialX128, block.timestamp
        );
    }

    /**
     * @dev Internal function to emit unstake event with position details
     */
    function _emitUnstakeEvent(uint256 tokenId, address user, SushiStakerStorage storage $) private {
        (,, address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper, uint128 liquidity,,,,) =
            $.sushiNft.positions(tokenId);

        // Get pool address
        address pool = $.factory.getPool(token0, token1, fee);

        // Get current secondsPerLiquidityInsideX128
        (, uint160 secondsPerLiquidityInsideX128,) =
            IUniswapV3Pool(pool).snapshotCumulativesInside(tickLower, tickUpper);

        emit TokenUnstaked(
            user, tokenId, pool, tickLower, tickUpper, liquidity, secondsPerLiquidityInsideX128, block.timestamp
        );
    }

    // =============================================================
    //                        VIEW FUNCTIONS
    // =============================================================

    /**
     * @notice Get the SushiSwap NFT contract address
     * @return The NFT contract address
     */
    function sushiNft() external view returns (address) {
        return address(_getSushiStakerStorage().sushiNft);
    }

    /**
     * @notice Get the Uniswap V3 Factory address
     * @return The factory contract address
     */
    function factory() external view returns (address) {
        return address(_getSushiStakerStorage().factory);
    }

    /**
     * @notice Get the fee collector address
     * @return The fee collector address
     */
    function feeCollector() external view returns (address) {
        return _getSushiStakerStorage().feeCollector;
    }

    /**
     * @notice Get the staker of a token
     * @param tokenId The token ID to query
     * @return The staker address (address(0) if not staked)
     */
    function getStaker(uint256 tokenId) external view returns (address) {
        return _getSushiStakerStorage().tokenStaker[tokenId];
    }

    /**
     * @notice Get the stake timestamp of a token
     * @param tokenId The token ID to query
     * @return The stake timestamp (0 if not staked)
     */
    function getStakeTimestamp(uint256 tokenId) external view returns (uint256) {
        return _getSushiStakerStorage().stakeTimestamp[tokenId];
    }

    /**
     * @notice Check if a token is currently staked
     * @param tokenId The token ID to check
     * @return True if the token is staked
     */
    function isStaked(uint256 tokenId) external view returns (bool) {
        return _getSushiStakerStorage().tokenStaker[tokenId] != address(0);
    }

    /**
     * @notice Get the gauge voter address
     * @return The gauge voter address
     */
    function getGaugeVoter() external view returns (address) {
        return _getSushiStakerStorage().gaugeVoter;
    }

    /**
     * @notice Get position information for a token
     * @param tokenId The token ID to query
     * @return token0 The first token of the pool
     * @return token1 The second token of the pool
     * @return fee The fee tier of the pool
     * @return tickLower The lower tick of the position
     * @return tickUpper The upper tick of the position
     * @return liquidity The liquidity of the position
     */
    function getPositionInfo(uint256 tokenId)
        external
        view
        returns (address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper, uint128 liquidity)
    {
        SushiStakerStorage storage $ = _getSushiStakerStorage();
        (,, token0, token1, fee, tickLower, tickUpper, liquidity,,,,) = $.sushiNft.positions(tokenId);
    }

    /**
     * @notice Fee collection statistics for multiple positions
     * @dev Used by backend to preview fees before calling collectFeesMultiple
     */
    struct FeeStats {
        uint256 totalTokensOwed0; // Total token0 fees available to collect
        uint256 totalTokensOwed1; // Total token1 fees available to collect
        uint256 stakedTokensCount; // Number of staked tokens in the provided array
        uint256 unstakedTokensCount; // Number of unstaked tokens in the provided array
        uint256 totalLiquidity; // Total liquidity across all staked positions
        uint256[] unstakedTokenIds; // Array of token IDs that are not staked
    }

    /**
     * @notice Get cumulative fee collection statistics for multiple token IDs
     * @dev This is a view function to check fees before calling collectFeesMultiple
     * @param tokenIds Array of token IDs to check
     * @return stats Cumulative statistics including total fees, counts, liquidity, and unstaked token IDs
     */
    function collectFeesMultipleStats(uint256[] calldata tokenIds) external view returns (FeeStats memory stats) {
        SushiStakerStorage storage $ = _getSushiStakerStorage();

        // Allocate at max possible size, will be trimmed after the loop
        stats.unstakedTokenIds = new uint256[](tokenIds.length);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];

            // Check if token is staked
            if ($.tokenStaker[tokenId] != address(0)) {
                stats.stakedTokensCount++;

                // Get position data including tokensOwed
                (,,,,,,, uint128 liquidity,,, uint128 tokensOwed0, uint128 tokensOwed1) = $.sushiNft.positions(tokenId);

                // Accumulate fees and liquidity
                stats.totalTokensOwed0 += tokensOwed0;
                stats.totalTokensOwed1 += tokensOwed1;
                stats.totalLiquidity += liquidity;
            } else {
                stats.unstakedTokenIds[stats.unstakedTokensCount] = tokenId;
                stats.unstakedTokensCount++;
            }
        }

        // Trim the array to actual size
        assembly {
            mstore(mload(add(stats, 160)), mload(add(stats, 96)))
        }
    }

    // =============================================================
    //                      ADMIN FUNCTIONS
    // =============================================================

    /**
     * @notice Update the fee collector address (only owner)
     * @param _newFeeCollector The new fee collector address
     */
    function setFeeCollector(address _newFeeCollector) external onlyOwner {
        if (_newFeeCollector == address(0)) revert SushiStakerZeroAddress();

        SushiStakerStorage storage $ = _getSushiStakerStorage();
        address oldCollector = $.feeCollector;
        $.feeCollector = _newFeeCollector;

        emit FeeCollectorUpdated(oldCollector, _newFeeCollector);
    }

    /**
     * @notice Set the gauge voter address (only owner)
     * @param _gaugeVoter The new gauge voter address
     */
    function setGaugeVoter(address _gaugeVoter) external onlyOwner {
        if (_gaugeVoter == address(0)) revert SushiStakerZeroAddress();

        SushiStakerStorage storage $ = _getSushiStakerStorage();
        address oldGaugeVoter = $.gaugeVoter;
        $.gaugeVoter = _gaugeVoter;

        emit GaugeVoterUpdated(oldGaugeVoter, _gaugeVoter);
    }

    // =============================================================
    //                     ERC721 RECEIVER
    // =============================================================

    /**
     * @notice Handle the receipt of an NFT
     * @dev Automatically stakes NFTs sent directly from users.
     *      When called from stake(), the _staking flag is set,
     *      so we detect that and return early (stake() handles staking).
     */
    function onERC721Received(address, address from, uint256 tokenId, bytes calldata)
        external
        override
        returns (bytes4)
    {
        SushiStakerStorage storage $ = _getSushiStakerStorage();

        // Only accept NFTs from the configured contract
        if (msg.sender != address($.sushiNft)) revert SushiStakerInvalidNFTContract();

        // If _staking flag is set, we're being called from stake()
        // Let stake() handle the staking logic
        if (_staking) {
            return IERC721Receiver.onERC721Received.selector;
        }

        // Reject transfers during reentrancy (e.g., from unstake() callbacks)
        // to prevent NFTs being accepted without proper staking records
        if (_reentrancyGuardEntered()) revert SushiStakerInvalidNFTContract();

        // Direct transfer - validate sender is not zero (prevents minting to contract)
        if (from == address(0)) revert SushiStakerZeroAddress();

        // Automatically stake for the sender
        _stakeInternal(tokenId, from, $);

        return IERC721Receiver.onERC721Received.selector;
    }
}
