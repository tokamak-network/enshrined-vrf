#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

confirm() {
  if [ "${YES:-0}" = "1" ]; then
    return 0
  fi
  printf '%s [y/N] ' "$1"
  read -r answer
  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) echo "aborted"; exit 1 ;;
  esac
}

commit_if_needed() {
  local message="$1"
  if git diff --cached --quiet; then
    echo "[skip] $message"
  else
    git commit -m "$message"
  fi
}

push_if_requested() {
  local remote="$1"
  local branch="$2"
  if [ "${PUSH:-1}" = "1" ]; then
    git push "$remote" "$branch"
  else
    echo "[skip] push disabled for $PWD"
  fi
}

echo "This script commits the current workspace changes by feature."
echo "It assumes you are running from a terminal with write access to .git."
echo
confirm "Proceed with feature-split commits and push?"

echo
echo "[op-geth] VRF payload deposits"
(
  cd "$ROOT/op-geth"
  git add \
    beacon/engine/gen_blockparams.go \
    beacon/engine/types.go \
    beacon/engine/vrf_payload_attributes_test.go \
    miner/payload_building.go \
    miner/payload_building_test.go \
    miner/vrf_builder.go \
    miner/vrf_builder_test.go \
    miner/worker.go
  commit_if_needed "feat(op-geth): inject enshrined VRF payload deposits"
  push_if_requested enshrined-vrf enshrined-vrf:op-geth
)

echo
echo "[optimism] VRF derivation and Engine API encoding"
(
  cd "$ROOT/optimism"
  git add \
    op-node/rollup/derive/attributes_test.go \
    op-node/rollup/derive/system_config.go \
    op-node/rollup/derive/system_config_test.go \
    op-service/eth/types.go \
    op-service/eth/types_test.go
  commit_if_needed "feat(optimism): propagate enshrined VRF payload data"
  push_if_requested enshrined-vrf enshrined-vrf:optimism
)

echo
echo "[root] Sepolia devnet tooling"
(
  cd "$ROOT"
  git add \
    .gitignore \
    README.md \
    devnet/sepolia/.env.example \
    docs/op-stack-customizations.md \
    docs/sepolia-devnet.md \
    scripts/devnet-build.sh \
    scripts/devnet-rpc-chain-id.sh \
    scripts/devnet-sepolia-preflight.sh \
    scripts/devnet-sepolia-prepare.sh \
    scripts/devnet-sepolia-render-intent.sh \
    scripts/devnet-sepolia-start.sh \
    scripts/devnet-sepolia-stop.sh \
    scripts/devnet-sepolia-up.sh \
    scripts/devnet-sepolia-verify-random.sh \
    scripts/commit-feature-split.sh \
    op-geth \
    optimism
  commit_if_needed "feat(devnet): add Sepolia-backed local L2 workflow"
)

echo
echo "[root] VRF verifier docs and source clarification"
(
  cd "$ROOT"
  git add \
    contracts/src/L1/VRFVerifier.sol \
    docs-site/contracts/vrf-verifier.mdx \
    docs-site/scripts/sync-contracts.mjs
  commit_if_needed "docs(vrf): clarify L1 verifier boundary"
)

echo
echo "[root] Architecture docs refresh"
(
  cd "$ROOT"
  git add \
    docs/PRD.md \
    docs/architecture.md \
    docs/phase-1-report.md \
    docs/phase-2-report.md \
    docs/phase-3-report.md \
    docs/phase-4-report.md \
    docs/security-audit-checklist.md \
    docs/testing-guide.md \
    docs-site/.mintignore \
    docs-site/architecture/execution.mdx \
    docs-site/architecture/fault-proof.mdx \
    docs-site/architecture/overview.mdx \
    docs-site/architecture/sequencer.mdx \
    docs-site/concepts/enshrined-vrf.mdx \
    docs-site/contracts/enshrined-vrf.mdx \
    docs-site/guides/build-vrf-game.mdx
  commit_if_needed "docs: refresh enshrined VRF architecture"
  push_if_requested origin main
)

echo
echo "done"
