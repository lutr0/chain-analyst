#!/usr/bin/env bash
set -euo pipefail

# Usage: query-contract.sh <method> <contract> [args...] [network]
# Queries current contract state via RPC
# Uses simplest available tool: curl → cast → viem
# Examples:
#   query-contract.sh decimals 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913 base
#   query-contract.sh balanceOf 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913 0xYourAddress base
#   query-contract.sh symbol 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913 base

METHOD="${1:?Usage: query-contract.sh <method> <contract> [args...] [network]}"
CONTRACT="${2:?Usage: query-contract.sh <method> <contract> [args...] [network]}"

ARGS=("${@:3}")
NETWORK="base"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SKILL_DIR/helpers.sh"

require_commands curl jq

if [[ ! "$CONTRACT" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
  jq -n --arg error "Invalid contract address: $CONTRACT" '{error: $error}'
  exit 1
fi

if (( ${#ARGS[@]} > 0 )); then
  LAST="${ARGS[-1]}"
  if is_network_token "$LAST"; then
    NETWORK="$(normalize_network_name "$LAST")"
    ARGS=("${ARGS[@]:0:${#ARGS[@]}-1}")
  fi
fi

RPC_URL="$(resolve_rpc_url "$NETWORK")"

resolve_cast_signature() {
  local method="$1"
  case "$method" in
    balanceOf) echo "balanceOf(address)(uint256)" ;;
    allowance) echo "allowance(address,address)(uint256)" ;;
    ownerOf) echo "ownerOf(uint256)(address)" ;;
    tokenURI) echo "tokenURI(uint256)(string)" ;;
    owner) echo "owner()(address)" ;;
    decimals) echo "decimals()(uint8)" ;;
    totalSupply) echo "totalSupply()(uint256)" ;;
    symbol) echo "symbol()(string)" ;;
    name) echo "name()(string)" ;;
    *)
      if [[ "$method" == *"("*")"* ]]; then
        echo "$method"
      else
        echo ""
      fi
      ;;
  esac
}

# Simple methods that need no arguments can use curl directly
if [[ ${#ARGS[@]} -eq 0 ]] && [[ "$METHOD" =~ ^(decimals|symbol|name|totalSupply|owner)$ ]]; then
  SELECTOR=$(case "$METHOD" in
    decimals) echo "0x313ce567" ;;
    symbol) echo "0x95d89b41" ;;
    name) echo "0x06fdde03" ;;
    totalSupply) echo "0x18160ddd" ;;
    owner) echo "0x8da5cb5b" ;;
  esac)

  RESULT=$(curl_with_retries -X POST "$RPC_URL" \
    -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_call\",\"params\":[{\"to\":\"$CONTRACT\",\"data\":\"$SELECTOR\"},\"latest\"],\"id\":1}" | \
    jq -r '.result // .error.message // "Error"')

  if [[ "$RESULT" == "0x"* ]]; then
    case "$METHOD" in
      decimals|totalSupply)
        DECIMAL_VALUE=$(hex_to_dec "$RESULT")
        if [[ "$DECIMAL_VALUE" =~ ^[0-9]+$ ]]; then
          jq -n --arg result "$DECIMAL_VALUE" --arg method "$METHOD" --arg contract "$CONTRACT" \
            '{result: ($result | tonumber), method: $method, contract: $contract}'
        else
          jq -n --arg result "$DECIMAL_VALUE" --arg method "$METHOD" --arg contract "$CONTRACT" \
            '{result: $result, method: $method, contract: $contract}'
        fi
        ;;
      symbol|name)
        if ! command -v xxd >/dev/null 2>&1; then
          echo '{"error": "xxd is required to decode string responses for symbol/name"}'
          exit 1
        fi
        HEX="${RESULT:2}"
        if [[ ${#HEX} -gt 128 ]]; then
          TEXT=$(echo "${HEX:128}" | sed 's/00*$//' | xxd -r -p 2>/dev/null || echo "")
          jq -n --arg result "$TEXT" --arg method "$METHOD" --arg contract "$CONTRACT" \
            '{result: $result, method: $method, contract: $contract}'
        else
          jq -n '{error: "Invalid string encoding"}'
        fi
        ;;
      owner)
        ADDRESS_HEX="${RESULT#0x}"
        if [[ ${#ADDRESS_HEX} -ge 40 ]]; then
          OWNER_ADDR="0x${ADDRESS_HEX: -40}"
          jq -n --arg result "$OWNER_ADDR" --arg method "$METHOD" --arg contract "$CONTRACT" \
            '{result: $result, method: $method, contract: $contract}'
        else
          jq -n '{error: "Invalid address encoding"}'
        fi
        ;;
    esac
  else
    jq -n --arg error "$RESULT" '{error: $error}'
  fi
  exit 0
fi

# For complex methods, try cast if available
if command -v cast >/dev/null 2>&1; then
  CAST_SIGNATURE="$(resolve_cast_signature "$METHOD")"
  if [[ -n "$CAST_SIGNATURE" ]] && RESULT=$(cast call "$CONTRACT" "$CAST_SIGNATURE" "${ARGS[@]}" --rpc-url "$RPC_URL" 2>&1); then
    jq -n --arg result "$RESULT" --arg method "$METHOD" --arg contract "$CONTRACT" \
      --argjson args "$(printf '%s\n' "${ARGS[@]}" | jq -R . | jq -s .)" \
      '{result: $result, method: $method, contract: $contract, args: $args}'
    exit 0
  fi
fi

if command -v node >/dev/null 2>&1; then
  if ! node --input-type=module -e "import('viem').then(() => process.exit(0)).catch(() => process.exit(1))" >/dev/null 2>&1; then
    jq -n '{error: "Method requires viem for node fallback. Install project dependencies (pnpm install) or use cast with a full function signature."}'
    exit 1
  fi

  NETWORK="$NETWORK" RPC_URL="$RPC_URL" node "$SCRIPT_DIR/query-contract-viem.mjs" "$METHOD" "$CONTRACT" "${ARGS[@]}"
  exit $?
fi

jq -n '{error: "Method requires cast (Foundry) or node+viem. For cast, pass a full signature for custom methods (e.g. \"myMethod(uint256)(address)\")."}'
exit 1
