# Chain Analyst

Agent skill for reproducible EVM blockchain analysis — decode transactions, query contract state, trace token flows, and fetch ABIs/prices across any EVM network.

## Install

```bash
npx skills add lutr0/chain-analyst
```

## What it does

Gives your AI agent six shell scripts that cover the most common onchain analysis tasks:

| Script | Purpose |
|--------|---------|
| `analyze-tx.sh` | Full transaction breakdown — fetches tx, logs, traces, and ABIs in one shot |
| `hypersync-query.sh` | Paginated historical queries over logs, traces, and transactions via HyperSync |
| `query-contract.sh` | Read current contract state via RPC (falls back through curl, cast, viem) |
| `get-contract-abi.sh` | Fetch verified ABI from Etherscan (unified V2 multichain endpoint) |
| `get-token-price.sh` | Current or historical token price from CoinGecko |
| `multicall.sh` | Batch multiple contract reads in a single RPC call via viem multicall |

## Setup

Copy `.env.example` to `.env` and fill in your keys:

```
HYPERSYNC_API_TOKEN=       # required — https://envio.dev
ETHERSCAN_API_KEY=         # required — https://etherscan.io/apidashboard
COINGECKO_API_KEY=         # optional — https://www.coingecko.com/en/api/pricing
```
## License

MIT
