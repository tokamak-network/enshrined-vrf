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
  def is_nitro_instance_type:
    type == "string" and
    test("^(m5|m5n|m5d|m5dn|m5zn|m6i|m6in|m7i|c5|c5d|c5n|c6i|c6id|c6in|c7i|r5|r5d|r5n|r5dn|r5b|r6i|r6id|r6in|r7i|x2idn|x2iedn|x2iezn|i3en|i4i|z1d|p3dn|p4d|p4de|p5)\\.(metal|((4|6|8|12|16|24|32|48)?xlarge|large))$");

  (.stack | type == "string" and length > 0) and
  .features.enshrinedVrf == true and
  .enshrinedVrf.mode == "tee" and
  (.enshrinedVrf.teeEndpoint | type == "string" and length > 0) and
  (.enshrinedVrf.publicKey | is_pk) and
  (.enshrinedVrf.enshrinedVrfTime | type == "number" and . >= 0) and
  (.enshrinedVrf.l2GenesisEnshrainedVRFTimeOffset | is_hex_quantity) and
  .enshrinedVrf.predeploy == "0x42000000000000000000000000000000000000f0" and
  .enshrinedVrf.verifyPrecompile == "0x0000000000000000000000000000000000000101" and
  .enshrinedVrf.setL1VRFPublicKey == true and
  (
    (.enshrinedVrf | has("aws") | not) or
    (
      .enshrinedVrf.aws.enclaveType == "none"
    ) or
    (
      .enshrinedVrf.aws.enclaveType == "nitro" and
      (.enshrinedVrf.aws.instanceType | is_nitro_instance_type) and
      (.enshrinedVrf.aws.enclaveCpuCount | type == "number" and . >= 2 and . <= 96) and
      (.enshrinedVrf.aws.enclaveMemoryMiB | type == "number" and . >= 512) and
      (.enshrinedVrf.aws.enclaveCID | type == "number" and . >= 3) and
      (.enshrinedVrf.aws.vsockPort | type == "number" and . >= 1 and . <= 65535) and
      (.enshrinedVrf.aws.eifImageURI | type == "string" and length > 0)
    )
  )
' "$SETTINGS_FILE" >/dev/null

echo "[settings] ok: $SETTINGS_FILE"
