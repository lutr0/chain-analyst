#!/usr/bin/env bash
set +x
set -euo pipefail

# Usage: get-token-price.sh <coin_id> [currency] [date_dd-mm-yyyy]
# Fetches token price from CoinGecko API.
# Uses COINGECKO_API_KEY from .env if available (higher rate limits).
# Falls back to free tier (no key) which is rate-limited (~10-30 req/min).

COIN_ID="${1:?Usage: get-token-price.sh <coin_id> [currency] [date_dd-mm-yyyy]}"
CURRENCY="${2:-usd}"
DATE="${3:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SKILL_DIR/helpers.sh"

require_commands curl jq
load_env_safe ".env" ".env.local" "$SKILL_DIR/.env" "$SKILL_DIR/.env.local" || true

if [[ ! "$CURRENCY" =~ ^[a-z0-9-]+$ ]]; then
  echo "ERROR: Invalid currency '$CURRENCY'. Use CoinGecko currency ids like usd, eur, gbp." >&2
  exit 1
fi

AUTH_HEADER=()
if [[ -n "${COINGECKO_API_KEY:-}" ]]; then
  COINGECKO_BASE="https://pro-api.coingecko.com/api/v3"
  AUTH_HEADER=(--header "x-cg-pro-api-key: ${COINGECKO_API_KEY}")
else
  COINGECKO_BASE="https://api.coingecko.com/api/v3"
fi

if [[ -n "$DATE" ]]; then
  RESPONSE=$(curl_with_retries "${AUTH_HEADER[@]}" \
    "${COINGECKO_BASE}/coins/${COIN_ID}/history?date=${DATE}&localization=false" 2>&1) || {
    echo "ERROR: CoinGecko history request failed for $COIN_ID on $DATE" >&2
    exit 1
  }

  PRICE=$(echo "$RESPONSE" | jq -r ".market_data.current_price.${CURRENCY} // empty")
  MCAP=$(echo "$RESPONSE" | jq -r ".market_data.market_cap.${CURRENCY} // empty")

  if [[ -z "$PRICE" ]]; then
    echo "ERROR: No price data for $COIN_ID on $DATE in $CURRENCY" >&2
    echo "$RESPONSE" | jq -r '.error // empty' >&2
    exit 1
  fi

  jq -n \
    --arg coin "$COIN_ID" \
    --arg currency "$CURRENCY" \
    --arg date "$DATE" \
    --arg price "$PRICE" \
    --arg mcap "$MCAP" \
    '{
      coin: $coin,
      currency: $currency,
      date: $date,
      price: ($price | tonumber),
      market_cap: (if $mcap == "" then null else ($mcap | tonumber) end)
    }'
else
  RESPONSE=$(curl_with_retries "${AUTH_HEADER[@]}" \
    "${COINGECKO_BASE}/simple/price?ids=${COIN_ID}&vs_currencies=${CURRENCY}&include_market_cap=true&include_24hr_change=true" 2>&1) || {
    echo "ERROR: CoinGecko price request failed for $COIN_ID" >&2
    exit 1
  }

  PRICE=$(echo "$RESPONSE" | jq -r ".\"${COIN_ID}\".${CURRENCY} // empty")

  if [[ -z "$PRICE" ]]; then
    echo "ERROR: No price data for $COIN_ID in $CURRENCY" >&2
    echo "Hint: Use CoinGecko coin IDs like 'ethereum', 'bitcoin', 'usd-coin', 'tether'" >&2
    echo "Search: ${COINGECKO_BASE}/search?query=${COIN_ID}" >&2
    exit 1
  fi

  echo "$RESPONSE" | jq ".\"${COIN_ID}\""
fi
