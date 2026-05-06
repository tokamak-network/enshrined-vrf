#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT/devnet/sepolia/.env}"
WORKDIR="${DEVNET_WORKDIR:-$ROOT/.devnet/sepolia}"
DEPLOYER_WORKDIR="$WORKDIR/op-deployer"
DEPLOYER_CACHE_DIR="${OP_DEPLOYER_CACHE_DIR:-$WORKDIR/op-deployer-cache}"
ARTIFACTS_DIR="$ROOT/optimism/packages/contracts-bedrock/forge-artifacts"

if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

run_op_deployer() {
  if [ -n "${OP_DEPLOYER_BIN:-}" ]; then
    "$OP_DEPLOYER_BIN" --cache-dir "$DEPLOYER_CACHE_DIR" "$@"
  elif [ -x "$ROOT/bin/op-deployer" ]; then
    "$ROOT/bin/op-deployer" --cache-dir "$DEPLOYER_CACHE_DIR" "$@"
  else
    (cd "$ROOT/optimism" && GOCACHE="${GOCACHE:-$ROOT/.devnet/go-build-cache}" go run ./op-deployer/cmd/op-deployer --cache-dir "$DEPLOYER_CACHE_DIR" "$@")
  fi
}

addr_from_key() {
  cast wallet address --private-key "$1"
}

normalize_bytes_output() {
  local value
  value="$(printf '%s' "$1" | tr -d '[:space:]')"
  if [ -z "$value" ]; then
    return 0
  fi
  if [ "${#value}" -eq 68 ]; then
    printf '%s\n' "$value"
    return 0
  fi
  cast abi-decode "f()(bytes)" "$value" | awk 'NF { print $1; exit }'
}

: "${L1_RPC_URL:?set L1_RPC_URL in $ENV_FILE}"
: "${PRIVATE_KEY:?set PRIVATE_KEY in $ENV_FILE}"

L2_CHAIN_ID="${L2_CHAIN_ID:-901005}"
VRF_SK="${VRF_SK:-0xc9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721}"
BUILD_BINARIES="${BUILD_BINARIES:-1}"
BUILD_CONTRACTS="${BUILD_CONTRACTS:-1}"
SET_L1_VRF_PUBLIC_KEY="${SET_L1_VRF_PUBLIC_KEY:-1}"

require_cmd cast
require_cmd jq
require_cmd forge
require_cmd go

L1_CHAIN_ID="$("$ROOT/scripts/devnet-rpc-chain-id.sh" "$L1_RPC_URL")"
if [ "$L1_CHAIN_ID" != "11155111" ]; then
  echo "refusing to deploy: L1_RPC_URL chain-id is $L1_CHAIN_ID, expected Sepolia 11155111" >&2
  exit 1
fi

mkdir -p "$WORKDIR" "$DEPLOYER_WORKDIR" "$DEPLOYER_CACHE_DIR" "$ROOT/bin"

if [ "$BUILD_BINARIES" = "1" ]; then
  "$ROOT/scripts/devnet-build.sh"
fi

if [ "$BUILD_CONTRACTS" = "1" ]; then
  echo "[prepare] building contracts-bedrock forge artifacts"
  (cd "$ROOT/optimism/packages/contracts-bedrock" && forge build)
fi

if [ ! -f "$ARTIFACTS_DIR/L2Genesis.s.sol/L2Genesis.json" ] ||
   [ ! -f "$ARTIFACTS_DIR/EnshrainedVRF.sol/EnshrainedVRF.json" ]; then
  echo "missing local contracts-bedrock artifacts in $ARTIFACTS_DIR; rerun with BUILD_CONTRACTS=1" >&2
  exit 1
fi

