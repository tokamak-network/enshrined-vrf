#!/usr/bin/env bash
set -euo pipefail

# Deploys the Jankenman example consumer contract to the local Sepolia-backed
# L2 devnet. Reads chain endpoints from .devnet/sepolia/devnet.json and writes
# the deployed address to .devnet/sepolia/jankenman.json.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT/devnet/sepolia/.env}"
WORKDIR="${DEVNET_WORKDIR:-$ROOT/.devnet/sepolia}"
MANIFEST="$WORKDIR/devnet.json"
ARTIFACT="$ROOT/contracts/out/Jankenman.sol/Jankenman.json"
OUTFILE="$WORKDIR/jankenman.json"

if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

[ -f "$MANIFEST" ] || {
  echo "missing $MANIFEST; run prepare/start first" >&2
  exit 1
}

command -v cast >/dev/null 2>&1 || { echo "missing required command: cast" >&2; exit 1; }
command -v jq   >/dev/null 2>&1 || { echo "missing required command: jq"   >&2; exit 1; }

L2_CHAIN_ID="$(jq -r '.l2ChainId' "$MANIFEST")"
MANIFEST_L2_RPC_URL="$(jq -r '.l2RpcUrl // "http://127.0.0.1:9545"' "$MANIFEST")"
L2_RPC_HOST="${L2_RPC_HOST:-127.0.0.1}"
L2_RPC_PORT="${L2_RPC_PORT:-$(printf '%s' "$MANIFEST_L2_RPC_URL" | sed -E 's#^https?://[^:/]+:([0-9]+).*$#\1#')}"
if [ "$L2_RPC_PORT" = "$MANIFEST_L2_RPC_URL" ]; then
  L2_RPC_PORT=9545
fi
L2_RPC_URL="${L2_RPC_URL:-http://$L2_RPC_HOST:$L2_RPC_PORT}"
VRF_ADDR="$(jq -r '.vrfAddress' "$MANIFEST")"

# First Hardhat account, prefunded by fundDevAccounts=true at L2 genesis.
DEPLOYER_KEY="${L2_TEST_PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"

# Optional: seed the LP pool so Jankenman can pay out wins immediately.
SEED_LP_AMOUNT="${SEED_LP_AMOUNT:-1ether}"

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

echo "[deploy] L2 RPC:        $L2_RPC_URL"
echo "[deploy] chain id:      $L2_CHAIN_ID"
echo "[deploy] VRF predeploy: $VRF_ADDR"

wait_chain

# Make sure the EnshrainedVRF predeploy is alive — Jankenman calls it on every
# round. Refusing to deploy when randomness is not yet available avoids leaving
# a useless contract on chain.
code="$(cast code "$VRF_ADDR" --rpc-url "$L2_RPC_URL")"
if [ "$code" = "0x" ]; then
  echo "EnshrainedVRF predeploy has no code at $VRF_ADDR; run start/verify first" >&2
  exit 1
fi
randomness="$(cast call "$VRF_ADDR" "getRandomness()(uint256)" --rpc-url "$L2_RPC_URL" 2>&1)"
if [ -z "$randomness" ] || [ "$randomness" = "0" ]; then
  echo "[deploy] warning: getRandomness() returned $randomness; sequencer may not have committed yet" >&2
fi

# Build the contracts package if the artifact is missing.
if [ ! -f "$ARTIFACT" ]; then
  echo "[deploy] building contracts package"
  (cd "$ROOT/contracts" && forge build)
fi
[ -f "$ARTIFACT" ] || { echo "missing artifact $ARTIFACT after build" >&2; exit 1; }

bytecode="$(jq -r '.bytecode.object' "$ARTIFACT")"
if [ -z "$bytecode" ] || [ "$bytecode" = "null" ]; then
  echo "Jankenman artifact has no bytecode" >&2
  exit 1
fi

