#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GOCACHE="${GOCACHE:-${TMPDIR:-/tmp}/enshrined-vrf-gocache}"
RUN_EXTERNAL_PATCH_COMPILE="${RUN_EXTERNAL_PATCH_COMPILE:-1}"
RUN_DOCKER_BUILD="${RUN_DOCKER_BUILD:-0}"

log() {
  echo
  echo "== $* =="
}

run() {
  echo "+ $*"
  "$@"
}

log "Shell syntax"
scripts=(
  scripts/devnet-sepolia-preflight.sh
  scripts/devnet-sepolia-prepare.sh
  scripts/devnet-sepolia-start.sh
  scripts/devnet-sepolia-verify-random.sh
  scripts/trh-attest-vrf-enclave.sh
  scripts/trh-build-vrf-enclave-image.sh
  scripts/trh-export-vrf-metrics.sh
  scripts/trh-production-vrf-gate.sh
  scripts/trh-render-vrf-metadata.sh
  scripts/trh-render-vrf-settings.sh
  scripts/trh-tee-readiness.sh
  scripts/trh-local-readiness.sh
  scripts/trh-validate-attestation-policy.sh
  scripts/trh-validate-k8s-vrf-sidecar.sh
  scripts/trh-validate-vrf-metadata.sh
  scripts/trh-validate-vrf-settings.sh
  scripts/trh-apply-external-patches.sh
  scripts/trh-check-external-patches.sh
  scripts/trh-verify-external-patches-compile.sh
  scripts/trh-validate-thanos-stack-chart.sh
  scripts/trh-check-external-integration.sh
  scripts/test-trh-attestation-policy.sh
  scripts/test-trh-validate-thanos-stack-chart.sh
  scripts/test-trh-render-vrf-settings.sh
  scripts/test-trh-export-vrf-metrics.sh
  scripts/trh-verify-vrf-chain.sh
  scripts/trh-verify-vrf-proof.sh
)
for script in "${scripts[@]}"; do
  run bash -n "$ROOT/$script"
done

log "TRH static readiness"
run env REQUIRE_TEE=0 GOCACHE="$GOCACHE" "$ROOT/scripts/trh-tee-readiness.sh"

log "Schemas, examples, and local guards"
run "$ROOT/scripts/trh-validate-vrf-settings.sh" "$ROOT/deploy/trh/settings.example.json"
run "$ROOT/scripts/trh-validate-vrf-metadata.sh" "$ROOT/deploy/trh/metadata.example.json"
run "$ROOT/scripts/trh-validate-attestation-policy.sh" "$ROOT/deploy/trh/attestation-policy.example.json"
run "$ROOT/scripts/trh-validate-k8s-vrf-sidecar.sh" "$ROOT/deploy/trh/kubernetes-vrf-sidecar.example.yaml"
run "$ROOT/scripts/test-trh-render-vrf-settings.sh"
run "$ROOT/scripts/test-trh-attestation-policy.sh"
run "$ROOT/scripts/test-trh-export-vrf-metrics.sh"
run "$ROOT/scripts/test-trh-validate-thanos-stack-chart.sh"

log "Production gate guard"
run env \
  VRF_MODE=tee \
  VRF_ATTESTATION_MODE=tdx \
  VRF_TEE_ENDPOINT=unix:///var/run/vrf-enclave/vrf.sock \
  VRF_PUBLIC_KEY=0x032c8c31fc9f990c6b55e3865a184a4ce50e09481f2eaeb3e60ec1cea13a6ae645 \
  VRF_PLATFORM_ATTESTATION_IMPLEMENTED=1 \
  IMAGE_TAG=v0.1.0 \
  EXTERNAL_AUDIT_ID=audit-2026-ci \
  VRF_ATTESTATION_POLICY_ID=tdx-game-l2-vrf-policy-v1 \
  "$ROOT/scripts/trh-production-vrf-gate.sh"

log "Go and contract tests"
run env GOCACHE="$GOCACHE" go -C "$ROOT" test ./crypto/ecvrf ./vrf-enclave/enclave ./vrf-enclave/cmd/vrf-prove
run env GOCACHE="$GOCACHE" go -C "$ROOT/optimism" test ./op-node/rollup/derive -run 'TestTEEVRFProver|TestComputeVRFProofWithRetry'
(
  cd "$ROOT/contracts"
  run forge test --offline --match-contract TRHGameRandomnessTest
)

if [ "$RUN_EXTERNAL_PATCH_COMPILE" = "1" ]; then
  log "External TRH patch package"
  run "$ROOT/scripts/trh-check-external-patches.sh"
  run env GOCACHE="$GOCACHE" "$ROOT/scripts/trh-verify-external-patches-compile.sh"
else
  echo "[skip] external patch compile checks disabled with RUN_EXTERNAL_PATCH_COMPILE=$RUN_EXTERNAL_PATCH_COMPILE"
fi

if [ "$RUN_DOCKER_BUILD" = "1" ]; then
  log "VRF enclave image"
  run docker build -f "$ROOT/vrf-enclave/Dockerfile" -t enshrined-vrf/vrf-enclave:local "$ROOT"
else
  echo "[skip] Docker build disabled with RUN_DOCKER_BUILD=$RUN_DOCKER_BUILD"
fi

echo
echo "[trh-local-readiness] ok"
