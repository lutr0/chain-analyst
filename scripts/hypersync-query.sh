#!/usr/bin/env bash
set +x
set -euo pipefail

# Queries HyperSync and paginates automatically until all matching data is retrieved.
# Each page is a server-side batch (~5s execution window). The script follows next_block
# until the chain tip is reached or max_pages is hit.
# Set max_pages=0 for unlimited. Default: 0 (fetch everything).
# API token is loaded from .env — never printed or logged.

NETWORK="${1:?Usage: hypersync-query.sh <network|chain_id> <query.json> [max_pages] [stream|aggregate]}"
QUERY_FILE="${2:?Usage: hypersync-query.sh <network|chain_id> <query.json> [max_pages] [stream|aggregate]}"
MAX_PAGES="${3:-0}"
OUTPUT_MODE="${4:-stream}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SKILL_DIR/helpers.sh"

require_commands curl jq

if [[ ! "$MAX_PAGES" =~ ^(0|[1-9][0-9]{0,8})$ ]]; then
  echo 'ERROR: max_pages must be an integer from 0 through 999999999.' >&2
  exit 1
fi

if [[ "$OUTPUT_MODE" != "stream" && "$OUTPUT_MODE" != "aggregate" ]]; then
  echo "ERROR: Invalid output mode '$OUTPUT_MODE'. Use 'stream' or 'aggregate'." >&2
  exit 1
fi

if [[ ! -f "$QUERY_FILE" ]]; then
  echo "ERROR: Query file not found: $QUERY_FILE" >&2
  exit 1
fi

if ! jq empty "$QUERY_FILE" >/dev/null 2>&1; then
  echo "ERROR: Query file is not valid JSON: $QUERY_FILE" >&2
  exit 1
fi

load_env_safe ".env" ".env.local" "$SKILL_DIR/.env" "$SKILL_DIR/.env.local" || true

if [[ -z "${HYPERSYNC_API_TOKEN:-}" ]]; then
  echo "ERROR: HYPERSYNC_API_TOKEN not set. Add it to .env in the workspace root." >&2
  exit 1
fi

BASE_URL=$(resolve_hypersync_url "$NETWORK")
QUERY=$(cat "$QUERY_FILE")

page=0
next_block=""
AGGREGATE_DIR=""

if [[ "$OUTPUT_MODE" == "aggregate" ]]; then
  AGGREGATE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/chain-analyst-hypersync-XXXXXX")
  trap 'rm -rf "$AGGREGATE_DIR"' EXIT
fi

while (( MAX_PAGES == 0 || page < MAX_PAGES )); do
  if [[ -n "$next_block" ]]; then
    QUERY=$(echo "$QUERY" | jq --argjson nb "$next_block" '.from_block = $nb')
  fi

  RESPONSE=$(curl_with_retries \
    --request POST \
    --url "${BASE_URL}/query" \
    --header 'Content-Type: application/json' \
    --header "Authorization: Bearer ${HYPERSYNC_API_TOKEN}" \
    --data "$QUERY" 2>&1) || {
    echo "ERROR: HyperSync query failed (page $page)" >&2
    redact_secret "$RESPONSE" "$HYPERSYNC_API_TOKEN" >&2
    exit 1
  }

  # Provider-controlled strings must never reach Bash arithmetic evaluation.
  if ! printf '%s' "$RESPONSE" | jq -e '
    def block: type == "number" and . >= 0 and . <= 9007199254740991 and . == floor;
    type == "object" and (.next_block | . == null or block)
      and (.archive_height | . == null or block)' >/dev/null; then
    echo 'ERROR: Invalid HyperSync pagination metadata.' >&2
    exit 1
  fi

  if [[ "$OUTPUT_MODE" == "aggregate" ]]; then
    printf '%s\n' "$RESPONSE" > "$AGGREGATE_DIR/page-${page}.json"
  else
    echo "$RESPONSE"
  fi
  (( ++page ))

  next_block=$(echo "$RESPONSE" | jq -r '.next_block // empty')
  archive_height=$(echo "$RESPONSE" | jq -r '.archive_height // empty')

  has_data=$(echo "$RESPONSE" | jq '
    [.data[]? |
      ((.blocks // []) | length > 0) or
      ((.transactions // []) | length > 0) or
      ((.logs // []) | length > 0) or
      ((.traces // []) | length > 0)
    ] | any
  ')

  if [[ "$has_data" == "false" ]]; then
    break
  fi

  if [[ -n "$next_block" && -n "$archive_height" ]]; then
    if (( next_block >= archive_height )); then
      break
    fi
  fi
done

if [[ "$OUTPUT_MODE" == "aggregate" ]]; then
  if compgen -G "$AGGREGATE_DIR/page-*.json" >/dev/null; then
    jq -s '{
      data: (map(.data // []) | add // []),
      archive_height: (map(.archive_height // empty) | last // null),
      next_block: (map(.next_block // empty) | last // null),
      page_count: length
    }' "$AGGREGATE_DIR"/page-*.json
  else
    jq -n '{data: [], archive_height: null, next_block: null, page_count: 0}'
  fi
fi
