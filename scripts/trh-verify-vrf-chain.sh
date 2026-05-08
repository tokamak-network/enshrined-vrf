#!/usr/bin/env bash
set -euo pipefail

VRF_ADDR="${VRF_ADDR:-0x42000000000000000000000000000000000000f0}"
WAIT_SECONDS="${WAIT_SECONDS:-120}"
REQUIRE_COMMIT="${REQUIRE_COMMIT:-1}"
VERIFY_RANDOMNESS="${VERIFY_RANDOMNESS:-1}"

: "${L2_RPC_URL:?set L2_RPC_URL}"

command -v cast >/dev/null 2>&1 || {
  echo "missing required command: cast" >&2
  exit 1
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

wait_commit_nonce() {
  local deadline
  deadline=$((SECONDS + WAIT_SECONDS))
  while [ "$SECONDS" -le "$deadline" ]; do
    if raw="$(cast call "$VRF_ADDR" "commitNonce()(uint256)" --rpc-url "$L2_RPC_URL" 2>/dev/null)"; then
      nonce="$(cast to-dec "$raw")"
      if [ "$REQUIRE_COMMIT" != "1" ] || [ "$nonce" -gt 0 ]; then
        printf '%s\n' "$nonce"
        return 0
      fi
    fi
    sleep 2
  done
  echo "VRF commitNonce did not advance within ${WAIT_SECONDS}s" >&2
  return 1
}

expected_pk=""
if [ -n "${EXPECTED_VRF_PUBLIC_KEY:-}" ]; then
  expected_pk="0x${EXPECTED_VRF_PUBLIC_KEY#0x}"
elif [ -n "${L1_RPC_URL:-}" ] && [ -n "${SYSTEM_CONFIG_PROXY:-}" ]; then
  raw_l1_pk="$(cast call "$SYSTEM_CONFIG_PROXY" "vrfPublicKey()(bytes)" --rpc-url "$L1_RPC_URL")"
  expected_pk="$(normalize_bytes_output "$raw_l1_pk")"
fi

chain_id="$(cast chain-id --rpc-url "$L2_RPC_URL")"
code="$(cast code "$VRF_ADDR" --rpc-url "$L2_RPC_URL")"
if [ "$code" = "0x" ]; then
  echo "EnshrainedVRF predeploy has no code at $VRF_ADDR on L2 chain $chain_id" >&2
  exit 1
fi

nonce="$(wait_commit_nonce)"

raw_l2_pk="$(cast call "$VRF_ADDR" "sequencerPublicKey()(bytes)" --rpc-url "$L2_RPC_URL")"
l2_pk="$(normalize_bytes_output "$raw_l2_pk")"
if [ "${#l2_pk}" -ne 68 ]; then
  echo "L2 sequencerPublicKey is not a 33-byte compressed SEC1 key: $l2_pk" >&2
  exit 1
fi

if [ -n "$expected_pk" ] && [ "$expected_pk" != "$l2_pk" ]; then
  echo "VRF public key mismatch" >&2
  echo "  expected: $expected_pk" >&2
  echo "  l2:       $l2_pk" >&2
  exit 1
fi

randomness=""
if [ "$VERIFY_RANDOMNESS" = "1" ]; then
  randomness="$(cast call "$VRF_ADDR" "getRandomness()(uint256)" --rpc-url "$L2_RPC_URL")"
fi

echo "[trh-vrf-verify] ok"
echo "  L2 RPC:        $L2_RPC_URL"
echo "  chain id:      $chain_id"
echo "  VRF predeploy: $VRF_ADDR"
echo "  commitNonce:   $nonce"
echo "  public key:    $l2_pk"
if [ -n "$expected_pk" ]; then
  echo "  expected key:  $expected_pk"
fi
if [ -n "$randomness" ]; then
  echo "  randomness:    $randomness"
fi
