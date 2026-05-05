#!/usr/bin/env bash
set -euo pipefail

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

if [ ! -f "$MANIFEST" ]; then
  echo "missing $MANIFEST; run ./scripts/devnet-sepolia-prepare.sh first" >&2
  exit 1
fi

command -v jq >/dev/null 2>&1 || {
  echo "missing required command: jq" >&2
  exit 1
}
command -v cast >/dev/null 2>&1 || {
  echo "missing required command: cast" >&2
  exit 1
}

require_file() {
  [ -f "$1" ] || {
    echo "missing required file: $1" >&2
    exit 1
  }
}

require_exe() {
  [ -x "$1" ] || {
    echo "missing executable: $1; run ./scripts/devnet-build.sh" >&2
    exit 1
  }
}

is_running() {
  [ -f "$1" ] && kill -0 "$(cat "$1")" >/dev/null 2>&1
}

wait_rpc() {
  local rpc_url="$1"
  local expected_chain_id="$2"
  local label="$3"
  for _ in $(seq 1 60); do
    if got="$("$ROOT/scripts/devnet-rpc-chain-id.sh" "$rpc_url" 2>/dev/null)"; then
      if [ "$got" = "$expected_chain_id" ]; then
        return 0
      fi
    fi
    sleep 1
  done
  echo "$label did not become ready at $rpc_url" >&2
  return 1
}

L1_RPC_URL="${L1_RPC_URL:-$(jq -r '.l1RpcUrl' "$MANIFEST")}"
L1_BEACON_URL="${L1_BEACON_URL:-$(jq -r '.l1BeaconUrl // ""' "$MANIFEST")}"
L2_CHAIN_ID="$(jq -r '.l2ChainId' "$MANIFEST")"
GENESIS="$(jq -r '.genesis' "$MANIFEST")"
ROLLUP="$(jq -r '.rollup' "$MANIFEST")"
JWT="$(jq -r '.jwt' "$MANIFEST")"
GETH_DATADIR="$(jq -r '.gethDatadir' "$MANIFEST")"
L2_RPC_PORT="${L2_RPC_PORT:-9545}"
L2_WS_PORT="${L2_WS_PORT:-9546}"
L2_AUTHRPC_PORT="${L2_AUTHRPC_PORT:-9551}"
OP_NODE_RPC_PORT="${OP_NODE_RPC_PORT:-7545}"
L2_RPC_ADDR="${L2_RPC_ADDR:-127.0.0.1}"
L2_WS_ADDR="${L2_WS_ADDR:-127.0.0.1}"
L2_AUTHRPC_ADDR="${L2_AUTHRPC_ADDR:-127.0.0.1}"
OP_NODE_RPC_ADDR="${OP_NODE_RPC_ADDR:-127.0.0.1}"
L2_RPC_HOST="${L2_RPC_HOST:-127.0.0.1}"
L2_WS_HOST="${L2_WS_HOST:-$L2_RPC_HOST}"
L2_AUTHRPC_HOST="${L2_AUTHRPC_HOST:-127.0.0.1}"
OP_NODE_RPC_HOST="${OP_NODE_RPC_HOST:-127.0.0.1}"
L2_RPC_URL="${L2_RPC_URL:-http://$L2_RPC_HOST:$L2_RPC_PORT}"
L2_AUTHRPC_URL="${L2_AUTHRPC_URL:-http://$L2_AUTHRPC_HOST:$L2_AUTHRPC_PORT}"
VRF_MODE="${VRF_MODE:-local}"
VRF_SK="${VRF_SK:-0xc9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721}"
L1_RPC_KIND="${L1_RPC_KIND:-standard}"
SEQUENCER_L1_CONFS="${SEQUENCER_L1_CONFS:-1}"
VERIFIER_L1_CONFS="${VERIFIER_L1_CONFS:-0}"

if got_l1_chain_id="$("$ROOT/scripts/devnet-rpc-chain-id.sh" "$L1_RPC_URL" 2>/dev/null)"; then
  if [ "$got_l1_chain_id" != "11155111" ]; then
    echo "refusing to start: L1_RPC_URL chain-id is $got_l1_chain_id, expected Sepolia 11155111" >&2
    exit 1
  fi
else
  echo "could not read L1 chain-id from L1_RPC_URL; refusing to start" >&2
  exit 1