DEPLOYER_ADDR="$(addr_from_key "$PRIVATE_KEY")"
BATCHER_ADDR="${BATCHER_ADDR:-$DEPLOYER_ADDR}"
PROPOSER_ADDR="${PROPOSER_ADDR:-$DEPLOYER_ADDR}"
CHALLENGER_ADDR="${CHALLENGER_ADDR:-$DEPLOYER_ADDR}"
SYSTEM_CONFIG_OWNER_ADDR="${SYSTEM_CONFIG_OWNER_ADDR:-$DEPLOYER_ADDR}"
L1_PROXY_ADMIN_OWNER_ADDR="${L1_PROXY_ADMIN_OWNER_ADDR:-$DEPLOYER_ADDR}"
L2_PROXY_ADMIN_OWNER_ADDR="${L2_PROXY_ADMIN_OWNER_ADDR:-$DEPLOYER_ADDR}"
UNSAFE_BLOCK_SIGNER_ADDR="${UNSAFE_BLOCK_SIGNER_ADDR:-$DEPLOYER_ADDR}"
FEE_VAULT_RECIPIENT_ADDR="${FEE_VAULT_RECIPIENT_ADDR:-$DEPLOYER_ADDR}"
CHAIN_FEES_RECIPIENT_ADDR="${CHAIN_FEES_RECIPIENT_ADDR:-$DEPLOYER_ADDR}"
L2_CHAIN_ID_HEX="$(printf "0x%064x" "$L2_CHAIN_ID")"
ARTIFACTS_LOCATOR="file://$ARTIFACTS_DIR"
export DEPLOYER_ADDR BATCHER_ADDR PROPOSER_ADDR CHALLENGER_ADDR
export SYSTEM_CONFIG_OWNER_ADDR L1_PROXY_ADMIN_OWNER_ADDR L2_PROXY_ADMIN_OWNER_ADDR
export UNSAFE_BLOCK_SIGNER_ADDR FEE_VAULT_RECIPIENT_ADDR CHAIN_FEES_RECIPIENT_ADDR
export L2_CHAIN_ID L2_CHAIN_ID_HEX ARTIFACTS_LOCATOR

if [ ! -f "$DEPLOYER_WORKDIR/state.json" ]; then
  echo "[prepare] initializing op-deployer workdir"
  run_op_deployer init \
    --l1-chain-id 11155111 \
    --l2-chain-ids "$L2_CHAIN_ID" \
    --intent-type custom \
    --workdir "$DEPLOYER_WORKDIR"
fi

if jq -e '.appliedIntent != null' "$DEPLOYER_WORKDIR/state.json" >/dev/null 2>&1; then
  echo "[prepare] op-deployer state is already applied; keeping existing intent/state"
else
  echo "[prepare] writing custom Sepolia intent"
  "$ROOT/scripts/devnet-sepolia-render-intent.sh" > "$DEPLOYER_WORKDIR/intent.toml"

  echo "[prepare] applying op-deployer intent to Sepolia"
  run_op_deployer apply \
    --workdir "$DEPLOYER_WORKDIR" \
    --l1-rpc-url "$L1_RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --deployment-target live
fi

echo "[prepare] rendering L2 genesis and rollup config"
run_op_deployer inspect genesis --workdir "$DEPLOYER_WORKDIR" --outfile "$WORKDIR/genesis.json" "$L2_CHAIN_ID"
run_op_deployer inspect rollup --workdir "$DEPLOYER_WORKDIR" --outfile "$WORKDIR/rollup.json" "$L2_CHAIN_ID"
run_op_deployer inspect deploy-config --workdir "$DEPLOYER_WORKDIR" --outfile "$WORKDIR/deploy-config.json" "$L2_CHAIN_ID"
run_op_deployer inspect l1 --workdir "$DEPLOYER_WORKDIR" --outfile "$WORKDIR/l1-addresses.json" "$L2_CHAIN_ID"

if [ ! -f "$WORKDIR/depset.json" ]; then
  printf '{"dependencies":{"%s":{}}}\n' "$L2_CHAIN_ID" > "$WORKDIR/depset.json"
fi

if [ ! -f "$WORKDIR/jwt.txt" ]; then
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32 > "$WORKDIR/jwt.txt"
  else
    printf "0000000000000000000000000000000000000000000000000000000000000000\n" > "$WORKDIR/jwt.txt"
  fi
fi

GETH_DATADIR="$WORKDIR/geth"
if [ ! -d "$GETH_DATADIR/geth/chaindata" ]; then
  echo "[prepare] initializing op-geth datadir"
  "$ROOT/bin/geth" init --state.scheme hash --datadir "$GETH_DATADIR" "$WORKDIR/genesis.json"
fi

