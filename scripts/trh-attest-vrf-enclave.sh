#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT/devnet/sepolia/.env}"

if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

: "${VRF_TEE_ENDPOINT:?set VRF_TEE_ENDPOINT}"

VRF_ATTESTATION_MODE="${VRF_ATTESTATION_MODE:-dev}"

make_challenge() {
  if [ -n "${VRF_ATTESTATION_CHALLENGE:-}" ]; then
    printf '%s\n' "${VRF_ATTESTATION_CHALLENGE#0x}"
    return 0
  fi
  od -An -N32 -tx1 /dev/urandom | tr -d ' \n'
  printf '\n'
}

if [ "${BUILD_VRF_PROVE:-1}" = "1" ] || [ ! -x "$ROOT/bin/vrf-prove" ]; then
  (cd "$ROOT" && go build -o "$ROOT/bin/vrf-prove" ./vrf-enclave/cmd/vrf-prove)
fi

challenge="$(make_challenge)"
if ! printf '%s' "$challenge" | grep -Eq '^[0-9a-fA-F]{64}$'; then
  echo "VRF_ATTESTATION_CHALLENGE must be a 32-byte hex string" >&2
  exit 1
fi

case "$VRF_ATTESTATION_MODE" in
  dev)
    cli_mode=dev
    ;;
  raw)
    cli_mode=raw
    ;;
  sgx|tdx|sev-snp)
    cli_mode=raw
    : "${PLATFORM_ATTESTATION_VERIFIER:?set PLATFORM_ATTESTATION_VERIFIER for $VRF_ATTESTATION_MODE attestation}"
    ;;
  none|"")
    echo "VRF_ATTESTATION_MODE=$VRF_ATTESTATION_MODE does not provide attestation" >&2
    exit 1
    ;;
  *)
    echo "unsupported VRF_ATTESTATION_MODE=$VRF_ATTESTATION_MODE (expected dev, raw, sgx, tdx, or sev-snp)" >&2
    exit 1
    ;;
esac

attestation="$("$ROOT/bin/vrf-prove" \
  -tee-endpoint "$VRF_TEE_ENDPOINT" \
  -public-key-only \
  -attest \
  -attestation-mode "$cli_mode" \
  -attestation-challenge "$challenge")"

pk="$(printf '%s\n' "$attestation" | awk -F= '/^pk=/{print $2; exit}')"
attestation_pk="$(printf '%s\n' "$attestation" | awk -F= '/^attestation_pk=/{print $2; exit}')"
report="$(printf '%s\n' "$attestation" | awk -F= '/^attestation_report=/{print $2; exit}')"

if [ -z "$pk" ] || [ "$pk" != "$attestation_pk" ]; then
  echo "attestation public key does not match GetPublicKey response" >&2
  printf '%s\n' "$attestation" >&2
  exit 1
fi

if [ -n "${VRF_PUBLIC_KEY:-}" ] && [ "0x${VRF_PUBLIC_KEY#0x}" != "$pk" ]; then
  echo "VRF_PUBLIC_KEY does not match attested enclave public key" >&2
  echo "  expected: 0x${VRF_PUBLIC_KEY#0x}" >&2
  echo "  attested: $pk" >&2
  exit 1
fi

if [ -n "${PLATFORM_ATTESTATION_VERIFIER:-}" ]; then
  VRF_ATTESTATION_MODE="$VRF_ATTESTATION_MODE" \
  VRF_ATTESTATION_PUBLIC_KEY="$pk" \
  VRF_ATTESTATION_CHALLENGE="0x$challenge" \
  VRF_ATTESTATION_REPORT="$report" \
  "$PLATFORM_ATTESTATION_VERIFIER"
fi

printf '%s\n' "$attestation"
echo "[trh-vrf-attest] ok"
