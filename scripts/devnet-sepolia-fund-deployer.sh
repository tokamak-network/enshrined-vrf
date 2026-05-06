#!/usr/bin/env bash
set -euo pipefail

# Tops up the deployer (the address derived from PRIVATE_KEY) on the local L2
# devnet by sending ETH from the prefunded Hardhat #0 account. Idempotent: the
# script skips the transfer when the deployer already holds at least the
# requested amount.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT/devnet/sepolia/.env}"
WORKDIR="${DEVNET_WORKDIR:-$ROOT/.devnet/sepolia}"
MANIFEST="$WORKDIR/devnet.json"

if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

[ -f "$MANIFEST" ] || { echo "missing $MANIFEST; run prepare/start first" >&2; exit 1; }
command -v cast >/dev/null 2>&1 || { echo "missing required command: cast" >&2; exit 1; }
command -v jq   >/dev/null 2>&1 || { echo "missing required command: jq"   >&2; exit 1; }
: "${PRIVATE_KEY:?PRIVATE_KEY is required to derive the deployer address}"

L2_CHAIN_ID="$(jq -r '.l2ChainId' "$MANIFEST")"
MANIFEST_L2_RPC_URL="$(jq -r '.l2RpcUrl // "http://127.0.0.1:9545"' "$MANIFEST")"
L2_RPC_HOST="${L2_RPC_HOST:-127.0.0.1}"
L2_RPC_PORT="${L2_RPC_PORT:-$(printf '%s' "$MANIFEST_L2_RPC_URL" | sed -E 's#^https?://[^:/]+:([0-9]+).*$#\1#')}"
if [ "$L2_RPC_PORT" = "$MANIFEST_L2_RPC_URL" ]; then
  L2_RPC_PORT=9545
fi
L2_RPC_URL="${L2_RPC_URL:-http://$L2_RPC_HOST:$L2_RPC_PORT}"

# First Hardhat account, prefunded by fundDevAccounts=true at L2 genesis.
FUNDER_KEY="${L2_TEST_PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
FUND_AMOUNT_ETH="${FUND_DEPLOYER_ETH:-1000}"

DEPLOYER_ADDR="$(cast wallet address --private-key "$PRIVATE_KEY")"
FUND_WEI="$(cast to-wei "$FUND_AMOUNT_ETH" ether)"

wait_chain() {
  for _ in $(seq 1 60); do
    if got="$("$ROOT/scripts/devnet-rpc-chain-id.sh" "$L2_RPC_URL" 2>/dev/null)"; then
      [ "$got" = "$L2_CHAIN_ID" ] && return 0
    fi
    sleep 1
  done
  echo "L2 RPC is not ready at $L2_RPC_URL" >&2
  exit 1
}
wait_chain

# Refuse to send when the sequencer hasn't started building blocks; otherwise the
# transaction sits in mempool with no receipt.
for _ in $(seq 1 60); do
  block="$(cast block-number --rpc-url "$L2_RPC_URL" 2>/dev/null || echo 0)"
  [ "$block" -gt 0 ] && break
  sleep 1
done
if [ "${block:-0}" -le 0 ]; then
  echo "sequencer is not producing blocks; check op-node.log" >&2
  exit 1
fi

current_balance="$(cast balance "$DEPLOYER_ADDR" --rpc-url "$L2_RPC_URL")"
echo "[fund] deployer:        $DEPLOYER_ADDR"
echo "[fund] current balance: $(cast from-wei "$current_balance") ETH"
echo "[fund] target balance:  $FUND_AMOUNT_ETH ETH"

# Idempotent skip when the deployer already has enough.
if cast --to-dec "$current_balance" >/dev/null 2>&1; then :; fi
if [ "$(printf '%s\n%s\n' "$current_balance" "$FUND_WEI" | sort -n | head -1)" = "$FUND_WEI" ]; then
  echo "[fund] already at or above target — skipping transfer"
  exit 0
fi

deficit_wei="$(python3 -c "print($FUND_WEI - $current_balance)")"

echo "[fund] sending $(cast from-wei "$deficit_wei") ETH from Hardhat #0"
send_json="$(cast send --json \
  --rpc-url "$L2_RPC_URL" \
  --private-key "$FUNDER_KEY" \
  --value "$deficit_wei" \
  "$DEPLOYER_ADDR")"

status="$(echo "$send_json" | jq -r '.status')"
if [ "$status" != "0x1" ] && [ "$status" != "1" ]; then
  echo "fund transfer transaction failed (status=$status)" >&2
  echo "$send_json" >&2
  exit 1
fi

new_balance="$(cast balance "$DEPLOYER_ADDR" --rpc-url "$L2_RPC_URL")"
echo "[fund] ok"
echo "  tx:           $(echo "$send_json" | jq -r '.transactionHash')"
echo "  block:        $(echo "$send_json" | jq -r '.blockNumber')"
echo "  new balance:  $(cast from-wei "$new_balance") ETH"
