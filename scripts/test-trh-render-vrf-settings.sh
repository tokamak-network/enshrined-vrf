#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PK="0x032c8c31fc9f990c6b55e3865a184a4ce50e09481f2eaeb3e60ec1cea13a6ae645"
ENDPOINT="unix:///var/run/vrf-enclave/vrf.sock"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

set +e
ENV_FILE=/dev/null \
VRF_MODE=tee \
VRF_PUBLIC_KEY="$PK" \
"$ROOT/scripts/trh-render-vrf-settings.sh" >"$TMP_DIR/no-endpoint.json" 2>"$TMP_DIR/no-endpoint.err"
status_no_endpoint=$?
set -e
if [ "$status_no_endpoint" -eq 0 ]; then
  echo "settings renderer accepted missing VRF_TEE_ENDPOINT" >&2
  exit 1
fi
grep -q "VRF_TEE_ENDPOINT" "$TMP_DIR/no-endpoint.err"

set +e
ENV_FILE=/dev/null \
VRF_MODE=local \
VRF_TEE_ENDPOINT="$ENDPOINT" \
VRF_PUBLIC_KEY="$PK" \
"$ROOT/scripts/trh-render-vrf-settings.sh" >"$TMP_DIR/local-mode.json" 2>"$TMP_DIR/local-mode.err"
status_local=$?
set -e
if [ "$status_local" -eq 0 ]; then
  echo "settings renderer accepted VRF_MODE=local" >&2
  exit 1
fi
grep -q "VRF_MODE=local" "$TMP_DIR/local-mode.err"

ENV_FILE=/dev/null \
VRF_MODE=tee \
VRF_TEE_ENDPOINT="$ENDPOINT" \
VRF_PUBLIC_KEY="$PK" \
"$ROOT/scripts/trh-render-vrf-settings.sh" >"$TMP_DIR/settings.json"

"$ROOT/scripts/trh-validate-vrf-settings.sh" "$TMP_DIR/settings.json" >/dev/null
jq -e \
  --arg endpoint "$ENDPOINT" \
  --arg pk "$PK" \
  '.stack == "thanos" and .enshrinedVrf.teeEndpoint == $endpoint and .enshrinedVrf.publicKey == $pk' \
  "$TMP_DIR/settings.json" >/dev/null

echo "[test-trh-render-vrf-settings] ok"
