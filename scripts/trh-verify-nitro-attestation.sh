#!/usr/bin/env bash
set -euo pipefail

# Standalone Nitro / Nitro-mock verifier. Designed to be wired into
# trh-attest-vrf-enclave.sh as PLATFORM_ATTESTATION_VERIFIER:
#
#   VRF_ATTESTATION_MODE=nitro-mock \
#   PLATFORM_ATTESTATION_VERIFIER="$ROOT/scripts/trh-verify-nitro-attestation.sh" \
#   NITRO_ALLOW_DEV=1 \
#   ./scripts/trh-attest-vrf-enclave.sh
#
# The script reads the (mode, public key, challenge, report) tuple from
# the env vars trh-attest-vrf-enclave.sh sets, optionally pulls expected
# PCRs from a policy file via VRF_ATTESTATION_POLICY_FILE, and shells
# the static verifier in vrf-prove. It does NOT contact the enclave.
#
# For mode=nitro the script REQUIRES a real AWS Nitro doc; the static
# verifier rejects dev signatures unless NITRO_ALLOW_DEV=1 is set on
# nitro-mock. AWS Nitro root CA chain validation lives in the next PR
# that wires the on-EC2 NSM bridge.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

: "${VRF_ATTESTATION_MODE:?VRF_ATTESTATION_MODE is required}"
: "${VRF_ATTESTATION_PUBLIC_KEY:?VRF_ATTESTATION_PUBLIC_KEY is required}"
: "${VRF_ATTESTATION_CHALLENGE:?VRF_ATTESTATION_CHALLENGE is required}"
: "${VRF_ATTESTATION_REPORT:?VRF_ATTESTATION_REPORT is required}"

case "$VRF_ATTESTATION_MODE" in
  nitro|nitro-mock) ;;
  *)
    echo "trh-verify-nitro-attestation: VRF_ATTESTATION_MODE=$VRF_ATTESTATION_MODE not supported (want nitro | nitro-mock)" >&2
    exit 1
    ;;
esac

allow_dev_flag=""
if [ "$VRF_ATTESTATION_MODE" = "nitro-mock" ]; then
  if [ "${NITRO_ALLOW_DEV:-0}" != "1" ]; then
    echo "trh-verify-nitro-attestation: nitro-mock requires NITRO_ALLOW_DEV=1" >&2
    exit 1
  fi
  allow_dev_flag="-nitro-allow-dev"
fi

pcr_arg=""
if [ -n "${VRF_ATTESTATION_POLICY_FILE:-}" ]; then
  command -v jq >/dev/null 2>&1 || { echo "jq is required to inspect VRF_ATTESTATION_POLICY_FILE" >&2; exit 1; }
  pcr_arg="$(jq -r '
    .requiredClaims
    | to_entries
    | map(select(.key | startswith("pcr")) | "\(.key | ltrimstr("pcr"))=\(.value)")
    | join(",")
  ' "$VRF_ATTESTATION_POLICY_FILE")"
fi

if [ "${BUILD_VRF_PROVE:-1}" = "1" ] || [ ! -x "$ROOT/bin/vrf-prove" ]; then
  (cd "$ROOT" && go build -o "$ROOT/bin/vrf-prove" ./vrf-enclave/cmd/vrf-prove)
fi

cmd=(
  "$ROOT/bin/vrf-prove"
  -verify-nitro
  -attestation-mode "$VRF_ATTESTATION_MODE"
  -nitro-report "$VRF_ATTESTATION_REPORT"
  -nitro-public-key "$VRF_ATTESTATION_PUBLIC_KEY"
  -attestation-challenge "$VRF_ATTESTATION_CHALLENGE"
)
if [ -n "$pcr_arg" ]; then
  cmd+=( -nitro-expected-pcrs "$pcr_arg" )
fi
if [ -n "$allow_dev_flag" ]; then
  cmd+=( "$allow_dev_flag" )
fi

"${cmd[@]}"
echo "[trh-verify-nitro-attestation] ok"
