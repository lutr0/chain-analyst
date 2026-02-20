# CoinGecko API Reference

Read this when you need token price data, coin ID lookups, or historical prices.

Docs: https://docs.coingecko.com/reference/introduction

## Table of Contents

- [Current Price](#current-price)
- [Historical Price (Specific Date)](#historical-price-specific-date)
- [Price Range (OHLC / Chart)](#price-range-ohlc--chart)
- [Search for Coin ID](#search-for-coin-id)
- [Token by Contract Address](#token-by-contract-address)
- [Common Coin IDs](#common-coin-ids)
- [Pricing from Block Timestamp](#pricing-from-block-timestamp)
- [Rate Limits](#rate-limits)

| Tier | Base URL | Auth Header |
|------|----------|-------------|
| Free (no key) | `https://api.coingecko.com/api/v3` | none |
| Demo/Pro (key) | `https://pro-api.coingecko.com/api/v3` | `x-cg-pro-api-key: <KEY>` |

Free tier: ~10-30 req/min, no key needed. With a key, higher limits apply.
The `get-token-price.sh` script auto-detects `COINGECKO_API_KEY` from `.env` and uses the Pro base URL when present.

## Current Price

```bash
curl "https://api.coingecko.com/api/v3/simple/price?ids=ethereum,bitcoin&vs_currencies=usd&include_market_cap=true&include_24hr_change=true"
```

Response:
```json
{
  "ethereum": {
    "usd": 3200.45,
    "usd_market_cap": 384000000000,
    "usd_24h_change": 2.5
  }
}
```

Multiple coin IDs: comma-separated in `ids` parameter.

## Historical Price (Specific Date)

```bash
curl "https://api.coingecko.com/api/v3/coins/ethereum/history?date=30-12-2024&localization=false"
```

Date format: `DD-MM-YYYY`

Response includes `market_data.current_price.<currency>`.

## Price Range (OHLC / Chart)

```bash
curl "https://api.coingecko.com/api/v3/coins/ethereum/market_chart?vs_currency=usd&days=30"
```

Returns `prices`, `market_caps`, `total_volumes` arrays of `[timestamp_ms, value]`.

## Search for Coin ID

```bash
curl "https://api.coingecko.com/api/v3/search?query=usdc"
```

Returns coins with matching names/symbols. Use the `id` field for other API calls.

## Token by Contract Address

```bash
curl "https://api.coingecko.com/api/v3/coins/ethereum/contract/0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
```

Platform IDs for contract lookups:
| Chain | Platform ID |
|-------|------------|
| Ethereum | ethereum |
| Base | base |
| Arbitrum | arbitrum-one |
| Optimism | optimistic-ethereum |
| Polygon | polygon-pos |
| BSC | binance-smart-chain |
| Avalanche | avalanche |
| Fantom | fantom |
| Gnosis | xdai |

## Common Coin IDs

| Token | CoinGecko ID |
|-------|-------------|
| ETH | ethereum |
| BTC | bitcoin |
| USDC | usd-coin |
| USDT | tether |
| DAI | dai |
| WETH | weth |
| WBTC | wrapped-bitcoin |
| LINK | chainlink |
| UNI | uniswap |
| AAVE | aave |
| ARB | arbitrum |
| OP | optimism |
| MATIC/POL | matic-network |
| SOL | solana |
| AVAX | avalanche-2 |
| BNB | binancecoin |
| STETH | staked-ether |

## Pricing from Block Timestamp

To price a token at the time of a transaction:

1. Get block timestamp from HyperSync response (`block.timestamp` in Unix seconds)
2. Convert to DD-MM-YYYY format
3. Call historical price endpoint

```bash
TIMESTAMP=1700000000
DATE=$(date -d @"$TIMESTAMP" +%d-%m-%Y 2>/dev/null || date -r "$TIMESTAMP" +%d-%m-%Y)
bash get-token-price.sh ethereum usd "$DATE"
```

## Rate Limits

- Free (no key): ~10-30 req/min, subject to change
- Demo key: 30 req/min, 10k req/month (free — sign up at https://www.coingecko.com/en/api/pricing)
- Pro/higher plans: increased limits
- Add `sleep 2` between calls in batch scenarios to stay within free tier limits
