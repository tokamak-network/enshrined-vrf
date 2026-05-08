#!/usr/bin/env bash
set -euo pipefail

VRF_ADDR="${VRF_ADDR:-0x42000000000000000000000000000000000000f0}"
VERIFY_PRECOMPILE="${VERIFY_PRECOMPILE:-0x0000000000000000000000000000000000000101}"
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

commit_nonce_raw="$(cast call "$VRF_ADDR" "commitNonce()(uint256)" --rpc-url "$L2_RPC_URL")"
commit_nonce="$(cast to-dec "$commit_nonce_raw")"
if [ "$commit_nonce" -le 0 ]; then
  echo "EnshrainedVRF has no committed result yet" >&2
  exit 1
fi

RESULT_NONCE="${RESULT_NONCE:-$((commit_nonce - 1))}"
calldata="$(cast calldata "getResult(uint256)" "$RESULT_NONCE")"
raw_result="$(cast call "$VRF_ADDR" --data "$calldata" --rpc-url "$L2_RPC_URL")"
decoded="$(cast abi-decode "getResult(uint256)(bytes32,bytes32,bytes)" "$raw_result")"
seed="$(printf '%s\n' "$decoded" | awk 'NF { print; exit }')"
beta="$(printf '%s\n' "$decoded" | awk 'NF { n++; if (n == 2) { print; exit } }')"
pi="$(printf '%s\n' "$decoded" | awk 'NF { n++; if (n == 3) { print; exit } }')"

if [ "${#seed}" -ne 66 ] || [ "${#beta}" -ne 66 ] || [ "${#pi}" -ne 164 ]; then
  echo "decoded VRF result has invalid lengths" >&2
  echo "  seed: ${#seed} $seed" >&2
  echo "  beta: ${#beta} $beta" >&2
  echo "  pi:   ${#pi} $pi" >&2
  exit 1
fi

raw_pk="$(cast call "$VRF_ADDR" "sequencerPublicKey()(bytes)" --rpc-url "$L2_RPC_URL")"
pk="$(normalize_bytes_output "$raw_pk")"
if [ "${#pk}" -ne 68 ]; then
  echo "L2 sequencerPublicKey is not a 33-byte compressed SEC1 key: $pk" >&2
  exit 1
fi

verify_input="$(cast concat-hex "$pk" "$seed" "$beta" "$pi")"
verify_output="$(cast call "$VERIFY_PRECOMPILE" --data "$verify_input" --rpc-url "$L2_RPC_URL")"
case "$verify_output" in
  0x01|0x0000000000000000000000000000000000000000000000000000000000000001)
    ;;
  *)
    echo "ECVRF precompile verification failed" >&2
    echo "  output: $verify_output" >&2
    exit 1
    ;;
esac

echo "[trh-vrf-proof] ok"
echo "  L2 RPC:        $L2_RPC_URL"
echo "  VRF predeploy: $VRF_ADDR"
echo "  precompile:    $VERIFY_PRECOMPILE"
echo "  result nonce:  $RESULT_NONCE"
echo "  public key:    $pk"
echo "  seed:          $seed"
echo "  beta:          $beta"
