# SushiSwap NFT Position Staker

A smart contract that allows users to stake their SushiSwap V3 NFT positions with automated fee collection. Built with upgradeable architecture using OpenZeppelin's Transparent Proxy pattern and EIP-7201 namespaced storage.

## Overview

The staker contract enables users to deposit their SushiSwap V3 liquidity positions (represented as NFTs) and have their staking activity tracked on-chain. Fees are automatically collected and distributed, while reward calculations are performed off-chain based on emitted events.

## Key Features

- **Stake/Unstake NFT Positions**: Users can deposit and withdraw their SushiSwap V3 positions at any time
- **Automated Fee Collection**: 
  - Pre-existing fees returned to user on stake
  - Accumulated fees sent to protocol fee collector on unstake
  - Batch collection available for multiple positions
- **Event-Based Tracking**: Detailed events for off-chain reward calculation systems
- **Upgradeable Architecture**: Transparent proxy with EIP-7201 storage to prevent collisions
- **Security**: ReentrancyGuard, access control, and NFT contract validation

## Architecture

```
User → TransparentUpgradeableProxy → SushiStaker Implementation
         ↓
       ProxyAdmin (Owner controlled)
```

**Components:**
- **SushiStaker**: Core implementation with staking logic
- **TransparentUpgradeableProxy**: Delegates calls to implementation
- **ProxyAdmin**: Manages upgrades (owner controlled)

## Fee Collection Flow

### On Stake
1. User approves and transfers NFT to contract
2. Contract collects any pre-existing fees → sends to user
3. Position recorded as staked with zero fees

### On Unstake
1. Contract collects fees accumulated during staking
2. Fees sent to designated `feeCollector` address
3. NFT returned to user

### Batch Collection
- `collectFeesMultiple(tokenIds[])` can be called by anyone
- Collects fees from multiple staked positions (skips unstaked tokens)
- All fees sent to `feeCollector`

### Fee Preview (New)
- `collectFeesMultipleStats(tokenIds[])` - View function for backend integration
- Returns cumulative statistics:
  - `totalTokensOwed0/1`: Total collectable fees
  - `stakedTokensCount/unstakedTokensCount`: Number of staked/unstaked tokens
  - `totalLiquidity`: Sum of liquidity across staked positions
  - `unstakedTokenIds[]`: Array of token IDs that are not staked
- Use this to preview fees before calling `collectFeesMultiple`

## Installation & Setup

```bash
# Install dependencies (using soldeer)
forge soldeer install

# Build contracts
forge build

# Run tests
forge test
```

