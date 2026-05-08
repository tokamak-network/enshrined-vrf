#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT/devnet/sepolia/.env}"
REQUIRE_TEE="${REQUIRE_TEE:-1}"
CHECK_TEE_ENDPOINT="${CHECK_TEE_ENDPOINT:-$REQUIRE_TEE}"

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

require_file_contains() {
  local path="$1"
  local pattern="$2"
  local label="$3"
  if [ ! -f "$ROOT/$path" ]; then
    fail "missing $label: $path"
    return
  fi
  if grep -q "$pattern" "$ROOT/$path"; then
    ok "$label"
  else
    fail "$label is missing expected marker '$pattern' in $path"
  fi
}

normalize_hex() {
  printf '0x%s' "${1#0x}"
}

echo "[readiness] TRH TEE VRF game-L2 deployment"
echo "  env:         $ENV_FILE"
echo "  require TEE: $REQUIRE_TEE"
echo "  check TEE:   $CHECK_TEE_ENDPOINT"
echo

require_cmd go
require_cmd jq
require_cmd forge

require_file_contains "optimism/packages/contracts-bedrock/src/L1/SystemConfig.sol" "setVRFPublicKey" "L1 SystemConfig VRF key setter"
require_file_contains "optimism/packages/contracts-bedrock/src/L2/EnshrainedVRF.sol" "commitRandomness" "L2 EnshrainedVRF predeploy"
require_file_contains "optimism/packages/contracts-bedrock/src/libraries/Predeploys.sol" "EnshrainedVRF" "L2 predeploy address registry"
require_file_contains "op-geth/core/vm/contracts_ecvrf.go" "Verify" "op-geth ECVRF verify precompile"
require_file_contains "op-geth/miner/vrf_builder.go" "commitRandomness" "op-geth VRF deposit builder"
require_file_contains "optimism/op-node/rollup/derive/vrf_tee.go" "GetPublicKey" "op-node TEE VRF prover"
require_file_contains "optimism/op-node/flags/flags.go" "sequencer.vrf-mode" "op-node VRF mode flag"
require_file_contains "optimism/op-program/client/l2/engineapi/precompiles.go" "ECVRF" "fault-proof ECVRF precompile path"
require_file_contains "scripts/devnet-sepolia-prepare.sh" "VRF_TEE_ENDPOINT" "prepare can register TEE public key"

VRF_MODE="${VRF_MODE:-}"
if [ "$REQUIRE_TEE" = "1" ]; then
  if [ "$VRF_MODE" != "tee" ]; then
    fail "set VRF_MODE=tee for TEE-backed game L2 deployment"
  else
    ok "VRF_MODE=tee"
  fi
  if [ -z "${VRF_TEE_ENDPOINT:-}" ]; then
    fail "set VRF_TEE_ENDPOINT to the enclave gRPC endpoint"
  else
    ok "VRF_TEE_ENDPOINT=$VRF_TEE_ENDPOINT"
  fi
  if [ "${SET_L1_VRF_PUBLIC_KEY:-1}" = "0" ]; then
    fail "SET_L1_VRF_PUBLIC_KEY=0 would skip L1 SystemConfig VRF public-key registration"
  else
    ok "L1 VRF public-key registration is enabled"
  fi
elif [ -z "$VRF_MODE" ]; then
  warn "VRF_MODE is not set; production game chains should use VRF_MODE=tee"
fi

if [ "$CHECK_TEE_ENDPOINT" = "1" ] && [ -n "${VRF_TEE_ENDPOINT:-}" ]; then
  if [ ! -x "$ROOT/bin/vrf-prove" ]; then
    fail "bin/vrf-prove is missing; run ./scripts/devnet-build.sh before live readiness checks"
  elif tee_pk="$("$ROOT/bin/vrf-prove" -tee-endpoint "$VRF_TEE_ENDPOINT" -public-key-only 2>/dev/null | awk -F= '/^pk=/{print $2; exit}')"; then
    tee_pk="$(normalize_hex "$tee_pk")"
    if [ "${#tee_pk}" -eq 68 ]; then
      ok "TEE enclave public key: $tee_pk"
      if [ -n "${VRF_PUBLIC_KEY:-}" ]; then
        configured_pk="$(normalize_hex "$VRF_PUBLIC_KEY")"
        if [ "$configured_pk" = "$tee_pk" ]; then
          ok "VRF_PUBLIC_KEY matches TEE enclave public key"
        else
          fail "VRF_PUBLIC_KEY ($configured_pk) does not match TEE enclave public key ($tee_pk)"
        fi
      fi
    else
      fail "TEE enclave returned invalid public key length"
    fi
  else
    fail "could not read public key from TEE endpoint $VRF_TEE_ENDPOINT"
  fi
