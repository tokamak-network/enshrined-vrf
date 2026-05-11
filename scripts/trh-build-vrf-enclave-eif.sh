#!/usr/bin/env bash
set -euo pipefail

# Builds an AWS Nitro Enclave EIF (Enclave Image File) from the VRF
# enclave Docker image and writes the platform measurements (PCR0..PCR2,
# PCR8) to a sidecar JSON. Optionally splices the same measurements into
# an attestation policy template so production gates can match the EIF
# bit-for-bit.
#
# Requires aws-nitro-enclaves-cli (nitro-cli) on the host. Outside an
# EC2 Nitro instance this is unusual; the script prints a helpful note
# and exits 0 when SKIP_IF_MISSING_NITRO_CLI=1 so CI on non-Nitro
# runners can call it without failing.
#
# Env:
#   IMAGE_REPOSITORY  Docker repo for the runtime image (default tokamaknetwork/vrf-enclave)
#   IMAGE_TAG         Tag for the runtime image (default nitro-dev)
#   PLATFORM          Build platform passed to docker (default linux/amd64; Nitro is amd64-only today)
#   EIF_OUTPUT        Path to write the EIF (default deploy/trh/build/vrf-enclave.eif)
#   MEASUREMENTS_OUT  Path to write JSON measurements (default deploy/trh/build/vrf-enclave.measurements.json)
#   POLICY_FILE       Optional attestation-policy.json to splice PCR values into (in-place)
#   POLICY_ID         Optional override for the spliced policy id
#   SKIP_IF_MISSING_NITRO_CLI=1  Print warning and exit 0 instead of failing when nitro-cli is missing
#   SKIP_DOCKER_BUILD=1          Reuse an already-built image instead of running trh-build-vrf-enclave-image.sh

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_REPOSITORY="${IMAGE_REPOSITORY:-tokamaknetwork/vrf-enclave}"
IMAGE_TAG="${IMAGE_TAG:-nitro-dev}"
IMAGE="${IMAGE_REPOSITORY}:${IMAGE_TAG}"
PLATFORM="${PLATFORM:-linux/amd64}"
EIF_OUTPUT="${EIF_OUTPUT:-$ROOT/deploy/trh/build/vrf-enclave.eif}"
MEASUREMENTS_OUT="${MEASUREMENTS_OUT:-$ROOT/deploy/trh/build/vrf-enclave.measurements.json}"
POLICY_FILE="${POLICY_FILE:-}"
POLICY_ID="${POLICY_ID:-}"
SKIP_IF_MISSING_NITRO_CLI="${SKIP_IF_MISSING_NITRO_CLI:-0}"
SKIP_DOCKER_BUILD="${SKIP_DOCKER_BUILD:-0}"

mkdir -p "$(dirname "$EIF_OUTPUT")"

if ! command -v nitro-cli >/dev/null 2>&1; then
  if [ "$SKIP_IF_MISSING_NITRO_CLI" = "1" ]; then
    echo "[trh-build-vrf-enclave-eif] nitro-cli not found; SKIP_IF_MISSING_NITRO_CLI=1 -> skipping (PCR splicing not performed)" >&2
    exit 0
  fi
  cat >&2 <<'NOTE'
[trh-build-vrf-enclave-eif] nitro-cli is required to build the AWS Nitro EIF.

Install on Amazon Linux 2 / Amazon Linux 2023:

  sudo dnf install -y aws-nitro-enclaves-cli aws-nitro-enclaves-cli-devel
  sudo usermod -aG ne "$USER"; sudo systemctl enable --now nitro-enclaves-allocator.service

Then re-run this script. To probe locally without nitro-cli, set
SKIP_IF_MISSING_NITRO_CLI=1 to no-op cleanly.
NOTE
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "missing required command: jq" >&2
  exit 1
fi
if ! command -v docker >/dev/null 2>&1; then
  echo "missing required command: docker" >&2
  exit 1
fi

if [ "$SKIP_DOCKER_BUILD" != "1" ]; then
  echo "[trh-build-vrf-enclave-eif] building runtime image $IMAGE for $PLATFORM"
  IMAGE_REPOSITORY="$IMAGE_REPOSITORY" IMAGE_TAG="$IMAGE_TAG" PLATFORM="$PLATFORM" PUSH=0 \
    "$ROOT/scripts/trh-build-vrf-enclave-image.sh" >/dev/null
