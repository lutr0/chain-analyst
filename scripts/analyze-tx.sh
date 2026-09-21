#!/usr/bin/env bash
set +x
set -euo pipefail

# Usage: analyze-tx.sh <tx_hash> [network]
# Fetches a single transaction with its logs and traces from HyperSync,
# then fetches ABIs for all involved contracts.
# All secrets loaded from .env — never printed.

TX_HASH="${1:?Usage: analyze-tx.sh <tx_hash> [network]}"
NETWORK="${2:-ethereum}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TMPDIR="${TMPDIR:-/tmp}"

source "$SKILL_DIR/helpers.sh"

require_commands curl jq
load_env_safe ".env" ".env.local" "$SKILL_DIR/.env" "$SKILL_DIR/.env.local" || true

if [[ ! "$TX_HASH" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
  echo "ERROR: Invalid transaction hash: $TX_HASH" >&2
  exit 1
fi

if [[ -z "${HYPERSYNC_API_TOKEN:-}" ]]; then
  echo "ERROR: HYPERSYNC_API_TOKEN not set in .env" >&2
  exit 1
fi

BASE_URL=$(resolve_hypersync_url "$NETWORK")

echo "--- Step 1: Fetching transaction from HyperSync ($NETWORK) ---" >&2

TX_QUERY=$(cat <<EOF
{
  "from_block": 0,
  "transactions": [{"hash": ["${TX_HASH}"]}],
  "include_all_blocks": false,
  "field_selection": {
    "block": ["number", "timestamp", "hash", "gas_used", "base_fee_per_gas"],
    "log": ["block_number", "log_index", "transaction_index", "transaction_hash", "data", "address", "topic0", "topic1", "topic2", "topic3"],
    "transaction": ["block_number", "transaction_index", "hash", "from", "to", "value", "input", "gas", "gas_used", "gas_price", "effective_gas_price", "status", "contract_address", "nonce"],
    "trace": ["block_number", "transaction_hash", "from", "to", "value", "input", "output", "gas", "gas_used", "type", "call_type", "trace_address", "error", "subtraces"]
  },
  "join_mode": "JoinAll"
}
EOF
)

RESULT=$(curl_with_retries \
  --request POST \
  --url "${BASE_URL}/query" \
  --header 'Content-Type: application/json' \
  --header "Authorization: Bearer ${HYPERSYNC_API_TOKEN}" \
  --data "$TX_QUERY" 2>&1) || {
  echo "ERROR: HyperSync query failed" >&2
  redact_secret "$RESULT" "$HYPERSYNC_API_TOKEN" >&2
  exit 1
}

TX_COUNT=$(echo "$RESULT" | jq '[.data[]?.transactions[]?] | length')
LOG_COUNT=$(echo "$RESULT" | jq '[.data[]?.logs[]?] | length')
TRACE_COUNT=$(echo "$RESULT" | jq '[.data[]?.traces[]?] | length')

echo "Found: $TX_COUNT transaction(s), $LOG_COUNT log(s), $TRACE_COUNT trace(s)" >&2

if [[ "$TX_COUNT" -eq 0 ]]; then
  echo "ERROR: Transaction $TX_HASH not found on $NETWORK" >&2
  exit 1
fi

CONTRACTS=$(echo "$RESULT" | jq -r '
  [
    (.data[]?.transactions[]? | .to // empty),
    (.data[]?.logs[]? | .address // empty),
    (.data[]?.traces[]? | .to // empty)
  ] | map(select(. != null and . != ""))
  | if all(.[]; type == "string" and test("^0x[0-9a-fA-F]{40}$"))
    then unique | .[] else error("Invalid contract address in HyperSync response") end
')

echo "--- Step 2: Unique contracts found ---" >&2
echo "$CONTRACTS" | while read -r addr; do
  echo "  $addr" >&2
done

echo "--- Step 3: Fetching ABIs ---" >&2
ABI_DIR=$(mktemp -d "$TMPDIR/chain-analyst-abis-XXXXXXXX")
trap 'rm -rf "$ABI_DIR"' EXIT

echo "$CONTRACTS" | while read -r addr; do
  if [[ -n "$addr" ]]; then
    ABI_FILE="$ABI_DIR/${addr}.json"
    if bash "$SCRIPT_DIR/get-contract-abi.sh" "$addr" "$NETWORK" > "$ABI_FILE" 2>/dev/null; then
      echo "  ABI fetched: $addr" >&2
    else
      echo "  ABI not available: $addr (unverified or proxy)" >&2
      rm -f "$ABI_FILE"
    fi
  fi
done

echo "--- Step 4: Output ---" >&2
echo ""

FLAT_DATA=$(echo "$RESULT" | jq '{
  blocks: [.data[]?.blocks[]?],
  transactions: [.data[]?.transactions[]?],
  logs: [.data[]?.logs[]?],
  traces: [.data[]?.traces[]?]
}')

jq -n \
  --argjson data "$FLAT_DATA" \
  --arg network "$NETWORK" \
  --arg tx_hash "$TX_HASH" \
  --arg abi_dir "$ABI_DIR" \
  --argjson archive_height "$(echo "$RESULT" | jq '.archive_height')" \
  '{
    network: $network,
    tx_hash: $tx_hash,
    abi_dir: $abi_dir,
    data: $data,
    archive_height: $archive_height
  }'
