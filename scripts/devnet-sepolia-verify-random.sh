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

[ -f "$MANIFEST" ] || {
  echo "missing $MANIFEST; run prepare/start first" >&2
  exit 1
}

command -v cast >/dev/null 2>&1 || {
  echo "missing required command: cast" >&2
  exit 1
}
command -v jq >/dev/null 2>&1 || {
  echo "missing required command: jq" >&2
  exit 1
}

L2_CHAIN_ID="$(jq -r '.l2ChainId' "$MANIFEST")"
MANIFEST_L2_RPC_URL="$(jq -r '.l2RpcUrl // "http://127.0.0.1:9545"' "$MANIFEST")"
L2_RPC_HOST="${L2_RPC_HOST:-127.0.0.1}"
L2_RPC_PORT="${L2_RPC_PORT:-$(printf '%s' "$MANIFEST_L2_RPC_URL" | sed -E 's#^https?://[^:/]+:([0-9]+).*$#\1#')}"
if [ "$L2_RPC_PORT" = "$MANIFEST_L2_RPC_URL" ]; then
  L2_RPC_PORT=9545
fi
L2_RPC_URL="${L2_RPC_URL:-http://$L2_RPC_HOST:$L2_RPC_PORT}"
VRF_ADDR="$(jq -r '.vrfAddress' "$MANIFEST")"
EXPECTED_VRF_PK="$(jq -r '.vrfPublicKey // ""' "$MANIFEST")"
L2_TEST_PRIVATE_KEY="${L2_TEST_PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
VERIFY_CONSUMER="${VERIFY_CONSUMER:-1}"
REQUIRE_VRF_PUBLIC_KEY="${REQUIRE_VRF_PUBLIC_KEY:-1}"

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

wait_commit_nonce() {
  for _ in $(seq 1 90); do
    if raw="$(cast call "$VRF_ADDR" "commitNonce()(uint256)" --rpc-url "$L2_RPC_URL" 2>/dev/null)"; then
      nonce="$(cast to-dec "$raw")"
      if [ "$nonce" -gt 0 ]; then
        echo "$nonce"
        return 0
      fi
    fi
    sleep 2
  done
  echo "VRF commitNonce did not advance; check $WORKDIR/logs/op-node.log and geth.log" >&2
  exit 1
}

wait_public_key() {
  for _ in $(seq 1 90); do
    raw_pk="$(cast call "$VRF_ADDR" "sequencerPublicKey()(bytes)" --rpc-url "$L2_RPC_URL" 2>/dev/null || true)"
    pk="$(normalize_bytes_output "$raw_pk" 2>/dev/null || true)"
    if [ -n "$pk" ] && [ "$pk" != "0x" ]; then
      echo "$pk"
      return 0
    fi
    sleep 2
  done
  return 1
}

wait_chain

code="$(cast code "$VRF_ADDR" --rpc-url "$L2_RPC_URL")"
if [ "$code" = "0x" ]; then
  echo "EnshrainedVRF predeploy has no code at $VRF_ADDR" >&2
  exit 1
fi

nonce="$(wait_commit_nonce)"

pk=""
if pk="$(wait_public_key)"; then
  if [ -n "$EXPECTED_VRF_PK" ] && [ "$EXPECTED_VRF_PK" != "null" ] && [ "$pk" != "$EXPECTED_VRF_PK" ]; then
    echo "L2 VRF public key mismatch" >&2
    echo "  expected: $EXPECTED_VRF_PK" >&2
    echo "  actual:   $pk" >&2
    exit 1
  fi
elif [ "$REQUIRE_VRF_PUBLIC_KEY" = "1" ]; then
  echo "L2 EnshrainedVRF public key was not set; rebuild op-geth with the VRF public-key deposit patch and restart" >&2
  exit 1
fi

randomness="$(cast call "$VRF_ADDR" "getRandomness()(uint256)" --rpc-url "$L2_RPC_URL")"

coinflip_addr=""
if [ "$VERIFY_CONSUMER" = "1" ]; then
  if [ ! -f "$ROOT/contracts/out/CoinFlip.sol/CoinFlip.json" ]; then
    (cd "$ROOT/contracts" && forge build)
  fi
  bytecode="$(jq -r '.bytecode.object' "$ROOT/contracts/out/CoinFlip.sol/CoinFlip.json")"
  if [ -z "$bytecode" ] || [ "$bytecode" = "null" ]; then
    echo "missing CoinFlip bytecode artifact" >&2
    exit 1
  fi
  deploy_json="$(cast send --json --rpc-url "$L2_RPC_URL" --private-key "$L2_TEST_PRIVATE_KEY" --create "0x${bytecode#0x}")"
  coinflip_addr="$(echo "$deploy_json" | jq -r '.contractAddress')"
  if [ -z "$coinflip_addr" ] || [ "$coinflip_addr" = "null" ]; then
    echo "CoinFlip deployment did not return a contractAddress" >&2
    echo "$deploy_json" >&2
    exit 1
  fi

  flip_json="$(cast send --json --rpc-url "$L2_RPC_URL" --private-key "$L2_TEST_PRIVATE_KEY" "$coinflip_addr" "flip()(bool)")"
  status="$(echo "$flip_json" | jq -r '.status')"
  if [ "$status" != "0x1" ] && [ "$status" != "1" ]; then
    echo "CoinFlip.flip() transaction failed" >&2
    echo "$flip_json" >&2
    exit 1
  fi
fi

echo "[verify] ok"
echo "  L2 RPC:        $L2_RPC_URL"
echo "  chain id:      $L2_CHAIN_ID"
echo "  VRF predeploy: $VRF_ADDR"
echo "  commitNonce:   $nonce"
echo "  public key:    ${pk:-not checked}"
echo "  randomness:    $randomness"
if [ -n "$coinflip_addr" ]; then
  echo "  CoinFlip:      $coinflip_addr"
fi
