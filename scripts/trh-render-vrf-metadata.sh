#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT/devnet/sepolia/.env}"
DEVNET_MANIFEST="${DEVNET_MANIFEST:-$ROOT/.devnet/sepolia/devnet.json}"

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

manifest_value() {
  local key="$1"
  if [ -f "$DEVNET_MANIFEST" ]; then
    jq -r "$key // empty" "$DEVNET_MANIFEST"
  fi
}

read_public_key() {
  if [ -n "${VRF_PUBLIC_KEY:-}" ]; then
    normalize_hex "$VRF_PUBLIC_KEY"
    return 0
  fi

  local manifest_pk
  manifest_pk="$(manifest_value '.vrfPublicKey')"
  if [ -n "$manifest_pk" ] && [ "$manifest_pk" != "null" ]; then
    normalize_hex "$manifest_pk"
    return 0
  fi

  if [ -n "${L1_RPC_URL:-}" ] && [ -n "${SYSTEM_CONFIG_PROXY:-}" ]; then
    raw_l1_pk="$(cast call "$SYSTEM_CONFIG_PROXY" "vrfPublicKey()(bytes)" --rpc-url "$L1_RPC_URL")"
    cast abi-decode "f()(bytes)" "$raw_l1_pk" | awk 'NF { print $1; exit }'
    return 0
  fi

  if [ -n "${VRF_TEE_ENDPOINT:-}" ]; then
    if [ ! -x "$ROOT/bin/vrf-prove" ]; then
      echo "missing bin/vrf-prove; run ./scripts/devnet-build.sh" >&2
      return 1
    fi
    "$ROOT/bin/vrf-prove" \
      -tee-endpoint "$VRF_TEE_ENDPOINT" \
      -public-key-only \
      2>/dev/null | awk -F= '/^pk=/{print $2; exit}'
    return 0
  fi

  echo "could not determine VRF public key; set VRF_PUBLIC_KEY, SYSTEM_CONFIG_PROXY+L1_RPC_URL, or VRF_TEE_ENDPOINT" >&2
  return 1
}

CHAIN_NAME="${CHAIN_NAME:-${ROLLUP_NAME:-example-game-l2}}"
STACK="${STACK:-thanos}"
CHAIN_ID="${CHAIN_ID:-${L2_CHAIN_ID:-$(manifest_value '.l2ChainId')}}"
if [ -z "$CHAIN_ID" ] || [ "$CHAIN_ID" = "null" ]; then
  echo "CHAIN_ID or L2_CHAIN_ID is required" >&2
  exit 1
fi

VRF_PUBLIC_KEY_RENDERED="$(read_public_key)"
VRF_PUBLIC_KEY_RENDERED="$(normalize_hex "$VRF_PUBLIC_KEY_RENDERED")"
if [[ ! "$VRF_PUBLIC_KEY_RENDERED" =~ ^0x(02|03)[0-9a-fA-F]{64}$ ]]; then
  echo "VRF public key must be a 33-byte compressed SEC1 key" >&2
  exit 1
fi

jq -n \
  --arg name "$CHAIN_NAME" \
  --arg stack "$STACK" \
  --arg publicKey "$VRF_PUBLIC_KEY_RENDERED" \
  --argjson chainId "$CHAIN_ID" \
  '{
    name: $name,
    stack: $stack,
    chainId: $chainId,
    features: {
      enshrinedVrf: true
    },
    enshrinedVrf: {
      mode: "tee",
      vrfPredeploy: "0x42000000000000000000000000000000000000f0",
      vrfVerifyPrecompile: "0x0000000000000000000000000000000000000101",
      vrfPublicKey: $publicKey,
      systemConfigPublicKeySource: "SystemConfig.vrfPublicKey()(bytes)",
      sequencerPublicKeySource: "EnshrainedVRF.sequencerPublicKey()(bytes)",
      readinessCommand: "./scripts/trh-verify-vrf-chain.sh",
      proofVerificationCommand: "./scripts/trh-verify-vrf-proof.sh",
      monitoringCommand: "./scripts/trh-export-vrf-metrics.sh"
    }
  }'
