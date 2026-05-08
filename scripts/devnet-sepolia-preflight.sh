#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT/devnet/sepolia/.env}"
WORKDIR="${DEVNET_WORKDIR:-$ROOT/.devnet/sepolia}"
DEPLOYER_CACHE_DIR="${OP_DEPLOYER_CACHE_DIR:-$WORKDIR/op-deployer-cache}"
ARTIFACTS_DIR="$ROOT/optimism/packages/contracts-bedrock/forge-artifacts"
L2_CHAIN_ID="${L2_CHAIN_ID:-901005}"
VRF_SK="${VRF_SK:-0xc9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721}"
VRF_MODE="${VRF_MODE:-local}"
SKIP_L1_RPC_CHECK="${SKIP_L1_RPC_CHECK:-0}"

if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

failures=0
warnings=0

ok() {
  echo "[ok] $*"
}

warn() {
  warnings=$((warnings + 1))
  echo "[warn] $*" >&2
}

fail() {
  failures=$((failures + 1))
  echo "[fail] $*" >&2
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

require_cmd() {
  if have_cmd "$1"; then
    ok "$1: $(command -v "$1")"
  else
    fail "missing required command: $1"
  fi
}

echo "[preflight] Sepolia-backed local L2 devnet"
echo "  env:     $ENV_FILE"
echo "  workdir: $WORKDIR"
echo

require_cmd cast
require_cmd jq
require_cmd forge
require_cmd go

if [ -f "$ENV_FILE" ]; then
  ok "env file exists"
elif [ -n "${L1_RPC_URL:-}" ] && [ -n "${PRIVATE_KEY:-}" ]; then
  warn "env file is missing; using L1_RPC_URL and PRIVATE_KEY from the shell environment"
else
  fail "missing env file; copy devnet/sepolia/.env.example to devnet/sepolia/.env or export L1_RPC_URL and PRIVATE_KEY"
fi

if [ -n "${L1_RPC_URL:-}" ]; then
  if [ "$SKIP_L1_RPC_CHECK" = "1" ]; then
    warn "skipping L1 RPC chain-id check because SKIP_L1_RPC_CHECK=1"
  elif have_cmd cast; then
    if l1_chain_id="$("$ROOT/scripts/devnet-rpc-chain-id.sh" "$L1_RPC_URL" 2>/dev/null)"; then
      if [ "$l1_chain_id" = "11155111" ]; then
        ok "L1 RPC chain-id is Sepolia 11155111"
      else
        fail "L1 RPC chain-id is $l1_chain_id, expected Sepolia 11155111"
      fi
    else
      fail "could not read L1 chain-id from L1_RPC_URL"
    fi
  fi
else
  fail "L1_RPC_URL is not set"
fi

if [ -n "${PRIVATE_KEY:-}" ]; then
  if have_cmd cast; then
    if deployer_addr="$(cast wallet address --private-key "$PRIVATE_KEY" 2>/dev/null)"; then
      ok "PRIVATE_KEY derives deployer address $deployer_addr"
    else
      fail "PRIVATE_KEY could not derive an address"
    fi
  fi
else
  fail "PRIVATE_KEY is not set"
fi

for bin in geth op-node op-deployer vrf-prove; do
  if [ -x "$ROOT/bin/$bin" ]; then
    ok "bin/$bin exists"
  else
    warn "bin/$bin is missing; prepare will build it when BUILD_BINARIES=1"
  fi
done

if [ -f "$ARTIFACTS_DIR/L2Genesis.s.sol/L2Genesis.json" ]; then
  ok "L2Genesis artifact exists"
else
  warn "missing L2Genesis artifact; prepare will build contracts when BUILD_CONTRACTS=1"
fi

if [ -f "$ARTIFACTS_DIR/EnshrainedVRF.sol/EnshrainedVRF.json" ]; then
  ok "EnshrainedVRF artifact exists"
else
  warn "missing EnshrainedVRF artifact; prepare will build contracts when BUILD_CONTRACTS=1"
fi

if [ -x "$ROOT/bin/vrf-prove" ]; then
  case "$VRF_MODE" in
    local)
      if vrf_pk="$("$ROOT/bin/vrf-prove" -sk "$VRF_SK" -public-key-only 2>/dev/null | awk -F= '/^pk=/{print $2; exit}')"; then
        vrf_pk="0x${vrf_pk#0x}"
        if [ "${#vrf_pk}" -eq 68 ]; then
          ok "VRF_SK derives 33-byte public key $vrf_pk"
        else
          fail "VRF_SK did not derive a 33-byte public key"
        fi
      else
        fail "vrf-prove failed to derive public key from VRF_SK"
      fi
      ;;
    tee)
      if [ -z "${VRF_TEE_ENDPOINT:-}" ]; then
        fail "VRF_TEE_ENDPOINT is required when VRF_MODE=tee"
      elif vrf_pk="$("$ROOT/bin/vrf-prove" -tee-endpoint "$VRF_TEE_ENDPOINT" -public-key-only 2>/dev/null | awk -F= '/^pk=/{print $2; exit}')"; then
        vrf_pk="0x${vrf_pk#0x}"
        if [ "${#vrf_pk}" -eq 68 ]; then
          ok "TEE enclave returns 33-byte public key $vrf_pk"
        else
          fail "TEE enclave did not return a 33-byte public key"
        fi
      else
        fail "vrf-prove failed to read public key from TEE endpoint $VRF_TEE_ENDPOINT"
      fi
      ;;
    *)
      fail "unsupported VRF_MODE=$VRF_MODE (expected local or tee)"
      ;;
  esac
