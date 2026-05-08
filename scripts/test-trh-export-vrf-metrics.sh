#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PK="0x032c8c31fc9f990c6b55e3865a184a4ce50e09481f2eaeb3e60ec1cea13a6ae645"

cat > "$TMP_DIR/cast" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

VRF_ADDR="${VRF_ADDR:-0x42000000000000000000000000000000000000f0}"
VERIFY_PRECOMPILE="${VERIFY_PRECOMPILE:-0x0000000000000000000000000000000000000101}"
PK="0x032c8c31fc9f990c6b55e3865a184a4ce50e09481f2eaeb3e60ec1cea13a6ae645"
SEED="0x1111111111111111111111111111111111111111111111111111111111111111"
BETA="0x2222222222222222222222222222222222222222222222222222222222222222"
PI="0x$(printf '%162s' '' | tr ' ' '3')"

case "$1" in
  chain-id)
    echo "901005"
    ;;
  code)
    test "$2" = "$VRF_ADDR"
    echo "0x6000"
    ;;
  call)
    case "$2" in
      "$VRF_ADDR")
        case "${3:-}" in
          "commitNonce()(uint256)")
            echo "0x02"
            ;;
          "sequencerPublicKey()(bytes)")
            echo "$PK"
            ;;
          "getRandomness()(uint256)")
            echo "0x7b"
            ;;
          --data)
            echo "0xencoded-result"
            ;;
          *)
            echo "unexpected VRF call: $*" >&2
            exit 1
            ;;
        esac
        ;;
      "$VERIFY_PRECOMPILE")
        if [ "${MOCK_PROOF_FAIL:-0}" = "1" ]; then
          echo "0x00"
        else
          echo "0x0000000000000000000000000000000000000000000000000000000000000001"
        fi
        ;;
      *)
        echo "unexpected call target: $*" >&2
        exit 1
        ;;
    esac
    ;;
  to-dec)
    case "$2" in
      0x02) echo "2" ;;
      *) echo "unexpected to-dec input: $2" >&2; exit 1 ;;
    esac
    ;;
  calldata)
    test "$2" = "getResult(uint256)"
    test "$3" = "1"
    echo "0xgetresult"
    ;;
  abi-decode)
    test "$2" = "getResult(uint256)(bytes32,bytes32,bytes)"
    printf '%s\n%s\n%s\n' "$SEED" "$BETA" "$PI"
    ;;
  concat-hex)
    test "$2" = "$PK"
    test "$3" = "$SEED"
    test "$4" = "$BETA"
    test "$5" = "$PI"
    echo "0xjoined-proof"
    ;;
  *)
    echo "unexpected cast command: $*" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$TMP_DIR/cast"

assert_metric() {
  local file="$1"
  local name="$2"
  local value="$3"
  if ! grep -qx "${name} ${value}" "$file"; then
    echo "missing metric: ${name} ${value}" >&2
    echo "--- output ---" >&2
    cat "$file" >&2
    exit 1
  fi
}

OUT_OK="$TMP_DIR/metrics-ok.prom"
PATH="$TMP_DIR:$PATH" \
L2_RPC_URL=http://mock-l2 \
EXPECTED_VRF_PUBLIC_KEY="$PK" \
"$ROOT/scripts/trh-export-vrf-metrics.sh" > "$OUT_OK"

assert_metric "$OUT_OK" "enshrined_vrf_l2_chain_id" "901005"
assert_metric "$OUT_OK" "enshrined_vrf_predeploy_code_present" "1"
assert_metric "$OUT_OK" "enshrined_vrf_commit_nonce" "2"
assert_metric "$OUT_OK" "enshrined_vrf_l2_public_key_set" "1"
assert_metric "$OUT_OK" "enshrined_vrf_public_key_match" "1"
assert_metric "$OUT_OK" "enshrined_vrf_randomness_call_ok" "1"
assert_metric "$OUT_OK" "enshrined_vrf_proof_verify_ok" "1"

OUT_FAIL="$TMP_DIR/metrics-fail.prom"
PATH="$TMP_DIR:$PATH" \
L2_RPC_URL=http://mock-l2 \
EXPECTED_VRF_PUBLIC_KEY="$PK" \
MOCK_PROOF_FAIL=1 \
"$ROOT/scripts/trh-export-vrf-metrics.sh" > "$OUT_FAIL"

assert_metric "$OUT_FAIL" "enshrined_vrf_proof_verify_ok" "0"

echo "[test-trh-export-vrf-metrics] ok"