elif [ -n "${VRF_TEE_ENDPOINT:-}" ]; then
  warn "skipping live TEE public-key check because CHECK_TEE_ENDPOINT=$CHECK_TEE_ENDPOINT"
fi

if [ -f "$ROOT/docs/trh-tee-game-l2.md" ]; then
  ok "TRH TEE game-L2 runbook exists"
else
  fail "missing docs/trh-tee-game-l2.md"
fi

if [ -f "$ROOT/docs/trh-tee-game-l2-completion-audit.md" ]; then
  ok "TRH TEE game-L2 completion audit exists"
else
  fail "missing docs/trh-tee-game-l2-completion-audit.md"
fi

if [ -f "$ROOT/deploy/trh/enshrined-vrf.manifest.json" ]; then
  if jq -e '.feature.id == "enshrined-vrf" and .sdkSettings.forbiddenInProduction.vrf_mode == "local"' "$ROOT/deploy/trh/enshrined-vrf.manifest.json" >/dev/null; then
    ok "TRH Enshrained VRF manifest exists"
  else
    fail "TRH Enshrained VRF manifest is missing required fields"
  fi
else
  fail "missing deploy/trh/enshrined-vrf.manifest.json"
fi

if [ -f "$ROOT/deploy/trh/metadata.example.json" ]; then
  ok "TRH VRF metadata example exists"
else
  fail "missing deploy/trh/metadata.example.json"
fi

if [ -x "$ROOT/scripts/trh-validate-vrf-metadata.sh" ]; then
  if "$ROOT/scripts/trh-validate-vrf-metadata.sh" "$ROOT/deploy/trh/metadata.example.json" >/dev/null; then
    ok "TRH VRF metadata validator exists"
  else
    fail "TRH VRF metadata validator rejected metadata.example.json"
  fi
else
  fail "missing executable scripts/trh-validate-vrf-metadata.sh"
fi

if [ -x "$ROOT/scripts/trh-render-vrf-metadata.sh" ]; then
  ok "TRH VRF metadata renderer exists"
else
  fail "missing executable scripts/trh-render-vrf-metadata.sh"
fi

if [ -f "$ROOT/deploy/trh/thanos-stack-vrf-values.example.yaml" ]; then
  ok "TRH Thanos VRF values overlay exists"
else
  fail "missing deploy/trh/thanos-stack-vrf-values.example.yaml"
fi

if [ -f "$ROOT/deploy/trh/kubernetes-vrf-sidecar.example.yaml" ]; then
  ok "TRH Kubernetes VRF sidecar example exists"
else
  fail "missing deploy/trh/kubernetes-vrf-sidecar.example.yaml"
fi

if [ -x "$ROOT/scripts/trh-validate-k8s-vrf-sidecar.sh" ]; then
  if "$ROOT/scripts/trh-validate-k8s-vrf-sidecar.sh" "$ROOT/deploy/trh/kubernetes-vrf-sidecar.example.yaml" >/dev/null; then
    ok "TRH Kubernetes VRF sidecar validator exists"
  else
    fail "TRH Kubernetes VRF sidecar validator rejected the example manifest"
  fi
else
  fail "missing executable scripts/trh-validate-k8s-vrf-sidecar.sh"
fi

if [ -x "$ROOT/scripts/trh-render-vrf-settings.sh" ]; then
  ok "TRH VRF settings renderer exists"
else
  fail "missing executable scripts/trh-render-vrf-settings.sh"
fi

if [ -f "$ROOT/deploy/trh/settings.schema.json" ]; then
  if jq -e '.properties.enshrinedVrf.properties.publicKey.pattern != null and .properties.enshrinedVrf.properties.teeEndpoint.minLength == 1' "$ROOT/deploy/trh/settings.schema.json" >/dev/null; then
    ok "TRH VRF settings schema exists"
  else
    fail "TRH VRF settings schema is missing endpoint or public-key validation"
  fi
else
  fail "missing deploy/trh/settings.schema.json"
fi

if [ -f "$ROOT/deploy/trh/settings.example.json" ]; then
  ok "TRH VRF settings example exists"
else
  fail "missing deploy/trh/settings.example.json"
fi

if [ -x "$ROOT/scripts/trh-validate-vrf-settings.sh" ]; then
  if "$ROOT/scripts/trh-validate-vrf-settings.sh" "$ROOT/deploy/trh/settings.example.json" >/dev/null; then
    ok "TRH VRF settings validator exists"
  else
    fail "TRH VRF settings validator rejected settings.example.json"
  fi
else
  fail "missing executable scripts/trh-validate-vrf-settings.sh"
fi

