#!/usr/bin/env bash
set -euo pipefail

VRF_ADDR="${VRF_ADDR:-0x42000000000000000000000000000000000000f0}"
VERIFY_PRECOMPILE="${VERIFY_PRECOMPILE:-0x0000000000000000000000000000000000000101}"
VERIFY_PROOF_METRIC="${VERIFY_PROOF_METRIC:-1}"
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

metric() {
  printf '%s %s\n' "$1" "$2"
}

chain_id="$(cast chain-id --rpc-url "$L2_RPC_URL" 2>/dev/null || printf '0')"
metric "enshrined_vrf_l2_chain_id" "$chain_id"

code="$(cast code "$VRF_ADDR" --rpc-url "$L2_RPC_URL" 2>/dev/null || printf '0x')"
if [ "$code" = "0x" ]; then
  metric "enshrined_vrf_predeploy_code_present" 0
  metric "enshrined_vrf_commit_nonce" 0
  metric "enshrined_vrf_l2_public_key_set" 0
  metric "enshrined_vrf_public_key_match" 0
  metric "enshrined_vrf_randomness_call_ok" 0
  metric "enshrined_vrf_proof_verify_ok" 0
  exit 0
fi
metric "enshrined_vrf_predeploy_code_present" 1

raw_nonce="$(cast call "$VRF_ADDR" "commitNonce()(uint256)" --rpc-url "$L2_RPC_URL" 2>/dev/null || printf '0x0')"
nonce="$(cast to-dec "$raw_nonce" 2>/dev/null || printf '0')"
metric "enshrined_vrf_commit_nonce" "$nonce"

raw_l2_pk="$(cast call "$VRF_ADDR" "sequencerPublicKey()(bytes)" --rpc-url "$L2_RPC_URL" 2>/dev/null || true)"
l2_pk="$(normalize_bytes_output "$raw_l2_pk" 2>/dev/null || true)"
if [ "${#l2_pk}" -eq 68 ]; then
  metric "enshrined_vrf_l2_public_key_set" 1
else
  metric "enshrined_vrf_l2_public_key_set" 0
fi

expected_pk=""
if [ -n "${EXPECTED_VRF_PUBLIC_KEY:-}" ]; then
  expected_pk="0x${EXPECTED_VRF_PUBLIC_KEY#0x}"
elif [ -n "${L1_RPC_URL:-}" ] && [ -n "${SYSTEM_CONFIG_PROXY:-}" ]; then
  raw_l1_pk="$(cast call "$SYSTEM_CONFIG_PROXY" "vrfPublicKey()(bytes)" --rpc-url "$L1_RPC_URL" 2>/dev/null || true)"
  expected_pk="$(normalize_bytes_output "$raw_l1_pk" 2>/dev/null || true)"
fi

if [ -n "$expected_pk" ] && [ "$expected_pk" = "$l2_pk" ]; then
  metric "enshrined_vrf_public_key_match" 1
elif [ -n "$expected_pk" ]; then
  metric "enshrined_vrf_public_key_match" 0
else
  metric "enshrined_vrf_public_key_match" -1
fi

if cast call "$VRF_ADDR" "getRandomness()(uint256)" --rpc-url "$L2_RPC_URL" >/dev/null 2>&1; then
  metric "enshrined_vrf_randomness_call_ok" 1
else
  metric "enshrined_vrf_randomness_call_ok" 0
fi

proof_ok=0
if [ "$VERIFY_PROOF_METRIC" = "1" ] && [ "$nonce" -gt 0 ] && [ "${#l2_pk}" -eq 68 ]; then
  result_nonce=$((nonce - 1))
  calldata="$(cast calldata "getResult(uint256)" "$result_nonce")"
  raw_result="$(cast call "$VRF_ADDR" --data "$calldata" --rpc-url "$L2_RPC_URL" 2>/dev/null || true)"
  if [ -n "$raw_result" ]; then
    decoded="$(cast abi-decode "getResult(uint256)(bytes32,bytes32,bytes)" "$raw_result" 2>/dev/null || true)"
    seed="$(printf '%s\n' "$decoded" | awk 'NF { print; exit }')"
    beta="$(printf '%s\n' "$decoded" | awk 'NF { n++; if (n == 2) { print; exit } }')"
    pi="$(printf '%s\n' "$decoded" | awk 'NF { n++; if (n == 3) { print; exit } }')"
    if [ "${#seed}" -eq 66 ] && [ "${#beta}" -eq 66 ] && [ "${#pi}" -eq 164 ]; then
      verify_input="$(cast concat-hex "$l2_pk" "$seed" "$beta" "$pi")"
      verify_output="$(cast call "$VERIFY_PRECOMPILE" --data "$verify_input" --rpc-url "$L2_RPC_URL" 2>/dev/null || true)"
      case "$verify_output" in
        0x01|0x0000000000000000000000000000000000000000000000000000000000000001)
          proof_ok=1
          ;;
      esac
    fi
  fi
elif [ "$VERIFY_PROOF_METRIC" != "1" ]; then
  proof_ok=-1
fi
metric "enshrined_vrf_proof_verify_ok" "$proof_ok"
