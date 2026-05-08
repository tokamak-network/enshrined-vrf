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

jq -e '
  def is_measurement:
    type == "string" and test("^0x[0-9a-fA-F]{64,}$");

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

if [ "$PRODUCTION" = "1" ]; then
  jq -e '
    def is_measurement:
      type == "string" and test("^0x[0-9a-fA-F]{64,}$");

    .status != "example-only" and
    (.requiredClaims.mrSignerOrEquivalent | is_measurement) and
    (.requiredClaims.mrEnclaveOrEquivalent | is_measurement)
  ' "$POLICY_FILE" >/dev/null
fi

echo "[attestation-policy] ok: $POLICY_FILE"
