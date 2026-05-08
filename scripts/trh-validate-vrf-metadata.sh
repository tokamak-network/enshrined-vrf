#!/usr/bin/env bash
set -euo pipefail

METADATA_FILE="${1:-deploy/trh/metadata.example.json}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

command -v jq >/dev/null 2>&1 || {
  echo "missing required command: jq" >&2
  exit 1
}

if [ ! -f "$METADATA_FILE" ]; then
  if [ -f "$ROOT/$METADATA_FILE" ]; then
    METADATA_FILE="$ROOT/$METADATA_FILE"
  else
    echo "metadata file not found: $METADATA_FILE" >&2
    exit 1
  fi
fi

jq -e '
  def is_addr:
    type == "string" and test("^0x[0-9a-fA-F]{40}$");
  def is_pk:
    type == "string" and test("^0x(02|03)[0-9a-fA-F]{64}$");

  .features.enshrinedVrf == true and
  .enshrinedVrf.mode == "tee" and
  .enshrinedVrf.vrfPredeploy == "0x42000000000000000000000000000000000000f0" and
  .enshrinedVrf.vrfVerifyPrecompile == "0x0000000000000000000000000000000000000101" and
  (.enshrinedVrf.vrfPublicKey | is_pk) and
  (.chainId | type == "number") and
  (.enshrinedVrf.readinessCommand | type == "string") and
  (.enshrinedVrf.proofVerificationCommand | type == "string") and
  (.enshrinedVrf.monitoringCommand | type == "string")
' "$METADATA_FILE" >/dev/null

echo "[metadata] ok: $METADATA_FILE"
