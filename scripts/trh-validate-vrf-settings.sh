#!/usr/bin/env bash
set -euo pipefail

SETTINGS_FILE="${1:-deploy/trh/settings.example.json}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

command -v jq >/dev/null 2>&1 || {
  echo "missing required command: jq" >&2
  exit 1
}

if [ "$SETTINGS_FILE" = "-" ]; then
  SETTINGS_FILE="/dev/stdin"
elif [ ! -f "$SETTINGS_FILE" ]; then
  if [ -f "$ROOT/$SETTINGS_FILE" ]; then
    SETTINGS_FILE="$ROOT/$SETTINGS_FILE"
  else
    echo "settings file not found: $SETTINGS_FILE" >&2
    exit 1
  fi
fi

jq -e '
  def is_addr:
    type == "string" and test("^0x[0-9a-fA-F]{40}$");
  def is_pk:
    type == "string" and test("^0x(02|03)[0-9a-fA-F]{64}$");
  def is_hex_quantity:
    type == "string" and test("^0x[0-9a-fA-F]+$");

  (.stack | type == "string" and length > 0) and
  .features.enshrinedVrf == true and
  .enshrinedVrf.mode == "tee" and
  (.enshrinedVrf.teeEndpoint | type == "string" and length > 0) and
  (.enshrinedVrf.publicKey | is_pk) and
  (.enshrinedVrf.enshrinedVrfTime | type == "number" and . >= 0) and
  (.enshrinedVrf.l2GenesisEnshrainedVRFTimeOffset | is_hex_quantity) and
  .enshrinedVrf.predeploy == "0x42000000000000000000000000000000000000f0" and
  .enshrinedVrf.verifyPrecompile == "0x0000000000000000000000000000000000000101" and
  .enshrinedVrf.setL1VRFPublicKey == true
' "$SETTINGS_FILE" >/dev/null

echo "[settings] ok: $SETTINGS_FILE"
