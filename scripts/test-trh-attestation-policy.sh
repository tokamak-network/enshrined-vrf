#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# 1. Default (nitro) example must pass dev validation but fail production validation.
"$ROOT/scripts/trh-validate-attestation-policy.sh" "$ROOT/deploy/trh/attestation-policy.example.json" >/dev/null

set +e
PRODUCTION=1 "$ROOT/scripts/trh-validate-attestation-policy.sh" "$ROOT/deploy/trh/attestation-policy.example.json" >"$TMP_DIR/example-prod.out" 2>"$TMP_DIR/example-prod.err"
example_prod_status=$?
set -e
if [ "$example_prod_status" -eq 0 ]; then
  echo "example-only nitro attestation policy passed production validation" >&2
  exit 1
fi

# 2. A production-shaped nitro policy with real-looking PCRs must pass.
jq '
  .status = "approved" |
  .requiredClaims.pcr0 = "0x" + (
    "1111111111111111111111111111111111111111111111111111111111111111" +
    "11111111111111111111111111111111"
  ) |
  .requiredClaims.pcr1 = "0x" + (
    "2222222222222222222222222222222222222222222222222222222222222222" +
    "22222222222222222222222222222222"
  ) |
  .requiredClaims.pcr2 = "0x" + (
    "3333333333333333333333333333333333333333333333333333333333333333" +
    "33333333333333333333333333333333"
  ) |
  .requiredClaims.pcr8 = "0x" + (
    "4444444444444444444444444444444444444444444444444444444444444444" +
    "44444444444444444444444444444444"
  )
' "$ROOT/deploy/trh/attestation-policy.example.json" > "$TMP_DIR/policy.nitro.production.json"

PRODUCTION=1 "$ROOT/scripts/trh-validate-attestation-policy.sh" "$TMP_DIR/policy.nitro.production.json" >/dev/null

# Production gate must reject mismatched policy id, accept correct one.
set +e
VRF_MODE=tee \
VRF_ATTESTATION_MODE=nitro \
VRF_TEE_ENDPOINT=vsock://16:5000 \
VRF_PUBLIC_KEY=0x032c8c31fc9f990c6b55e3865a184a4ce50e09481f2eaeb3e60ec1cea13a6ae645 \
VRF_PLATFORM_ATTESTATION_IMPLEMENTED=1 \
IMAGE_TAG=v0.1.0 \
EXTERNAL_AUDIT_ID=audit-2026-ci \
VRF_ATTESTATION_POLICY_ID=wrong-policy \
VRF_ATTESTATION_POLICY_FILE="$TMP_DIR/policy.nitro.production.json" \
"$ROOT/scripts/trh-production-vrf-gate.sh" >"$TMP_DIR/gate-mismatch.out" 2>"$TMP_DIR/gate-mismatch.err"
gate_mismatch_status=$?
set -e
if [ "$gate_mismatch_status" -eq 0 ]; then
  echo "production gate accepted mismatched attestation policy id" >&2
  exit 1
fi
grep -q "does not match policy file id" "$TMP_DIR/gate-mismatch.err"

VRF_MODE=tee \
VRF_ATTESTATION_MODE=nitro \
VRF_TEE_ENDPOINT=vsock://16:5000 \
VRF_PUBLIC_KEY=0x032c8c31fc9f990c6b55e3865a184a4ce50e09481f2eaeb3e60ec1cea13a6ae645 \
VRF_PLATFORM_ATTESTATION_IMPLEMENTED=1 \
IMAGE_TAG=v0.1.0 \
EXTERNAL_AUDIT_ID=audit-2026-ci \
VRF_ATTESTATION_POLICY_ID=nitro-game-l2-vrf-policy-v1 \
VRF_ATTESTATION_POLICY_FILE="$TMP_DIR/policy.nitro.production.json" \
"$ROOT/scripts/trh-production-vrf-gate.sh" >/dev/null

# 3. nitro-mock must NEVER pass the production gate.
set +e
VRF_MODE=tee \
VRF_ATTESTATION_MODE=nitro-mock \
VRF_TEE_ENDPOINT=vsock://16:5000 \
VRF_PUBLIC_KEY=0x032c8c31fc9f990c6b55e3865a184a4ce50e09481f2eaeb3e60ec1cea13a6ae645 \
VRF_PLATFORM_ATTESTATION_IMPLEMENTED=1 \
IMAGE_TAG=v0.1.0 \
EXTERNAL_AUDIT_ID=audit-2026-ci \
VRF_ATTESTATION_POLICY_ID=nitro-game-l2-vrf-policy-v1 \
VRF_ATTESTATION_POLICY_FILE="$TMP_DIR/policy.nitro.production.json" \
"$ROOT/scripts/trh-production-vrf-gate.sh" >"$TMP_DIR/gate-mock.out" 2>"$TMP_DIR/gate-mock.err"
gate_mock_status=$?
set -e
if [ "$gate_mock_status" -eq 0 ]; then
  echo "production gate accepted nitro-mock attestation mode" >&2
  exit 1
fi
grep -q "is not production-safe" "$TMP_DIR/gate-mock.err"

# 4. Legacy TDX-shaped policy must still validate (dev), and gate against tdx mode.
cat > "$TMP_DIR/policy.tdx.example.json" <<'JSON'
{
  "policyId": "tdx-game-l2-vrf-policy-v1",
  "mode": "tdx",
  "status": "example-only",
  "publicKeyBinding": {
    "field": "public_key",
    "encoding": "compressed-sec1",
    "lengthBytes": 33
  },
  "requiredClaims": {
    "mrSignerOrEquivalent": "0x...",
    "mrEnclaveOrEquivalent": "0x...",
    "reportDataIncludesPublicKey": true,
    "debugDisabled": true
  },
  "releaseRequirements": [
    "platform quote verifier implemented",
    "quote verifier audited",
    "sealed key derives from platform identity",
    "VRF public key in SystemConfig matches attested enclave key"
  ]
}
JSON
"$ROOT/scripts/trh-validate-attestation-policy.sh" "$TMP_DIR/policy.tdx.example.json" >/dev/null

jq '
  .status = "approved" |
  .requiredClaims.mrSignerOrEquivalent = "0x1111111111111111111111111111111111111111111111111111111111111111" |
  .requiredClaims.mrEnclaveOrEquivalent = "0x2222222222222222222222222222222222222222222222222222222222222222"
' "$TMP_DIR/policy.tdx.example.json" > "$TMP_DIR/policy.tdx.production.json"

PRODUCTION=1 "$ROOT/scripts/trh-validate-attestation-policy.sh" "$TMP_DIR/policy.tdx.production.json" >/dev/null

VRF_MODE=tee \
VRF_ATTESTATION_MODE=tdx \
VRF_TEE_ENDPOINT=unix:///var/run/vrf-enclave/vrf.sock \
VRF_PUBLIC_KEY=0x032c8c31fc9f990c6b55e3865a184a4ce50e09481f2eaeb3e60ec1cea13a6ae645 \
VRF_PLATFORM_ATTESTATION_IMPLEMENTED=1 \
IMAGE_TAG=v0.1.0 \
EXTERNAL_AUDIT_ID=audit-2026-ci \
VRF_ATTESTATION_POLICY_ID=tdx-game-l2-vrf-policy-v1 \
VRF_ATTESTATION_POLICY_FILE="$TMP_DIR/policy.tdx.production.json" \
"$ROOT/scripts/trh-production-vrf-gate.sh" >/dev/null

echo "[test-trh-attestation-policy] ok"