fi

require_file "$GENESIS"
require_file "$ROLLUP"
require_file "$JWT"
require_exe "$ROOT/bin/geth"
require_exe "$ROOT/bin/op-node"

mkdir -p "$WORKDIR/logs" "$GETH_DATADIR"

if is_running "$WORKDIR/geth.pid"; then
  echo "[start] geth already running: pid $(cat "$WORKDIR/geth.pid")"
else
  echo "[start] op-geth L2 execution client"
  "$ROOT/bin/geth" \
    --datadir "$GETH_DATADIR" \
    --networkid "$L2_CHAIN_ID" \
    --http \
    --http.addr "$L2_RPC_ADDR" \
    --http.port "$L2_RPC_PORT" \
    --http.api eth,net,web3,debug,txpool \
    --http.corsdomain "*" \
    --http.vhosts "*" \
    --ws \
    --ws.addr "$L2_WS_ADDR" \
    --ws.port "$L2_WS_PORT" \
    --ws.api eth,net,web3,debug,txpool \
    --authrpc.addr "$L2_AUTHRPC_ADDR" \
    --authrpc.port "$L2_AUTHRPC_PORT" \
    --authrpc.jwtsecret "$JWT" \
    --authrpc.vhosts "*" \
    --syncmode full \
    --gcmode archive \
    --state.scheme hash \
    --nodiscover \
    --maxpeers 0 \
    --rollup.disabletxpoolgossip \
    --verbosity "${GETH_VERBOSITY:-3}" \
    > "$WORKDIR/logs/geth.log" 2>&1 &
  echo $! > "$WORKDIR/geth.pid"
fi

wait_rpc "$L2_RPC_URL" "$L2_CHAIN_ID" "op-geth"

if is_running "$WORKDIR/op-node.pid"; then
  echo "[start] op-node already running: pid $(cat "$WORKDIR/op-node.pid")"
else
  echo "[start] op-node sequencer"
  OP_NODE_ARGS=(
    --l1 "$L1_RPC_URL"
    --l1.rpckind "$L1_RPC_KIND"
    --l2 "$L2_AUTHRPC_URL"
    --l2.jwt-secret "$JWT"
    --rollup.config "$ROLLUP"
    --sequencer.enabled
    --sequencer.l1-confs "$SEQUENCER_L1_CONFS"
    --verifier.l1-confs "$VERIFIER_L1_CONFS"
    --p2p.disable
    --rpc.addr "$OP_NODE_RPC_ADDR"
    --rpc.port "$OP_NODE_RPC_PORT"
    --rpc.enable-admin
    --safedb.path "$WORKDIR/safedb"
  )

  if [ -n "$L1_BEACON_URL" ] && [ "$L1_BEACON_URL" != "null" ]; then
    OP_NODE_ARGS+=(--l1.beacon "$L1_BEACON_URL")
  else
    OP_NODE_ARGS+=(--l1.beacon.ignore)
  fi

  case "$VRF_MODE" in
    local)
      OP_NODE_ARGS+=(--sequencer.vrf-mode local --sequencer.vrf-key "$VRF_SK")
      ;;
    tee)
      : "${VRF_TEE_ENDPOINT:?set VRF_TEE_ENDPOINT when VRF_MODE=tee}"
      OP_NODE_ARGS+=(--sequencer.vrf-mode tee --sequencer.vrf-tee-endpoint "$VRF_TEE_ENDPOINT")
      ;;
    *)
      echo "unsupported VRF_MODE=$VRF_MODE (expected local or tee)" >&2
      exit 1
      ;;
  esac

  "$ROOT/bin/op-node" "${OP_NODE_ARGS[@]}" > "$WORKDIR/logs/op-node.log" 2>&1 &
  echo $! > "$WORKDIR/op-node.pid"
fi

echo
echo "[start] ready"
echo "  L2 RPC:       $L2_RPC_URL"
echo "  L2 WS:        ws://$L2_WS_HOST:$L2_WS_PORT"
echo "  op-node RPC:  http://$OP_NODE_RPC_HOST:$OP_NODE_RPC_PORT"
echo "  logs:         $WORKDIR/logs"
echo
echo "Next: ./scripts/devnet-sepolia-verify-random.sh"
