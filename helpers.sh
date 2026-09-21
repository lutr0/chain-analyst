#!/usr/bin/env bash

: "${CURL_RETRY:=3}"
: "${CURL_RETRY_DELAY:=1}"
: "${CURL_CONNECT_TIMEOUT:=10}"
: "${CURL_MAX_TIME:=45}"

trim_whitespace() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

require_commands() {
  local missing=()
  local cmd
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    echo "ERROR: Missing required command(s): ${missing[*]}" >&2
    exit 1
  fi
}

load_env_safe() {
  local env_file line key value
  local loaded=0
  for env_file in "$@"; do
    [[ -f "$env_file" ]] || continue

    loaded=1

    while IFS= read -r line || [[ -n "$line" ]]; do
      line="$(trim_whitespace "$line")"
      [[ -z "$line" || "${line:0:1}" == "#" ]] && continue

      if [[ "$line" == export\ * ]]; then
        line="${line#export }"
      fi

      [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || continue

      key="${line%%=*}"
      # Workspace files configure this skill, never the shell or its executables.
      case "$key" in
        HYPERSYNC_API_TOKEN|ETHERSCAN_API_KEY|COINGECKO_API_KEY|TYPESAFE_API_KEY|TYPESAFE_DEFAULT_MODEL) ;;
        *) continue ;;
      esac
      value="${line#*=}"
      value="$(trim_whitespace "$value")"

      if [[ ${#value} -ge 2 ]]; then
        if [[ "$value" == \"*\" && "$value" == *\" ]]; then
          value="${value:1:${#value}-2}"
        elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
          value="${value:1:${#value}-2}"
        fi
      fi

      export "$key=$value"
    done < "$env_file"
  done

  return $(( loaded == 0 ))
}

curl_with_retries() {
  curl -q --globoff --proto '=https' --max-redirs 0 --silent --show-error --fail-with-body \
    --retry "$CURL_RETRY" \
    --retry-delay "$CURL_RETRY_DELAY" \
    --connect-timeout "$CURL_CONNECT_TIMEOUT" \
    --max-time "$CURL_MAX_TIME" \
    "$@"
}

redact_secret() {
  local text="$1"
  local secret="${2:-}"
  if [[ -z "$secret" ]]; then
    printf '%s' "$text"
  else
    printf '%s' "${text//$secret/***REDACTED***}"
  fi
}

normalize_network_name() {
  local network="${1,,}"
  if [[ ! "$network" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]; then
    printf '%s\n' 'ERROR: Network must be a DNS label, not a URL or path.' >&2
    return 1
  fi
  case "$network" in
    eth|mainnet|1) echo "ethereum" ;;
    op|10) echo "optimism" ;;
    matic|137) echo "polygon" ;;
    *) echo "$network" ;;
  esac
}

# HyperSync: https://{name}.hypersync.xyz (ethereum uses "eth" subdomain)
resolve_hypersync_url() {
  local net
  net="$(normalize_network_name "$1")" || return 1
  case "$net" in
    ethereum) echo "https://eth.hypersync.xyz" ;;
    *) echo "https://${net}.hypersync.xyz" ;;
  esac
}

# RPC: https://{name}.drpc.org (ethereum uses "eth" subdomain)
resolve_rpc_url() {
  local net
  net="$(normalize_network_name "$1")" || return 1
  case "$net" in
    ethereum) echo "https://eth.drpc.org" ;;
    *) echo "https://${net}.drpc.org" ;;
  esac
}

# Top-5 chain IDs hardcoded; pass numeric chain ID for others
resolve_chain_id() {
  local net
  net="$(normalize_network_name "$1")" || return 1
  case "$net" in
    ethereum) echo "1" ;;
    base) echo "8453" ;;
    arbitrum) echo "42161" ;;
    optimism) echo "10" ;;
    polygon) echo "137" ;;
    *)
      if [[ "$net" =~ ^[0-9]+$ ]]; then
        echo "$net"
      else
        echo ""
      fi
      ;;
  esac
}

hex_to_dec() {
  local hex="${1#0x}"
  if [[ -z "$hex" ]]; then
    echo "0"
    return 0
  fi

  if command -v bc >/dev/null 2>&1; then
    echo "ibase=16; ${hex^^}" | bc
    return 0
  fi

  if [[ ${#hex} -le 16 ]]; then
    printf '%d\n' "$((16#$hex))"
    return 0
  fi

  printf '0x%s\n' "$hex"
}

# Convert address to topic format (left-padded to 32 bytes)
addr_to_topic() {
  local addr="${1#0x}"
  printf "0x%064s" "$addr" | tr ' ' '0'
}

# Convert wei to human readable with decimals
wei_to_human() {
  local wei="$1"
  local decimals="${2:-18}"
  echo "scale=$decimals; $wei / 10^$decimals" | bc -l
}

# Get current block number
get_latest_block() {
  local network="${1:-ethereum}"
  local url
  url="$(resolve_hypersync_url "$network")"
  curl_with_retries "$url/height" | jq -r '.height'
}

# Common token decimals
declare -A TOKEN_DECIMALS=(
  ["USDC"]=6
  ["USDT"]=6
  ["DAI"]=18
  ["WETH"]=18
  ["WBTC"]=8
)

# Common event signatures
declare -A EVENT_SIGS=(
  ["Transfer"]="0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
  ["Approval"]="0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925"
  ["Swap_V2"]="0xd78ad95fa46c994b6551d0da85fc275fe613ce37657fb8d5e3d130840159d822"
  ["Swap_V3"]="0xc42079f94a6350d7e6235f29174924f928cc2ac818eb64fed8004e115fbcca67"
  ["PoolCreated"]="0x783cca1c0412dd0d695e784568c96da2e9c22ff989357a2e8b1d9b2b4e6b7118"
)

# Pretty print JSON with syntax highlighting if available
pretty_json() {
  if command -v jq >/dev/null 2>&1; then
    jq -C .
  else
    cat
  fi
}

export -f trim_whitespace require_commands load_env_safe curl_with_retries redact_secret
is_network_token() {
  local resolved
  resolved="$(resolve_chain_id "$(normalize_network_name "$1")")"
  [[ -n "$resolved" ]]
}

export -f normalize_network_name resolve_hypersync_url resolve_rpc_url resolve_chain_id is_network_token
export -f hex_to_dec addr_to_topic wei_to_human get_latest_block pretty_json
