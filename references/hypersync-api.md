# HyperSync API Reference

Read this when you need full query structure details, all available fields, or the complete network list.

Docs: https://docs.envio.dev/docs/HyperSync/overview
Query builder: http://builder.hypersync.xyz/
Curl examples: https://docs.envio.dev/docs/HyperSync/hypersync-curl-examples

## Table of Contents

- [Endpoint Pattern](#endpoint-pattern)
- [Query Structure](#query-structure)
- [Selection Types](#selection-types)
- [Join Modes](#join-modes)
- [Pagination](#pagination)
- [All Available Fields](#all-available-fields)

## Endpoint Pattern

```
POST https://<network>.hypersync.xyz/query
GET  https://<network>.hypersync.xyz/height
```

Auth header: `Authorization: Bearer <HYPERSYNC_API_TOKEN>`

## Query Structure

```json
{
  "from_block": 0,
  "to_block": null,
  "logs": [<LogSelection>, ...],
  "transactions": [<TransactionSelection>, ...],
  "traces": [<TraceSelection>, ...],
  "blocks": [<BlockSelection>, ...],
  "include_all_blocks": false,
  "field_selection": { "block": [...], "log": [...], "transaction": [...], "trace": [...] },
  "max_num_blocks": null,
  "max_num_transactions": null,
  "max_num_logs": null,
  "max_num_traces": null,
  "join_mode": "Default"
}
```

Multiple entries in `logs`, `transactions`, or `traces` arrays have **OR** relationship.
Fields within a single selection have **AND** relationship.

## Selection Types

### LogSelection

```json
{
  "address": ["0x..."],
  "topics": [
    ["0xEVENT_SIG"],
    ["0xINDEXED_PARAM_1"],
    [],
    []
  ]
}
```

- `address`: contracts to match (empty = all)
- `topics`: array of 4 arrays. Each position is OR within, AND across positions.
  - topics[0] = event signature hash (topic0)
  - topics[1-3] = indexed parameters

### TransactionSelection

```json
{
  "from": ["0x..."],
  "to": ["0x..."],
  "sighash": ["0x12345678"],
  "status": 1,
  "type": [2],
  "contract_address": ["0x..."]
}
```

- `sighash`: first 4 bytes of input data (function selector)
- `status`: 1 = success, 0 = failed
- `type`: 0 = legacy, 1 = EIP-2930, 2 = EIP-1559, 3 = EIP-4844
- `from` AND `to` within one selection, but OR across multiple selections

### TraceSelection

```json
{
  "from": ["0x..."],
  "to": ["0x..."],
  "address": ["0x..."],
  "call_type": ["call", "delegatecall", "staticcall"],
  "kind": ["call", "create", "suicide", "reward"],
  "sighash": ["0x12345678"]
}
```

### BlockSelection

```json
{
  "hash": ["0x..."],
  "miner": ["0x..."]
}
```

## Join Modes

| Mode | Behavior |
|------|----------|
| `Default` | logs → txs → traces → blocks (follow relationships) |
| `JoinAll` | All data from matching transactions (all logs, traces of tx) |
| `JoinNothing` | Only directly matched data, no related records |

Use `JoinAll` for full transaction analysis. Use `JoinNothing` for targeted queries.

## Pagination

Response includes `next_block`. To continue, set `from_block = next_block` in next query.
Default server timeout: 5 seconds per query. Use multiple pages for large scans.

## All Available Fields

### Block Fields

number, hash, parent_hash, timestamp, miner, gas_limit, gas_used, base_fee_per_gas, logs_bloom, difficulty, total_difficulty, extra_data, mix_hash, nonce, sha3_uncles, state_root, transactions_root, receipts_root, size, uncles, withdrawals_root, withdrawals, blob_gas_used, excess_blob_gas, parent_beacon_block_root

### Transaction Fields

block_hash, block_number, hash, transaction_index, from, to, gas, gas_price, gas_used, cumulative_gas_used, effective_gas_price, max_priority_fee_per_gas, max_fee_per_gas, input, value, nonce, v, r, s, y_parity, chain_id, contract_address, status, logs_bloom, root, access_list, max_fee_per_blob_gas, blob_versioned_hashes, type, l1_fee, l1_gas_price, l1_gas_used, l1_fee_scalar, gas_used_for_l1

### Log Fields

log_index, transaction_index, transaction_hash, block_hash, block_number, address, data, topic0, topic1, topic2, topic3, removed

### Trace Fields

transaction_hash, transaction_position, subtraces, trace_address, block_hash, block_number, from, to, value, gas, gas_used, input, init, output, address, code, type, call_type, reward_type, author, error

## Complete Network List

| Network | ID | URL slug |
|---------|-----|----------|
| Ethereum | 1 | eth |
| Base | 8453 | base |
| Arbitrum | 42161 | arbitrum |
| Optimism | 10 | optimism |
| Polygon | 137 | polygon |
| BSC | 56 | bsc |
| Scroll | 534352 | scroll |
| Avalanche | 43114 | avalanche |
| Gnosis | 100 | gnosis |
| Fantom | 250 | fantom |
| Linea | 59144 | linea |
| Blast | 81457 | blast |
| ZKsync | 324 | zksync |
| Zora | 7777777 | zora |
| Mode | 34443 | mode |
| Mantle | 5000 | mantle |
| Celo | 42220 | celo |
| Moonbeam | 1284 | moonbeam |
| Polygon zkEVM | 1101 | polygon-zkevm |
| Manta | 169 | manta |
| Abstract | 2741 | abstract |
| Berachain | 80094 | berachain |
| Monad | 143 | monad |
| Sonic | 146 | sonic |
| Hyperliquid | 999 | hyperliquid |
| Unichain | 130 | unichain |
| Soneium | 1868 | soneium |

Any chain ID works via `https://<chain_id>.hypersync.xyz`.

Full list: https://docs.envio.dev/docs/HyperSync/hypersync-supported-networks

## Common Event Signatures (topic0)

### Token Events

| Event | Signature Hash |
|-------|----------------|
| Transfer(address,address,uint256) | 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef |
| Approval(address,address,uint256) | 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925 |
| ApprovalForAll(address,address,bool) | 0x17307eab39ab6107e8899845ad3d59bd9653f200f220920489ca2b5937696c31 |
| TransferSingle(address,address,address,uint256,uint256) (ERC-1155) | 0xc3d58168c5ae7397731d063d5bbf3d657854427343f4c083240f7aacaa2d0f62 |
| TransferBatch(address,address,address,uint256[],uint256[]) (ERC-1155) | 0x4a39dc06d4c0dbc64b70af90fd698a233a518aa5d07e595d983b8c0526c8f7fb |

### WETH

| Event | Signature Hash |
|-------|----------------|
| Deposit(address,uint256) | 0xe1fffcc4923d04b559f4d29a8bfc6cda04eb5b0d3c460751c2402c5c5cc9109c |
| Withdrawal(address,uint256) | 0x7fcf532c15f0a6db0bd6d0e038bea71d30d808c7d98cb3bf7268a95bf5081b65 |

### DEX / AMM

| Event | Signature Hash |
|-------|----------------|
| Swap — Uniswap V2 (address,uint256,uint256,uint256,uint256,address) | 0xd78ad95fa46c994b6551d0da85fc275fe613ce37657fb8d5e3d130840159d822 |
| Swap — Uniswap V3 (address,address,int256,int256,uint160,uint128,int24) | 0xc42079f94a6350d7e6235f29174924f928cc2ac818eb64fed8004e115fbcca67 |
| Sync — Uniswap V2 (uint112,uint112) | 0x1c411e9a96e071241c2f21f7726b17ae89e3cab4c78be50e062b03a9fffbbad1 |
| PairCreated — Uniswap V2 (address,address,address,uint256) | 0x0d3648bd0f6ba80134a33ba9275ac585d9d315f0ad8355cddefde31afa28d0e9 |
| PoolCreated — Uniswap V3 (address,address,uint24,int24,address) | 0x783cca1c0412dd0d695e784568c96da2e9c22ff989357a2e8b1d9b2b4e6b7118 |

### Governance / Proxy

| Event | Signature Hash |
|-------|----------------|
| OwnershipTransferred(address,address) | 0x8be0079c531659141344cd1fd0a4f28419497f9722a3daafe3b4186f6b6457e0 |
| Upgraded(address) | 0xbc7cd75a20ee27fd9adebab32041f755214dbc6bffa90cc0225b39da2e5c2d3b |
| AdminChanged(address,address) | 0x7e644d79422f17c01e4894b5f4f588d331ebfa28653d42ae832dc59e38c9798f |

## Query Recipes

### All Uniswap V2 Swaps on a Pool

```json
{
  "from_block": 0,
  "logs": [{
    "address": ["0xPOOL_ADDRESS"],
    "topics": [["0xd78ad95fa46c994b6551d0da85fc275fe613ce37657fb8d5e3d130840159d822"]]
  }],
  "field_selection": {
    "log": ["block_number", "transaction_hash", "address", "data", "topic0", "topic1", "topic2"],
    "block": ["number", "timestamp"],
    "transaction": ["hash", "from", "to", "value"]
  }
}
```

### All NFT Mints Across All Contracts

```json
{
  "from_block": 0,
  "logs": [{
    "topics": [
      ["0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"],
      ["0x0000000000000000000000000000000000000000000000000000000000000000"]
    ]
  }],
  "field_selection": {
    "log": ["block_number", "transaction_hash", "address", "topic0", "topic1", "topic2", "topic3"],
    "transaction": ["hash", "from", "to", "value"]
  }
}
```

### Internal Call Traces to a Contract

Only on networks with trace support (use `eth-traces.hypersync.xyz` for Ethereum):

```json
{
  "from_block": 0,
  "traces": [{"to": ["0xCONTRACT"], "call_type": ["call", "delegatecall"]}],
  "field_selection": {
    "trace": ["block_number", "transaction_hash", "from", "to", "value", "input", "output", "gas_used", "call_type", "trace_address", "error"],
    "transaction": ["hash", "from", "to"]
  }
}
```

### Contract Creations

```json
{
  "from_block": 0,
  "traces": [{"kind": ["create"]}],
  "field_selection": {
    "trace": ["block_number", "transaction_hash", "from", "address", "gas_used"]
  }
}
```

## Reverse Search

Add `reverse: true` to stream from the chain tip backwards (useful for "most recent" queries).

## Rate Limits

Free tier has rate limits. Obtain API token from https://envio.dev for higher throughput.
