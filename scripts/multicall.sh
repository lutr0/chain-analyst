#!/usr/bin/env bash
set -euo pipefail

# Usage: multicall.sh <network> <calls.json>
# Batch multiple contract calls in a single RPC request using viem's multicall
# Example calls.json:
# [
#   { "contract": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", "method": "balanceOf", "args": ["0xAddress"] },
#   { "contract": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", "method": "decimals" },
#   { "contract": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", "method": "symbol" }
# ]

NETWORK="${1:?Usage: multicall.sh <network> <calls.json>}"
CALLS_FILE="${2:?Usage: multicall.sh <network> <calls.json>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SKILL_DIR/helpers.sh"

require_commands node jq

if [[ ! -f "$CALLS_FILE" ]]; then
  echo "ERROR: Calls file not found: $CALLS_FILE" >&2
  exit 1
fi

if ! jq -e 'type == "array"' "$CALLS_FILE" >/dev/null 2>&1; then
  echo "ERROR: Calls file must be a JSON array: $CALLS_FILE" >&2
  exit 1
fi

NETWORK="$(normalize_network_name "$NETWORK")"
RPC_URL="$(resolve_rpc_url "$NETWORK")"

if ! node --input-type=module -e "import('viem').then(() => process.exit(0)).catch(() => process.exit(1))" >/dev/null 2>&1; then
  echo "ERROR: viem is required for multicall. Install project dependencies (pnpm install)." >&2
  exit 1
fi

NETWORK="$NETWORK" RPC_URL="$RPC_URL" node "$SCRIPT_DIR/multicall-viem.mjs" "$CALLS_FILE"
