#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

"$ROOT/scripts/trh-validate-attestation-policy.sh" "$ROOT/deploy/trh/attestation-policy.example.json" >/dev/null

set +e
PRODUCTION=1 "$ROOT/scripts/trh-validate-attestation-policy.sh" "$ROOT/deploy/trh/attestation-policy.example.json" >"$TMP_DIR/example-prod.out" 2>"$TMP_DIR/example-prod.err"
example_prod_status=$?
set -e
if [ "$example_prod_status" -eq 0 ]; then
  echo "example-only attestation policy passed production validation" >&2
  exit 1
fi

jq '
  .status = "approved" |
  .requiredClaims.mrSignerOrEquivalent = "0x1111111111111111111111111111111111111111111111111111111111111111" |
  .requiredClaims.mrEnclaveOrEquivalent = "0x2222222222222222222222222222222222222222222222222222222222222222"
' "$ROOT/deploy/trh/attestation-policy.example.json" > "$TMP_DIR/policy.production.json"

PRODUCTION=1 "$ROOT/scripts/trh-validate-attestation-policy.sh" "$TMP_DIR/policy.production.json" >/dev/null

set +e
VRF_MODE=tee \
VRF_ATTESTATION_MODE=tdx \
VRF_TEE_ENDPOINT=unix:///var/run/vrf-enclave/vrf.sock \
VRF_PUBLIC_KEY=0x032c8c31fc9f990c6b55e3865a184a4ce50e09481f2eaeb3e60ec1cea13a6ae645 \
VRF_PLATFORM_ATTESTATION_IMPLEMENTED=1 \
IMAGE_TAG=v0.1.0 \
EXTERNAL_AUDIT_ID=audit-2026-ci \
VRF_ATTESTATION_POLICY_ID=wrong-policy \
VRF_ATTESTATION_POLICY_FILE="$TMP_DIR/policy.production.json" \
"$ROOT/scripts/trh-production-vrf-gate.sh" >"$TMP_DIR/gate-mismatch.out" 2>"$TMP_DIR/gate-mismatch.err"
gate_mismatch_status=$?
set -e
if [ "$gate_mismatch_status" -eq 0 ]; then
  echo "production gate accepted mismatched attestation policy id" >&2
  exit 1
fi
grep -q "does not match policy file id" "$TMP_DIR/gate-mismatch.err"

VRF_MODE=tee \
VRF_ATTESTATION_MODE=tdx \
VRF_TEE_ENDPOINT=unix:///var/run/vrf-enclave/vrf.sock \
VRF_PUBLIC_KEY=0x032c8c31fc9f990c6b55e3865a184a4ce50e09481f2eaeb3e60ec1cea13a6ae645 \
VRF_PLATFORM_ATTESTATION_IMPLEMENTED=1 \
IMAGE_TAG=v0.1.0 \
EXTERNAL_AUDIT_ID=audit-2026-ci \
VRF_ATTESTATION_POLICY_ID=tdx-game-l2-vrf-policy-v1 \
VRF_ATTESTATION_POLICY_FILE="$TMP_DIR/policy.production.json" \
"$ROOT/scripts/trh-production-vrf-gate.sh" >/dev/null

echo "[test-trh-attestation-policy] ok"
