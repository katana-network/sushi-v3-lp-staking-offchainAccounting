// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

/// @title Interface for the Nonfungible Position Manager
/// @notice Minimal interface for interacting with Uniswap/SushiSwap V3 NFT positions
/// @dev We use a minimal interface instead of the full INonfungiblePositionManager to avoid
///      OpenZeppelin version conflicts between v4 (used by Uniswap) and v5 (used by this project)
interface INonfungiblePositionManager {
    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );

    function collect(CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1);
}

/**
 * @title SushiStaker
 * @notice A contract that allows users to stake their SushiSwap NFT positions
 * @dev Uses EIP-7201 namespaced storage for transparent proxy compatibility
 */
contract SushiStaker is Initializable, OwnableUpgradeable, ReentrancyGuard, IERC721Receiver {
    // =============================================================
    //                          ERRORS
    // =============================================================

    error InvalidNFTContract();
    error NotTokenOwner();
    error NotTokenStaker();
    error TokenNotStaked();
    error ZeroAddress();
    error ZeroLiquidity();

    // =============================================================
    //                          EVENTS
    // =============================================================

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

    event FeesCollected(
        uint256 indexed tokenId,
        address indexed recipient,
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1
    );

    event FeeCollectorUpdated(address indexed oldCollector, address indexed newCollector);

    // =============================================================
    //                    EIP-7201 NAMESPACED STORAGE
    // =============================================================

    /// @custom:storage-location erc7201:sushistaker.storage.main
    struct SushiStakerStorage {
        /// @notice The SushiSwap NFT contract address
        INonfungiblePositionManager sushiNFT;
        /// @notice The Uniswap V3 Factory address
        IUniswapV3Factory factory;
        /// @notice The fee collector address
        address feeCollector;
        /// @notice Mapping from token ID to staker address
        mapping(uint256 => address) tokenStaker;
        /// @notice Mapping from token ID to stake timestamp
        mapping(uint256 => uint256) stakeTimestamp;
    }

    // keccak256(abi.encode(uint256(keccak256("sushistaker.storage.main")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant SUSHI_STAKER_STORAGE_LOCATION =
        0xb440148b1c334507c0052c0f23ea4ea76d9ce3c5acb0c2d6dee0a0b55e066300;

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
     * @param _sushiNFT The SushiSwap NFT contract address
     * @param _factory The Uniswap V3 Factory address
     * @param _feeCollector The fee collector address
     * @param _owner The owner of the contract
     */
    function initialize(address _sushiNFT, address _factory, address _feeCollector, address _owner)
        external
        initializer
    {
        if (_sushiNFT == address(0)) revert ZeroAddress();
        if (_factory == address(0)) revert ZeroAddress();
        if (_feeCollector == address(0)) revert ZeroAddress();
        if (_owner == address(0)) revert ZeroAddress();

        __Ownable_init(_owner);

        SushiStakerStorage storage $ = _getSushiStakerStorage();
        $.sushiNFT = INonfungiblePositionManager(_sushiNFT);
        $.factory = IUniswapV3Factory(_factory);
        $.feeCollector = _feeCollector;

        emit FeeCollectorUpdated(address(0), _feeCollector);
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
        if (IERC721(address($.sushiNFT)).ownerOf(tokenId) != msg.sender) revert NotTokenOwner();

        // Transfer NFT to this contract
        // Note: This triggers onERC721Received, which detects the locked
        // reentrancy guard and returns early without double-staking
        IERC721(address($.sushiNFT)).safeTransferFrom(msg.sender, address(this), tokenId);

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
        if ($.tokenStaker[tokenId] == address(0)) revert TokenNotStaked();

        // Verify the caller is the original staker
        if ($.tokenStaker[tokenId] != msg.sender) revert NotTokenStaker();

        // Collect fees accumulated during staking and send to feeCollector
        _collectAndTransferFees(tokenId, $.feeCollector, $);

        // Emit event with position details before clearing state
        _emitUnstakeEvent(tokenId, msg.sender, $);

        // Clear staking info
        delete $.tokenStaker[tokenId];
        delete $.stakeTimestamp[tokenId];

        // Transfer NFT back to user
        IERC721(address($.sushiNFT)).safeTransferFrom(address(this), msg.sender, tokenId);
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
        (,, address token0, address token1,,,,,,,,) = $.sushiNFT.positions(tokenId);

        // Collect all available fees directly to recipient
        (uint256 amount0, uint256 amount1) = $.sushiNFT
            .collect(
                INonfungiblePositionManager.CollectParams({
                    tokenId: tokenId, recipient: recipient, amount0Max: type(uint128).max, amount1Max: type(uint128).max
                })
            );

        // Emit event if any fees were collected
        if (amount0 > 0 || amount1 > 0) {
            emit FeesCollected(tokenId, recipient, token0, token1, amount0, amount1);
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
            $.sushiNFT.positions(tokenId);

        // Verify position has liquidity
        if (liquidity == 0) revert ZeroLiquidity();

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
            $.sushiNFT.positions(tokenId);

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
    function sushiNFT() external view returns (address) {
        return address(_getSushiStakerStorage().sushiNFT);
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
        (,, token0, token1, fee, tickLower, tickUpper, liquidity,,,,) = $.sushiNFT.positions(tokenId);
    }

    // =============================================================
    //                      ADMIN FUNCTIONS
    // =============================================================

    /**
     * @notice Update the fee collector address (only owner)
     * @param _newFeeCollector The new fee collector address
     */
    function setFeeCollector(address _newFeeCollector) external onlyOwner {
        if (_newFeeCollector == address(0)) revert ZeroAddress();

        SushiStakerStorage storage $ = _getSushiStakerStorage();
        address oldCollector = $.feeCollector;
        $.feeCollector = _newFeeCollector;

        emit FeeCollectorUpdated(oldCollector, _newFeeCollector);
    }

    // =============================================================
    //                     ERC721 RECEIVER
    // =============================================================

    /**
     * @notice Handle the receipt of an NFT
     * @dev Automatically stakes NFTs sent directly from users.
     *      When called from stake(), the reentrancy guard is locked,
     *      so we detect that and return early (stake() handles staking).
     */
    function onERC721Received(address, address from, uint256 tokenId, bytes calldata)
        external
        override
        returns (bytes4)
    {
        SushiStakerStorage storage $ = _getSushiStakerStorage();

        // Only accept NFTs from the configured contract
        if (msg.sender != address($.sushiNFT)) revert InvalidNFTContract();

        // If reentrancy guard is locked, we're being called from stake()
        // Let stake() handle the staking logic
        if (_reentrancyGuardEntered()) {
            return IERC721Receiver.onERC721Received.selector;
        }

        // Direct transfer - validate sender is not zero (prevents minting to contract)
        if (from == address(0)) revert ZeroAddress();

        // Automatically stake for the sender
        _stakeInternal(tokenId, from, $);

        return IERC721Receiver.onERC721Received.selector;
    }
}
