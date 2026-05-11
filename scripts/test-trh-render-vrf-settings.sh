#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PK="0x032c8c31fc9f990c6b55e3865a184a4ce50e09481f2eaeb3e60ec1cea13a6ae645"
ENDPOINT="unix:///var/run/vrf-enclave/vrf.sock"
EIF_URI="0123456789.dkr.ecr.ap-northeast-2.amazonaws.com/tokamak/vrf-enclave:nitro-v0.1.0"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# 1. Missing VRF_TEE_ENDPOINT must fail.
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

# 2. VRF_MODE=local must be rejected.
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

# 3. Default Unix-socket render still validates and omits the AWS block.
ENV_FILE=/dev/null \
VRF_MODE=tee \
VRF_TEE_ENDPOINT="$ENDPOINT" \
VRF_PUBLIC_KEY="$PK" \
"$ROOT/scripts/trh-render-vrf-settings.sh" >"$TMP_DIR/settings.json"

"$ROOT/scripts/trh-validate-vrf-settings.sh" "$TMP_DIR/settings.json" >/dev/null
jq -e \
  --arg endpoint "$ENDPOINT" \
  --arg pk "$PK" \
  '.stack == "thanos" and .enshrinedVrf.teeEndpoint == $endpoint and .enshrinedVrf.publicKey == $pk and (.enshrinedVrf | has("aws") | not)' \
  "$TMP_DIR/settings.json" >/dev/null

# 4. AWS=nitro without instance type must fail.
set +e
ENV_FILE=/dev/null \
VRF_MODE=tee \
VRF_TEE_ENDPOINT="$ENDPOINT" \
VRF_PUBLIC_KEY="$PK" \
VRF_AWS_ENCLAVE_TYPE=nitro \
VRF_AWS_EIF_IMAGE_URI="$EIF_URI" \
"$ROOT/scripts/trh-render-vrf-settings.sh" >"$TMP_DIR/aws-no-instance.json" 2>"$TMP_DIR/aws-no-instance.err"
status_no_instance=$?
set -e
if [ "$status_no_instance" -eq 0 ]; then
  echo "settings renderer accepted nitro without VRF_AWS_INSTANCE_TYPE" >&2
  exit 1
fi
grep -q "VRF_AWS_INSTANCE_TYPE" "$TMP_DIR/aws-no-instance.err"

# 5. AWS=nitro without EIF image URI must fail.
set +e
ENV_FILE=/dev/null \
VRF_MODE=tee \
VRF_TEE_ENDPOINT="$ENDPOINT" \
VRF_PUBLIC_KEY="$PK" \
VRF_AWS_ENCLAVE_TYPE=nitro \
VRF_AWS_INSTANCE_TYPE=m5.xlarge \
"$ROOT/scripts/trh-render-vrf-settings.sh" >"$TMP_DIR/aws-no-eif.json" 2>"$TMP_DIR/aws-no-eif.err"
status_no_eif=$?
set -e
if [ "$status_no_eif" -eq 0 ]; then
  echo "settings renderer accepted nitro without VRF_AWS_EIF_IMAGE_URI" >&2
  exit 1
fi
grep -q "VRF_AWS_EIF_IMAGE_URI" "$TMP_DIR/aws-no-eif.err"

# 6. AWS=nitro happy path renders, validates, and contains the aws block with default CID/port.
ENV_FILE=/dev/null \
VRF_MODE=tee \
VRF_TEE_ENDPOINT="$ENDPOINT" \
VRF_PUBLIC_KEY="$PK" \
VRF_AWS_ENCLAVE_TYPE=nitro \
VRF_AWS_INSTANCE_TYPE=m5.xlarge \
VRF_AWS_EIF_IMAGE_URI="$EIF_URI" \
"$ROOT/scripts/trh-render-vrf-settings.sh" >"$TMP_DIR/aws-settings.json"

"$ROOT/scripts/trh-validate-vrf-settings.sh" "$TMP_DIR/aws-settings.json" >/dev/null
jq -e \
  --arg eif "$EIF_URI" \
  '.enshrinedVrf.aws.enclaveType == "nitro" and
   .enshrinedVrf.aws.instanceType == "m5.xlarge" and
   .enshrinedVrf.aws.enclaveCID == 16 and
   .enshrinedVrf.aws.vsockPort == 5000 and
   .enshrinedVrf.aws.eifImageURI == $eif' \
  "$TMP_DIR/aws-settings.json" >/dev/null

# 7. AWS=nitro with custom CID/port honors env overrides.
ENV_FILE=/dev/null \
VRF_MODE=tee \
VRF_TEE_ENDPOINT="$ENDPOINT" \
VRF_PUBLIC_KEY="$PK" \
VRF_AWS_ENCLAVE_TYPE=nitro \
VRF_AWS_INSTANCE_TYPE=m5.xlarge \
VRF_AWS_EIF_IMAGE_URI="$EIF_URI" \
VRF_AWS_ENCLAVE_CID=32 \
VRF_AWS_VSOCK_PORT=6001 \
"$ROOT/scripts/trh-render-vrf-settings.sh" >"$TMP_DIR/aws-custom.json"

"$ROOT/scripts/trh-validate-vrf-settings.sh" "$TMP_DIR/aws-custom.json" >/dev/null
jq -e '.enshrinedVrf.aws.enclaveCID == 32 and .enshrinedVrf.aws.vsockPort == 6001' "$TMP_DIR/aws-custom.json" >/dev/null

echo "[test-trh-render-vrf-settings] ok"