**Note**: This project uses [Soldeer](https://soldeer.xyz/) for dependency management instead of git submodules.

## Deployment

1. Configure environment:

```bash
cp .env.example .env
# Edit .env with your settings
```

**Required variables:**
- `PRIVATE_KEY`: Deployer private key
- `SUSHI_NFT_CONTRACT`: SushiSwap NFT Position Manager address
- `FACTORY_CONTRACT`: SushiSwap V3 Factory address
- `FEE_COLLECTOR`: Address to receive collected fees
- `GAUGE_VOTER`: Address of the gauge voter contract
- `OWNER_ADDRESS`: Contract owner (admin functions)
- `RPC_URL`: Network RPC endpoint

**Mainnet Addresses:**
- SushiSwap NFT Position Manager: `0x2214A42d8e2A1d20635c2cb0664422c528B6A432`
- SushiSwap V3 Factory: `0xbACEB8eC6b9355Dfc0269C18bac9d6E2Bdc29C4F`

2. Deploy:

```bash
forge script script/Deploy.s.sol:DeploySushiStaker \
    --rpc-url $RPC_URL \
    --broadcast \
    --verify
```

3. Upgrade (if needed):

```bash
# Add PROXY_ADMIN_ADDRESS and PROXY_ADDRESS to .env
forge script script/Deploy.s.sol:UpgradeSushiStaker \
    --rpc-url $RPC_URL \
    --broadcast \
    --verify
```

## Core Functions

### User Functions

| Function | Description |
|----------|-------------|
| `stake(uint256 tokenId)` | Stake NFT position (requires approval first) |
| `unstake(uint256 tokenId)` | Unstake position (only original staker) |
| `collectFeesMultiple(uint256[] tokenIds)` | Batch collect fees (public) |
| `collectFeesMultipleStats(uint256[] tokenIds)` | View function to preview fees before collection |

### View Functions

| Function | Returns |
|----------|---------|
| `sushiNFT()` | NFT contract address |
| `factory()` | Factory contract address |
| `feeCollector()` | Fee collector address |
| `gaugeVoter()` | Gauge voter contract address |
| `getStaker(uint256 tokenId)` | Staker address (or address(0)) |
| `getStakeTimestamp(uint256 tokenId)` | Unix timestamp of stake |
| `isStaked(uint256 tokenId)` | Boolean staking status |
| `getPositionInfo(uint256 tokenId)` | Position details (tokens, ticks, liquidity) |
| `collectFeesMultipleStats(uint256[] tokenIds)` | Preview stats (fees, counts, liquidity, unstaked IDs) |

### Admin Functions (Owner Only)

| Function | Description |
|----------|-------------|
| `setFeeCollector(address)` | Update fee collector address (cannot be zero) |
| `setGaugeVoter(address)` | Update gauge voter address (cannot be zero) |

## Events

**TokenStaked**: Emitted when a position is staked
```solidity
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
```

**TokenUnstaked**: Emitted when a position is unstaked
```solidity
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
```

**FeesCollected**: Emitted when fees are collected
```solidity
event FeesCollected(
    uint256 indexed tokenId,
    address indexed recipient,
    address token0,
    address token1,
    uint256 amount0,
    uint256 amount1
);
```

**FeeCollectorUpdated**: Emitted when fee collector is changed
```solidity
event FeeCollectorUpdated(address oldCollector, address newCollector);
```

**GaugeVoterUpdated**: Emitted when gauge voter is changed
```solidity
event GaugeVoterUpdated(address oldVoter, address newVoter);
```

## Off-Chain Reward Calculation

The contract emits detailed events for off-chain systems to calculate rewards:

1. **Index events**: Query `TokenStaked` and `TokenUnstaked` events to build position state
2. **Calculate liquidity-seconds**: Use difference in `secondsPerLiquidityInside` × `liquidity`

Example:
```javascript
// Query events to get position data
const stakedEvent = await contract.queryFilter('TokenStaked', ...);
const { liquidity, secondsPerLiquidityInsideInitialX128 } = stakedEvent.args;

// On unstake event
const unstakedEvent = await contract.queryFilter('TokenUnstaked', ...);
const { secondsPerLiquidityInsideX128: finalSecondsPerLiquidity } = unstakedEvent.args;

// Calculate reward
const secondsInside = finalSecondsPerLiquidity - secondsPerLiquidityInsideInitialX128;
const rewardShare = (liquidity * secondsInside) / totalLiquiditySeconds;
const userReward = totalRewardPool * rewardShare;
```

## Error Handling

| Error | Triggered When |
|-------|----------------|
| `InvalidNFTContract()` | Non-approved NFT contract attempts transfer |
| `NotTokenOwner()` | Caller doesn't own NFT being staked |
| `TokenNotStaked()` | Attempting to unstake non-staked token |
| `NotTokenStaker()` | Caller is not the original staker |
| `ZeroAddress()` | Zero address provided (initialization, setFeeCollector, setGaugeVoter) |
| `ZeroLiquidity()` | Position has no liquidity |

## Security Features

- **NFT Validation**: Only accepts NFTs from configured SushiSwap contract
- **Authorization**: Only original staker can unstake
- **Reentrancy Protection**: ReentrancyGuard on all state-changing functions
- **Safe Transfers**: SafeERC20 for token transfers
- **Zero Address Protection**: Validation on critical addresses (feeCollector, gaugeVoter)
- **Upgradeability**: EIP-7201 namespaced storage prevents collisions


## Testing

```bash
# Run all tests
forge test

# Verbose output
forge test -vvv

# Test coverage
forge coverage

# Specific test
forge test --match-test test_Stake
```

**Test Coverage:**
- Initialization and upgrades
- Stake/unstake flows
- Fee collection (pre-stake, post-stake, batch)
- Fee statistics preview (`collectFeesMultipleStats`)
- Error conditions (zero addresses, zero liquidity, authorization)
- Admin functions (setFeeCollector, setGaugeVoter)
- Direct NFT transfers (auto-staking via `onERC721Received`)
- EIP-7201 storage verification

**Test Results:** 41 tests passing across 3 test suites

## License

MIT
