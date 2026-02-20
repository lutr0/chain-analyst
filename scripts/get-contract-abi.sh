#!/usr/bin/env bash
set -euo pipefail

# Usage: get-contract-abi.sh <contract_address> [network]
# Fetches verified contract ABI from Etherscan API V2 (unified multichain endpoint).
# A single ETHERSCAN_API_KEY works for all chains.
# API key loaded from .env — never printed or logged.

ADDRESS="${1:?Usage: get-contract-abi.sh <contract_address> [network]}"
NETWORK="${2:-ethereum}"

ETHERSCAN_V2_BASE="https://api.etherscan.io/v2/api"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SKILL_DIR/helpers.sh"

require_commands curl jq
load_env_safe ".env" ".env.local" "$SKILL_DIR/.env" "$SKILL_DIR/.env.local" || true

if [[ ! "$ADDRESS" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
  echo "ERROR: Invalid contract address: $ADDRESS" >&2
  exit 1
fi

API_KEY="${ETHERSCAN_API_KEY:-}"

if [[ -z "$API_KEY" ]]; then
  echo "ERROR: ETHERSCAN_API_KEY not set. Add it to .env in the workspace root." >&2
  exit 1
fi

CHAIN_ID=$(resolve_chain_id "$NETWORK")

if [[ -z "$CHAIN_ID" ]]; then
  echo "ERROR: Cannot resolve chain ID for network '$NETWORK'." >&2
  echo "Use a known name (ethereum, base, arbitrum, ...) or a numeric chain ID." >&2
  exit 1
fi

RESPONSE=$(curl_with_retries \
  "${ETHERSCAN_V2_BASE}?chainid=${CHAIN_ID}&module=contract&action=getabi&address=${ADDRESS}&apikey=${API_KEY}" 2>&1) || {
  echo "ERROR: Etherscan API V2 request failed for $ADDRESS on $NETWORK (chain $CHAIN_ID)" >&2
  redact_secret "$RESPONSE" "$API_KEY" >&2
  exit 1
}

STATUS=$(echo "$RESPONSE" | jq -r '.status // "0"')
MESSAGE=$(echo "$RESPONSE" | jq -r '.message // "Unknown error"')

if [[ "$STATUS" != "1" ]]; then
  RESULT_MSG=$(echo "$RESPONSE" | jq -r '.result // ""')
  RESULT_MSG=$(redact_secret "$RESULT_MSG" "$API_KEY")
  echo "ERROR: Etherscan returned status=$STATUS: $MESSAGE" >&2
  if [[ -n "$RESULT_MSG" ]]; then
    echo "Detail: $RESULT_MSG" >&2
  fi
  echo "Contract $ADDRESS on $NETWORK (chain $CHAIN_ID) may not be verified." >&2
  exit 1
fi

echo "$RESPONSE" | jq -r '.result'
