#!/usr/bin/env bash
set -euo pipefail

POLICY_FILE="${1:-deploy/trh/attestation-policy.example.json}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRODUCTION="${PRODUCTION:-0}"

command -v jq >/dev/null 2>&1 || {
  echo "missing required command: jq" >&2
  exit 1
}

if [ ! -f "$POLICY_FILE" ]; then
  if [ -f "$ROOT/$POLICY_FILE" ]; then
    POLICY_FILE="$ROOT/$POLICY_FILE"
  else
    echo "attestation policy file not found: $POLICY_FILE" >&2
    exit 1
  fi
fi

mode="$(jq -r '.mode' "$POLICY_FILE")"

case "$mode" in
  nitro)
    jq -e '
      (.policyId | type == "string" and length > 0) and
      (.mode == "nitro") and
      (.status | type == "string" and length > 0) and
      .publicKeyBinding.field == "public_key" and
      .publicKeyBinding.encoding == "compressed-sec1" and
      .publicKeyBinding.lengthBytes == 33 and
      (.requiredClaims.pcr0 | type == "string" and length > 0) and
      (.requiredClaims.pcr1 | type == "string" and length > 0) and
      (.requiredClaims.pcr2 | type == "string" and length > 0) and
      (.requiredClaims.pcr8 | type == "string" and length > 0) and
      .requiredClaims.reportDataIncludesPublicKey == true and
      .requiredClaims.debugDisabled == true and
      (.releaseRequirements | type == "array" and length > 0)
    ' "$POLICY_FILE" >/dev/null
    ;;
  sgx|tdx|sev-snp)
    jq -e '
      (.policyId | type == "string" and length > 0) and
      (.mode | IN("sgx", "tdx", "sev-snp")) and
      (.status | type == "string" and length > 0) and
      .publicKeyBinding.field == "public_key" and
      .publicKeyBinding.encoding == "compressed-sec1" and
      .publicKeyBinding.lengthBytes == 33 and
      (.requiredClaims.mrSignerOrEquivalent | type == "string" and length > 0) and
      (.requiredClaims.mrEnclaveOrEquivalent | type == "string" and length > 0) and
      .requiredClaims.reportDataIncludesPublicKey == true and
      .requiredClaims.debugDisabled == true and
      (.releaseRequirements | type == "array" and length > 0)
    ' "$POLICY_FILE" >/dev/null
    ;;
  *)
    echo "unsupported attestation policy mode: $mode" >&2
    exit 1
    ;;
esac

if [ "$PRODUCTION" = "1" ]; then
  case "$mode" in
    nitro)
      jq -e '
        .status != "example-only" and
        (.requiredClaims.pcr0 | test("^0x[0-9a-fA-F]{96}$")) and
        (.requiredClaims.pcr1 | test("^0x[0-9a-fA-F]{96}$")) and
        (.requiredClaims.pcr2 | test("^0x[0-9a-fA-F]{96}$")) and
        (.requiredClaims.pcr8 | test("^0x[0-9a-fA-F]{96}$"))
      ' "$POLICY_FILE" >/dev/null
      ;;
    sgx|tdx|sev-snp)
      jq -e '
        .status != "example-only" and
        (.requiredClaims.mrSignerOrEquivalent | test("^0x[0-9a-fA-F]{64,}$")) and
        (.requiredClaims.mrEnclaveOrEquivalent | test("^0x[0-9a-fA-F]{64,}$"))
      ' "$POLICY_FILE" >/dev/null
      ;;
  esac
fi

echo "[attestation-policy] ok: $POLICY_FILE"
