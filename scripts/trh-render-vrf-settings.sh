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

command -v jq >/dev/null 2>&1 || {
  echo "missing required command: jq" >&2
  exit 1
}

normalize_hex() {
  printf '0x%s' "${1#0x}"
}

read_public_key() {
  if [ -n "${VRF_PUBLIC_KEY:-}" ]; then
    normalize_hex "$VRF_PUBLIC_KEY"
    return 0
  fi
  if [ "${VRF_MODE:-}" != "tee" ]; then
    echo "VRF_MODE=tee is required unless VRF_PUBLIC_KEY is provided" >&2
    return 1
  fi
  : "${VRF_TEE_ENDPOINT:?set VRF_TEE_ENDPOINT when VRF_MODE=tee}"
  if [ ! -x "$ROOT/bin/vrf-prove" ]; then
    echo "missing bin/vrf-prove; run ./scripts/devnet-build.sh" >&2
    return 1
  fi
  "$ROOT/bin/vrf-prove" \
    -tee-endpoint "$VRF_TEE_ENDPOINT" \
    -public-key-only \
    2>/dev/null | awk -F= '/^pk=/{print $2; exit}'
}

VRF_MODE="${VRF_MODE:-tee}"
if [ "$VRF_MODE" != "tee" ]; then
  echo "refusing to render production TRH settings with VRF_MODE=$VRF_MODE; use VRF_MODE=tee" >&2
  exit 1
fi
: "${VRF_TEE_ENDPOINT:?set VRF_TEE_ENDPOINT for TRH runtime settings}"

VRF_PUBLIC_KEY_RENDERED="$(read_public_key)"
VRF_PUBLIC_KEY_RENDERED="$(normalize_hex "$VRF_PUBLIC_KEY_RENDERED")"
if [ "${#VRF_PUBLIC_KEY_RENDERED}" -ne 68 ]; then
  echo "VRF public key must be a 33-byte compressed SEC1 key" >&2
  exit 1
fi

jq -n \
  --arg stack "${TRH_STACK:-thanos}" \
  --arg vrfMode "$VRF_MODE" \
  --arg endpoint "${VRF_TEE_ENDPOINT:-}" \
  --arg publicKey "$VRF_PUBLIC_KEY_RENDERED" \
  --argjson enshrinedVrfTime "${ENSHRINED_VRF_TIME:-0}" \
  '{
    stack: $stack,
    features: {
      enshrinedVrf: true
    },
    enshrinedVrf: {
      mode: $vrfMode,
      teeEndpoint: $endpoint,
      publicKey: $publicKey,
      enshrinedVrfTime: $enshrinedVrfTime,
      l2GenesisEnshrainedVRFTimeOffset: "0x0",
      predeploy: "0x42000000000000000000000000000000000000f0",
      verifyPrecompile: "0x0000000000000000000000000000000000000101",
      setL1VRFPublicKey: true
    }
  }'
