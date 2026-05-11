#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TRH_SDK_PATH="${TRH_SDK_PATH:-../trh-sdk}"
TRH_BACKEND_PATH="${TRH_BACKEND_PATH:-../trh-backend}"
TRH_PLATFORM_UI_PATH="${TRH_PLATFORM_UI_PATH:-../trh-platform-ui}"
failures=0

check_patch() {
  local repo="$1"
  local patch="$2"
  local label="$3"

  if [ ! -d "$repo/.git" ]; then
    echo "[warn] $label repository not found: $repo" >&2
    return
  fi
  if [ ! -f "$patch" ]; then
    echo "[fail] missing patch: $patch" >&2
    failures=$((failures + 1))
    return
  fi
  if git -C "$repo" apply --recount --check "$patch"; then
    echo "[ok] $label patch applies"
  else
    echo "[fail] $label patch does not apply cleanly" >&2
    failures=$((failures + 1))
  fi
}

check_patch "$TRH_SDK_PATH" "$ROOT/deploy/trh/external-integration/trh-sdk-enshrined-vrf.patch" "trh-sdk"
check_patch "$TRH_BACKEND_PATH" "$ROOT/deploy/trh/external-integration/trh-backend-enshrined-vrf.patch" "trh-backend"
check_patch "$TRH_PLATFORM_UI_PATH" "$ROOT/deploy/trh/external-integration/trh-platform-ui-enshrined-vrf.patch" "trh-platform-ui"

if [ "$failures" -ne 0 ]; then
  echo "[external-patches] failed: $failures failure(s)" >&2
  exit 1
fi

echo "[external-patches] ok"
