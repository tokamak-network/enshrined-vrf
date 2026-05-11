#!/usr/bin/env bash
set -euo pipefail

chart_root="${1:-${TRH_THANOS_STACK_CHART_PATH:-${TRH_THANOS_STACK_PATH:-../tokamak-thanos-stack}/charts/thanos-stack}}"
failures=0

if ! command -v rg >/dev/null 2>&1; then
  echo "[fail] rg (ripgrep) is required by this validator. Install: brew install ripgrep (macOS) | apt-get install -y ripgrep (Debian/Ubuntu)" >&2
  exit 1
fi

fail() {
  failures=$((failures + 1))
  echo "[fail] $*" >&2
}

ok() {
  echo "[ok] $*"
}

require_file() {
  local file="$1"
  local label="$2"
  if [ -f "$file" ]; then
    ok "$label"
  else
    fail "$label: missing $file"
  fi
}

require_pattern() {
  local path="$1"
  local pattern="$2"
  local label="$3"
  if [ ! -e "$path" ]; then
    fail "$label: missing $path"
    return
  fi
  if rg -q -- "$pattern" "$path"; then
    ok "$label"
  else
    fail "$label: missing pattern $pattern in $path"
  fi
}

if [ ! -d "$chart_root" ]; then
  fail "chart root does not exist: $chart_root"
else
  ok "chart root exists"
fi

values_file="$chart_root/values.yaml"
templates_dir="$chart_root/templates"

require_file "$values_file" "values.yaml exists"
require_file "$chart_root/Chart.yaml" "Chart.yaml exists"

require_pattern "$values_file" "enshrinedVrf:" "values exposes enshrinedVrf"
require_pattern "$values_file" "vrfEnclave:" "values exposes vrfEnclave"
require_pattern "$values_file" "teeEndpoint:" "values exposes TEE endpoint"
require_pattern "$values_file" "publicKey:" "values exposes VRF public key"
require_pattern "$values_file" "l2GenesisEnshrainedVRFTimeOffset:" "values exposes fork offset"

require_pattern "$templates_dir" "sequencer\\.vrf-mode=tee|sequencer.vrf-mode" "op-node VRF mode arg is templated"
require_pattern "$templates_dir" "sequencer\\.vrf-tee-endpoint|vrf-tee-endpoint" "op-node TEE endpoint arg is templated"
require_pattern "$templates_dir" "vrf-enclave" "vrf-enclave workload is templated"
require_pattern "$templates_dir" "vrf-enclave-socket|/var/run/vrf-enclave" "shared VRF socket volume is templated"
require_pattern "$templates_dir" "/secure/sealed|sealedKey" "sealed key storage is templated"

if [ "$failures" -ne 0 ]; then
  echo "[thanos-stack-chart] failed: $failures failure(s)" >&2
  exit 1
fi

echo "[thanos-stack-chart] ok"