fi

mkdir -p "$DEPLOYER_CACHE_DIR"
if [ -x "$ROOT/bin/op-deployer" ]; then
  tmpdir="$(mktemp -d "${TMPDIR:-/private/tmp}/enshrined-vrf-preflight.XXXXXX")"
  trap 'rm -rf "$tmpdir"' EXIT
  if "$ROOT/bin/op-deployer" --cache-dir "$DEPLOYER_CACHE_DIR" init \
    --l1-chain-id 11155111 \
    --l2-chain-ids "$L2_CHAIN_ID" \
    --intent-type custom \
    --workdir "$tmpdir/work" >/dev/null; then
    ok "op-deployer can initialize with workspace cache"
  else
    fail "op-deployer init failed with workspace cache"
  fi

  if [ -f "$ARTIFACTS_DIR/L2Genesis.s.sol/L2Genesis.json" ] &&
     [ -f "$ARTIFACTS_DIR/EnshrainedVRF.sol/EnshrainedVRF.json" ]; then
    test_addr="0xd2Fa7E6D0619952D32145E0c3c4169f2d197138B"
    DEPLOYER_ADDR="$test_addr" \
      L2_CHAIN_ID="$L2_CHAIN_ID" \
      ARTIFACTS_LOCATOR="file://$ARTIFACTS_DIR" \
      "$ROOT/scripts/devnet-sepolia-render-intent.sh" > "$tmpdir/work/intent.toml"
    if L1_RPC_URL="" "$ROOT/bin/op-deployer" --cache-dir "$DEPLOYER_CACHE_DIR" apply \
      --workdir "$tmpdir/work" \
      --deployment-target genesis >/dev/null 2>&1; then
      ok "op-deployer accepts generated Sepolia custom intent"
    else
      fail "op-deployer rejected generated Sepolia custom intent"
    fi
  else
    warn "skipping generated intent smoke because contracts-bedrock artifacts are missing"
  fi
fi

echo
if [ "$failures" -ne 0 ]; then
  echo "[preflight] failed: $failures failure(s), $warnings warning(s)" >&2
  exit 1
fi

echo "[preflight] ok: $warnings warning(s)"
echo "Next: ./scripts/devnet-sepolia-prepare.sh"
