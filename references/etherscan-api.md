# Etherscan API V2 Reference

Read this when you need details on fetching ABIs, contract source code, or other Etherscan API calls.

Docs: https://docs.etherscan.io/
V2 migration: https://docs.etherscan.io/v2-migration

## Table of Contents

- [API V2 — Unified Multichain Endpoint](#api-v2--unified-multichain-endpoint)
- [Chain IDs](#chain-ids)
- [Get Contract ABI](#get-contract-abi)
- [Get Contract Source Code](#get-contract-source-code)
- [Handling Proxies](#handling-proxies)
- [Get Transaction List](#get-transaction-list)
- [Get Internal Transactions](#get-internal-transactions)
- [Get Token Transfers](#get-token-transfers)
- [Rate Limits](#rate-limits)
- [Decoding ABI Data](#decoding-abi-data)

## API V2 — Unified Multichain Endpoint

As of August 2025, Etherscan uses a single V2 endpoint for all chains. One `ETHERSCAN_API_KEY` works across all supported networks.

**Base URL**: `https://api.etherscan.io/v2/api`

Add `chainid=<CHAIN_ID>` to specify the target network. The `get-contract-abi.sh` script handles this automatically.

## Chain IDs

| Network | Chain ID |
|---------|----------|
| Ethereum | 1 |
| Base | 8453 |
| Arbitrum | 42161 |
| Optimism | 10 |
| Polygon | 137 |
| BSC | 56 |
| Scroll | 534352 |
| Gnosis | 100 |
| Linea | 59144 |
| Blast | 81457 |
| Avalanche | 43114 |
| Fantom | 250 |
| Celo | 42220 |
| Moonbeam | 1284 |
| ZKsync | 324 |

## Get Contract ABI

```bash
curl "https://api.etherscan.io/v2/api?chainid=1&module=contract&action=getabi&address=0xCONTRACT&apikey=KEY"
```

Response:
```json
{
  "status": "1",
  "message": "OK",
  "result": "[{\"inputs\":[],\"name\":\"totalSupply\",...}]"
}
```

- `status: "1"` = success, `"0"` = failure
- `result` is a JSON string containing the ABI array

## Get Contract Source Code

```bash
curl "https://api.etherscan.io/api?module=contract&action=getsourcecode&address=0xCONTRACT&apikey=KEY"
```

Response includes:
- `ContractName`: contract name
- `CompilerVersion`: solidity version
- `Implementation`: implementation address (for proxies)
- `Proxy`: "1" if proxy, "0" if not
- `SourceCode`: full source code

## Handling Proxies

If `Proxy == "1"`, fetch the ABI from the `Implementation` address instead:

1. Call `getsourcecode` on the proxy address
2. If `Proxy == "1"`, get `Implementation` address
3. Call `getabi` on the implementation address

The `get-contract-abi.sh` script does NOT auto-resolve proxies. Handle this manually:

```bash
PROXY_INFO=$(curl -s "https://api.etherscan.io/v2/api?chainid=1&module=contract&action=getsourcecode&address=0xPROXY&apikey=${ETHERSCAN_API_KEY}")
IMPL=$(echo "$PROXY_INFO" | jq -r '.result[0].Implementation // empty')

if [[ -n "$IMPL" ]]; then
  bash get-contract-abi.sh "$IMPL" ethereum
fi
```

## Get Transaction List

```bash
curl "https://api.etherscan.io/v2/api?chainid=1&module=account&action=txlist&address=0xADDR&startblock=0&endblock=99999999&sort=asc&apikey=KEY"
```

## Get Internal Transactions

```bash
curl "https://api.etherscan.io/v2/api?chainid=1&module=account&action=txlistinternal&txhash=0xHASH&apikey=KEY"
```

## Get Token Transfers

```bash
curl "https://api.etherscan.io/v2/api?chainid=1&module=account&action=tokentx&address=0xADDR&startblock=0&endblock=99999999&sort=asc&apikey=KEY"
```

## Rate Limits

- Free tier: 5 calls/second
- With API key: higher limits depending on plan
- Add `sleep 0.2` between batch calls to avoid throttling

## Decoding ABI Data

Once you have the ABI JSON, use it to:

1. **Match function selectors**: First 4 bytes of `input` → function name + parameter types
2. **Decode event logs**: `topic0` → event signature, remaining topics + data → parameter values
3. **Compute selectors**: `keccak256("functionName(type1,type2)")[:4]`

If `cast` (from Foundry) is available:
```bash
cast abi-decode "transfer(address,uint256)" 0x...input_data
cast 4byte-decode 0x...input_data
cast sig "transfer(address,uint256)"
```
