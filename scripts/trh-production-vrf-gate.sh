#!/usr/bin/env bash
set -euo pipefail

failures=0

fail() {
  failures=$((failures + 1))
  echo "[fail] $*" >&2
}

ok() {
  echo "[ok] $*"
}

require_nonempty() {
  local name="$1"
  local value="${!name:-}"
  if [ -z "$value" ]; then
    fail "$name is required for production VRF deployment"
  else
    ok "$name is set"
  fi
}

case "${VRF_MODE:-}" in
  tee)
    ok "VRF_MODE=tee"
    ;;
  "")
    fail "VRF_MODE is required and must be tee"
    ;;
  *)
    fail "VRF_MODE=${VRF_MODE} is not production-safe; expected tee"
    ;;
esac

case "${VRF_ATTESTATION_MODE:-}" in
  sgx|tdx|sev-snp)
    ok "VRF_ATTESTATION_MODE=${VRF_ATTESTATION_MODE}"
    ;;
  "")
    fail "VRF_ATTESTATION_MODE is required; expected sgx, tdx, or sev-snp"
    ;;
  none|dev)
    fail "VRF_ATTESTATION_MODE=${VRF_ATTESTATION_MODE} is not production-safe"
    ;;
  *)
    fail "unsupported VRF_ATTESTATION_MODE=${VRF_ATTESTATION_MODE}; expected sgx, tdx, or sev-snp"
    ;;
esac

require_nonempty VRF_TEE_ENDPOINT
require_nonempty VRF_PUBLIC_KEY
require_nonempty IMAGE_TAG
require_nonempty EXTERNAL_AUDIT_ID
require_nonempty VRF_ATTESTATION_POLICY_ID

if [ -n "${VRF_PUBLIC_KEY:-}" ] && [[ ! "$VRF_PUBLIC_KEY" =~ ^0x(02|03)[0-9a-fA-F]{64}$ ]]; then
  fail "VRF_PUBLIC_KEY must be a 33-byte compressed SEC1 key"
fi

case "${IMAGE_TAG:-}" in
  dev|latest|local|local-test|test)
    fail "IMAGE_TAG=${IMAGE_TAG} is not a pinned production release tag"
    ;;
  "")
    ;;
  *)
    ok "IMAGE_TAG=${IMAGE_TAG}"
    ;;
esac

if [ "${SET_L1_VRF_PUBLIC_KEY:-1}" = "0" ]; then
  fail "SET_L1_VRF_PUBLIC_KEY=0 would skip SystemConfig VRF public-key registration"
else
  ok "L1 VRF public-key registration enabled"
fi

if [ "${VRF_PLATFORM_ATTESTATION_IMPLEMENTED:-0}" != "1" ]; then
  fail "VRF_PLATFORM_ATTESTATION_IMPLEMENTED=1 is required; current dev enclave modes are not production-safe"
else
  ok "platform attestation implementation is enabled"
fi

if [ -n "${VRF_ATTESTATION_POLICY_FILE:-}" ]; then
  command -v jq >/dev/null 2>&1 || {
    fail "jq is required to inspect VRF_ATTESTATION_POLICY_FILE"
  }
  if ! PRODUCTION=1 "$(dirname "$0")/trh-validate-attestation-policy.sh" "$VRF_ATTESTATION_POLICY_FILE" >/dev/null; then
    fail "VRF_ATTESTATION_POLICY_FILE is not production-valid"
  else
    policy_id="$(jq -r '.policyId' "$VRF_ATTESTATION_POLICY_FILE")"
    policy_mode="$(jq -r '.mode' "$VRF_ATTESTATION_POLICY_FILE")"
    if [ "$policy_id" != "$VRF_ATTESTATION_POLICY_ID" ]; then
      fail "VRF_ATTESTATION_POLICY_ID=$VRF_ATTESTATION_POLICY_ID does not match policy file id $policy_id"
    else
      ok "attestation policy id matches"
    fi
    if [ "$policy_mode" != "$VRF_ATTESTATION_MODE" ]; then
      fail "VRF_ATTESTATION_MODE=$VRF_ATTESTATION_MODE does not match policy file mode $policy_mode"
    else
      ok "attestation policy mode matches"
    fi
  fi
fi

if [ "$failures" -ne 0 ]; then
  echo "[production-gate] failed: $failures failure(s)" >&2
  exit 1
fi

echo "[production-gate] ok"