fi

echo "[trh-build-vrf-enclave-eif] building EIF $EIF_OUTPUT from $IMAGE"
nitro_cli_out="$(nitro-cli build-enclave --docker-uri "$IMAGE" --output-file "$EIF_OUTPUT")"
echo "$nitro_cli_out"

# nitro-cli emits a JSON blob containing Measurements.{HashAlgorithm,PCR0,PCR1,PCR2,PCR8}.
measurements="$(printf '%s' "$nitro_cli_out" | jq -e '.Measurements')"
pcr0="$(printf '%s' "$measurements" | jq -r '.PCR0 // empty')"
pcr1="$(printf '%s' "$measurements" | jq -r '.PCR1 // empty')"
pcr2="$(printf '%s' "$measurements" | jq -r '.PCR2 // empty')"
pcr8="$(printf '%s' "$measurements" | jq -r '.PCR8 // empty')"

if [ -z "$pcr0" ] || [ -z "$pcr1" ] || [ -z "$pcr2" ]; then
  echo "nitro-cli output did not include PCR0/PCR1/PCR2 measurements" >&2
  exit 1
fi

# Normalize to 0x-prefixed hex. PCR8 is empty when the EIF is unsigned;
# downstream policy validation requires a real PCR8 for signed-enclave
# enforcement, so fall back to 48 zero bytes and flag the build as
# unsigned in the sidecar JSON.
normalize() { printf '0x%s' "$(printf '%s' "$1" | tr 'A-Z' 'a-z' | sed 's/^0x//')"; }

pcr0_hex="$(normalize "$pcr0")"
pcr1_hex="$(normalize "$pcr1")"
pcr2_hex="$(normalize "$pcr2")"
if [ -n "$pcr8" ]; then
  pcr8_hex="$(normalize "$pcr8")"
  signed_enclave=true
else
  pcr8_hex="0x$(printf '00%.0s' $(seq 1 48))"
  signed_enclave=false
fi

jq -n \
  --arg image "$IMAGE" \
  --arg eif "$EIF_OUTPUT" \
  --arg pcr0 "$pcr0_hex" \
  --arg pcr1 "$pcr1_hex" \
  --arg pcr2 "$pcr2_hex" \
  --arg pcr8 "$pcr8_hex" \
  --argjson signed "$signed_enclave" \
  '{
    image: $image,
    eif: $eif,
    pcrs: { pcr0: $pcr0, pcr1: $pcr1, pcr2: $pcr2, pcr8: $pcr8 },
    signedEnclave: $signed
  }' >"$MEASUREMENTS_OUT"
echo "[trh-build-vrf-enclave-eif] wrote measurements $MEASUREMENTS_OUT"

if [ -n "$POLICY_FILE" ]; then
  if [ ! -f "$POLICY_FILE" ]; then
    echo "POLICY_FILE not found: $POLICY_FILE" >&2
    exit 1
  fi
  tmp_policy="$(mktemp)"
  jq \
    --arg pcr0 "$pcr0_hex" \
    --arg pcr1 "$pcr1_hex" \
    --arg pcr2 "$pcr2_hex" \
    --arg pcr8 "$pcr8_hex" \
    --arg policyId "${POLICY_ID:-$(jq -r '.policyId' "$POLICY_FILE")}" \
    '
    .policyId = $policyId
    | .mode = "nitro"
    | .requiredClaims.pcr0 = $pcr0
    | .requiredClaims.pcr1 = $pcr1
    | .requiredClaims.pcr2 = $pcr2
    | .requiredClaims.pcr8 = $pcr8
    | .requiredClaims.reportDataIncludesPublicKey = true
    | .requiredClaims.debugDisabled = true
    ' "$POLICY_FILE" >"$tmp_policy"
  mv "$tmp_policy" "$POLICY_FILE"
  echo "[trh-build-vrf-enclave-eif] spliced PCRs into $POLICY_FILE"
fi

echo "[trh-build-vrf-enclave-eif] ok"