SYSTEM_CONFIG_PROXY="$(jq -r '.SystemConfigProxy // .systemConfigProxy' "$WORKDIR/l1-addresses.json")"
if [ -z "$SYSTEM_CONFIG_PROXY" ] || [ "$SYSTEM_CONFIG_PROXY" = "null" ]; then
  echo "could not read SystemConfigProxy from $WORKDIR/l1-addresses.json" >&2
  exit 1
fi

if [ "$SET_L1_VRF_PUBLIC_KEY" = "1" ]; then
  if [ ! -x "$ROOT/bin/vrf-prove" ]; then
    (cd "$ROOT" && go build -o "$ROOT/bin/vrf-prove" ./vrf-enclave/cmd/vrf-prove)
  fi
  VRF_PK_RAW="$("$ROOT/bin/vrf-prove" -sk "$VRF_SK" -seed "0000000000000000000000000000000000000000000000000000000000000000" 2>/dev/null | awk -F= '/^pk=/{print $2; exit}')"
  VRF_PUBLIC_KEY="0x${VRF_PK_RAW#0x}"
  if [ "${#VRF_PUBLIC_KEY}" -ne 68 ]; then
    echo "failed to derive 33-byte VRF public key from VRF_SK" >&2
    exit 1
  fi
  CURRENT_VRF_PK_RAW="$(cast call "$SYSTEM_CONFIG_PROXY" "vrfPublicKey()(bytes)" --rpc-url "$L1_RPC_URL" 2>/dev/null || true)"
  CURRENT_VRF_PK="$(normalize_bytes_output "$CURRENT_VRF_PK_RAW" 2>/dev/null || true)"
  if [ "$CURRENT_VRF_PK" = "$VRF_PUBLIC_KEY" ]; then
    echo "[prepare] L1 SystemConfig already has VRF public key"
  else
    echo "[prepare] setting L1 SystemConfig VRF public key on Sepolia"
    cast send "$SYSTEM_CONFIG_PROXY" "setVRFPublicKey(bytes)" "$VRF_PUBLIC_KEY" \
      --rpc-url "$L1_RPC_URL" \
      --private-key "$PRIVATE_KEY"
  fi
else
  VRF_PUBLIC_KEY=""
fi

jq -n \
  --arg l1RpcUrl "$L1_RPC_URL" \
  --arg l1BeaconUrl "${L1_BEACON_URL:-}" \
  --arg l2ChainId "$L2_CHAIN_ID" \
  --arg l2ChainIdHex "$L2_CHAIN_ID_HEX" \
  --arg workdir "$WORKDIR" \
  --arg genesis "$WORKDIR/genesis.json" \
  --arg rollup "$WORKDIR/rollup.json" \
  --arg jwt "$WORKDIR/jwt.txt" \
  --arg gethDatadir "$GETH_DATADIR" \
  --arg systemConfigProxy "$SYSTEM_CONFIG_PROXY" \
  --arg vrfAddress "0x42000000000000000000000000000000000000f0" \
  --arg vrfPublicKey "$VRF_PUBLIC_KEY" \
  '{
    l1ChainId: 11155111,
    l1RpcUrl: $l1RpcUrl,
    l1BeaconUrl: $l1BeaconUrl,
    l2ChainId: ($l2ChainId | tonumber),
    l2ChainIdHex: $l2ChainIdHex,
    workdir: $workdir,
    genesis: $genesis,
    rollup: $rollup,
    jwt: $jwt,
    gethDatadir: $gethDatadir,
    systemConfigProxy: $systemConfigProxy,
    vrfAddress: $vrfAddress,
    vrfPublicKey: $vrfPublicKey,
    l2RpcUrl: "http://127.0.0.1:9545",
    l2AuthRpcUrl: "http://127.0.0.1:9551",
    opNodeRpcUrl: "http://127.0.0.1:7545"
  }' > "$WORKDIR/devnet.json"

echo
echo "[prepare] ready"
echo "  workdir:        $WORKDIR"
echo "  l2 chain id:    $L2_CHAIN_ID"
echo "  system config:  $SYSTEM_CONFIG_PROXY"
echo "  rollup config:  $WORKDIR/rollup.json"
echo "  genesis:        $WORKDIR/genesis.json"
echo
echo "Next: ./scripts/devnet-sepolia-start.sh"
