#!/usr/bin/env bash
set -euo pipefail

TRH_SDK_PATH="${TRH_SDK_PATH:-../trh-sdk}"
TRH_THANOS_STACK_PATH="${TRH_THANOS_STACK_PATH:-../tokamak-thanos-stack}"
TRH_BACKEND_PATH="${TRH_BACKEND_PATH:-../trh-backend}"
TRH_PLATFORM_UI_PATH="${TRH_PLATFORM_UI_PATH:-../trh-platform-ui}"
failures=0

fail() {
  failures=$((failures + 1))
  echo "[fail] $*" >&2
}

ok() {
  echo "[ok] $*"
}

require_file_contains() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if [ ! -f "$file" ]; then
    fail "$label: missing $file"
    return
  fi
  if rg -q -- "$pattern" "$file"; then
    ok "$label"
  else
    fail "$label: missing pattern $pattern in $file"
  fi
}

if [ -d "$TRH_SDK_PATH" ]; then
  require_file_contains "$TRH_SDK_PATH/pkg/types/configuration.go" "EnshrinedVrfConfig" "trh-sdk settings model"
  require_file_contains "$TRH_SDK_PATH/pkg/types/deploy_config_template.go" "L2GenesisEnshrainedVRFTimeOffset" "trh-sdk deploy-config field"
  require_file_contains "$TRH_SDK_PATH/pkg/stacks/thanos/input.go" "TRH_ENABLE_ENSHRAINED_VRF" "trh-sdk env feature flag"
  require_file_contains "$TRH_SDK_PATH/pkg/stacks/thanos/deploy_contracts.go" "EnshrinedVrf" "trh-sdk persisted settings"
  require_file_contains "$TRH_SDK_PATH/pkg/stacks/thanos/deploy_chain.go" "applyEnshrinedVrfValues" "trh-sdk values injection"
  require_file_contains "$TRH_SDK_PATH/pkg/stacks/thanos/enshrined_vrf.go" "sequencer.vrf-mode=tee" "trh-sdk op-node TEE args"
else
  fail "TRH_SDK_PATH does not exist: $TRH_SDK_PATH"
fi

if [ -d "$TRH_THANOS_STACK_PATH" ]; then
  chart_path="${TRH_THANOS_STACK_CHART_PATH:-$TRH_THANOS_STACK_PATH/charts/thanos-stack}"
  if "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/trh-validate-thanos-stack-chart.sh" "$chart_path"; then
    ok "tokamak-thanos-stack chart integration"
  else
    fail "tokamak-thanos-stack chart integration failed"
  fi
else
  echo "[warn] TRH_THANOS_STACK_PATH does not exist: $TRH_THANOS_STACK_PATH" >&2
fi

if [ -d "$TRH_BACKEND_PATH" ]; then
  require_file_contains "$TRH_BACKEND_PATH/pkg/api/dtos/thanos.go" "EnshrinedVrf" "trh-backend request DTO"
  require_file_contains "$TRH_BACKEND_PATH/pkg/api/dtos/thanos.go" "teeEndpoint" "trh-backend TEE endpoint validation"
  require_file_contains "$TRH_BACKEND_PATH/pkg/stacks/thanos/thanos_stack.go" "EnshrinedVrf" "trh-backend SDK input mapping"
else
  echo "[warn] TRH_BACKEND_PATH does not exist: $TRH_BACKEND_PATH" >&2
fi

if [ -d "$TRH_PLATFORM_UI_PATH" ]; then
  require_file_contains "$TRH_PLATFORM_UI_PATH/src/features/rollup/schemas/create-rollup.ts" "enshrinedVrf" "trh-platform-ui create-rollup schema"
  require_file_contains "$TRH_PLATFORM_UI_PATH/src/features/rollup/schemas/create-rollup.ts" "teeEndpoint" "trh-platform-ui TEE endpoint field"
  require_file_contains "$TRH_PLATFORM_UI_PATH/src/features/rollup/schemas/thanos.ts" "enshrinedVrf" "trh-platform-ui stack config type"
else
  echo "[warn] TRH_PLATFORM_UI_PATH does not exist: $TRH_PLATFORM_UI_PATH" >&2
fi

if [ "$failures" -ne 0 ]; then
  echo "[external-integration] failed: $failures failure(s)" >&2
  exit 1
fi

echo "[external-integration] ok"