DEPLOYER_ADDR="$(cast wallet address --private-key "$DEPLOYER_KEY")"
echo "[deploy] deployer:      $DEPLOYER_ADDR"

deploy_json="$(cast send --json \
  --rpc-url "$L2_RPC_URL" \
  --private-key "$DEPLOYER_KEY" \
  --create "0x${bytecode#0x}")"

JANKENMAN_ADDR="$(echo "$deploy_json" | jq -r '.contractAddress')"
deploy_tx="$(echo "$deploy_json" | jq -r '.transactionHash')"
deploy_block="$(echo "$deploy_json" | jq -r '.blockNumber')"
deploy_status="$(echo "$deploy_json" | jq -r '.status')"

if [ -z "$JANKENMAN_ADDR" ] || [ "$JANKENMAN_ADDR" = "null" ]; then
  echo "Jankenman deployment did not return a contractAddress" >&2
  echo "$deploy_json" >&2
  exit 1
fi
if [ "$deploy_status" != "0x1" ] && [ "$deploy_status" != "1" ]; then
  echo "Jankenman deployment transaction failed (status=$deploy_status)" >&2
  echo "$deploy_json" >&2
  exit 1
fi

# Verify there's actually code at the new address (cheap sanity check).
deployed_code="$(cast code "$JANKENMAN_ADDR" --rpc-url "$L2_RPC_URL")"
if [ "$deployed_code" = "0x" ]; then
  echo "deployment reported success but address has no code: $JANKENMAN_ADDR" >&2
  exit 1
fi

# Optional: seed the LP pool so subsequent play() calls don't revert with PoolTooShallow.
seed_tx=""
if [ -n "$SEED_LP_AMOUNT" ] && [ "$SEED_LP_AMOUNT" != "0" ]; then
  seed_json="$(cast send --json \
    --rpc-url "$L2_RPC_URL" \
    --private-key "$DEPLOYER_KEY" \
    --value "$SEED_LP_AMOUNT" \
    "$JANKENMAN_ADDR" "depositLP()")"
  seed_status="$(echo "$seed_json" | jq -r '.status')"
  if [ "$seed_status" = "0x1" ] || [ "$seed_status" = "1" ]; then
    seed_tx="$(echo "$seed_json" | jq -r '.transactionHash')"
  else
    echo "[deploy] warning: depositLP seed call failed (status=$seed_status)" >&2
  fi
fi

lpAssets="$(cast call "$JANKENMAN_ADDR" "lpAssets()(uint256)" --rpc-url "$L2_RPC_URL" 2>&1 || echo unknown)"

jq -n \
  --arg address "$JANKENMAN_ADDR" \
  --arg deployer "$DEPLOYER_ADDR" \
  --arg deployTx "$deploy_tx" \
  --arg deployBlock "$deploy_block" \
  --arg seedTx "$seed_tx" \
  --arg seedAmount "$SEED_LP_AMOUNT" \
  --arg l2RpcUrl "$L2_RPC_URL" \
  --arg l2ChainId "$L2_CHAIN_ID" \
  --arg vrfAddress "$VRF_ADDR" \
  '{
    address: $address,
    deployer: $deployer,
    deployTx: $deployTx,
    deployBlock: $deployBlock,
    seedTx: $seedTx,
    seedAmount: $seedAmount,
    l2RpcUrl: $l2RpcUrl,
    l2ChainId: ($l2ChainId | tonumber),
    vrfAddress: $vrfAddress
  }' > "$OUTFILE"

echo
echo "[deploy] ok"
echo "  Jankenman:    $JANKENMAN_ADDR"
echo "  deployer:     $DEPLOYER_ADDR"
echo "  deploy tx:    $deploy_tx"
echo "  deploy block: $deploy_block"
if [ -n "$seed_tx" ]; then
  echo "  LP seed:      $SEED_LP_AMOUNT (tx $seed_tx)"
  echo "  lpAssets:     $lpAssets"
fi
echo "  manifest:     $OUTFILE"
