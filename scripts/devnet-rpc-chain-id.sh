#!/usr/bin/env bash
set -euo pipefail

RPC_URL="${1:?usage: devnet-rpc-chain-id.sh <rpc-url>}"
RPC_TIMEOUT="${RPC_TIMEOUT:-20}"
RPC_DOH_URL="${RPC_DOH_URL:-https://dns.google/dns-query}"

hex_to_dec() {
  local value="${1#0x}"
  printf '%d\n' "$((16#$value))"
}

curl_error=""
try_curl_chain_id() {
  local response
  local chain_id_hex
  local rpc_error
  if response="$(curl -sS -m "$RPC_TIMEOUT" "$@" \
    -H 'content-type: application/json' \
    --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' \
    "$RPC_URL" 2>&1)"; then
    chain_id_hex="$(printf '%s' "$response" | jq -r '.result // empty' 2>/dev/null || true)"
    if [ -n "$chain_id_hex" ] && [ "$chain_id_hex" != "null" ]; then
      hex_to_dec "$chain_id_hex"
      return 0
    fi
    rpc_error="$(printf '%s' "$response" | jq -r '.error.message // empty' 2>/dev/null || true)"
    curl_error="${rpc_error:-RPC response did not include eth_chainId result}"
  else
    curl_error="$response"
  fi
  return 1
}

if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  case "$RPC_URL" in
    http://127.0.0.1:*|http://localhost:*|http://0.0.0.0:*|http://[::1]:*)
      try_curl_chain_id && exit 0
      [ -n "$RPC_DOH_URL" ] && try_curl_chain_id --doh-url "$RPC_DOH_URL" && exit 0
      ;;
    *)
      [ -n "$RPC_DOH_URL" ] && try_curl_chain_id --doh-url "$RPC_DOH_URL" && exit 0
      try_curl_chain_id && exit 0
      ;;
  esac
fi

if command -v cast >/dev/null 2>&1; then
  if chain_id="$(cast chain-id --rpc-url "$RPC_URL" 2>/dev/null)"; then
    printf '%s\n' "$chain_id"
    exit 0
  fi
fi

if [ -n "$curl_error" ]; then
  echo "could not read chain-id from RPC URL: $curl_error" >&2
else
  echo "could not read chain-id from RPC URL" >&2
fi
exit 1