if [ -x "$ROOT/scripts/trh-production-vrf-gate.sh" ]; then
  ok "TRH production VRF gate exists"
else
  fail "missing executable scripts/trh-production-vrf-gate.sh"
fi

if [ -x "$ROOT/scripts/trh-verify-vrf-chain.sh" ]; then
  ok "TRH deployed-chain verifier exists"
else
  fail "missing executable scripts/trh-verify-vrf-chain.sh"
fi

if [ -x "$ROOT/scripts/trh-verify-vrf-proof.sh" ]; then
  ok "TRH VRF proof verifier exists"
else
  fail "missing executable scripts/trh-verify-vrf-proof.sh"
fi

if [ -x "$ROOT/scripts/trh-export-vrf-metrics.sh" ]; then
  ok "TRH VRF metrics exporter exists"
else
  fail "missing executable scripts/trh-export-vrf-metrics.sh"
fi

if [ -f "$ROOT/deploy/trh/prometheus-rules.example.yaml" ]; then
  ok "TRH VRF Prometheus rules example exists"
else
  fail "missing deploy/trh/prometheus-rules.example.yaml"
fi

if [ -f "$ROOT/deploy/trh/attestation-policy.example.json" ]; then
  if [ -x "$ROOT/scripts/trh-validate-attestation-policy.sh" ] && "$ROOT/scripts/trh-validate-attestation-policy.sh" "$ROOT/deploy/trh/attestation-policy.example.json" >/dev/null; then
    ok "TRH attestation policy example exists"
  else
    fail "TRH attestation policy example is missing required fields"
  fi
else
  fail "missing deploy/trh/attestation-policy.example.json"
fi

if [ -f "$ROOT/deploy/trh/attestation-policy.schema.json" ]; then
  if jq -e '.properties.publicKeyBinding.properties.lengthBytes.const == 33 and .properties.mode.enum != null' "$ROOT/deploy/trh/attestation-policy.schema.json" >/dev/null; then
    ok "TRH attestation policy schema exists"
  else
    fail "TRH attestation policy schema is missing required fields"
  fi
else
  fail "missing deploy/trh/attestation-policy.schema.json"
fi

if [ -x "$ROOT/scripts/trh-validate-attestation-policy.sh" ]; then
  ok "TRH attestation policy validator exists"
else
  fail "missing executable scripts/trh-validate-attestation-policy.sh"
fi

if [ -x "$ROOT/scripts/trh-attest-vrf-enclave.sh" ]; then
  ok "TRH VRF enclave attestation preflight exists"
else
  fail "missing executable scripts/trh-attest-vrf-enclave.sh"
fi

if [ -f "$ROOT/vrf-enclave/Dockerfile" ]; then
  ok "VRF enclave Dockerfile exists"
else
  fail "missing vrf-enclave/Dockerfile"
fi

if [ -f "$ROOT/vrf-enclave/Dockerfile.dockerignore" ]; then
  ok "VRF enclave Docker build ignore exists"
else
  fail "missing vrf-enclave/Dockerfile.dockerignore"
fi

if [ -x "$ROOT/scripts/trh-build-vrf-enclave-image.sh" ]; then
  ok "VRF enclave image build script exists"
else
  fail "missing executable scripts/trh-build-vrf-enclave-image.sh"
fi

if [ -f "$ROOT/deploy/trh/external-integration/README.md" ] &&
   [ -f "$ROOT/deploy/trh/external-integration/trh-sdk-enshrined-vrf.patch" ] &&
   [ -f "$ROOT/deploy/trh/external-integration/trh-backend-enshrined-vrf.patch" ] &&
   [ -f "$ROOT/deploy/trh/external-integration/trh-platform-ui-enshrined-vrf.patch" ] &&
   [ -f "$ROOT/deploy/trh/external-integration/tokamak-thanos-stack-chart-contract.md" ] &&
   [ -x "$ROOT/scripts/trh-apply-external-patches.sh" ] &&
   [ -x "$ROOT/scripts/trh-check-external-patches.sh" ] &&
   [ -x "$ROOT/scripts/trh-verify-external-patches-compile.sh" ] &&
   [ -x "$ROOT/scripts/trh-validate-thanos-stack-chart.sh" ] &&
   [ -x "$ROOT/scripts/test-trh-validate-thanos-stack-chart.sh" ] &&
   [ -x "$ROOT/scripts/trh-check-external-integration.sh" ]; then
  ok "TRH external integration patch package exists"
else
  fail "missing TRH external integration patch package"
fi

echo
if [ "$failures" -ne 0 ]; then
  echo "[readiness] failed: $failures failure(s), $warnings warning(s)" >&2
  exit 1
fi

echo "[readiness] ok: $warnings warning(s)"
