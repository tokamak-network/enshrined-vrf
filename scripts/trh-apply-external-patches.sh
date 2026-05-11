#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TRH_SDK_PATH="${TRH_SDK_PATH:-../trh-sdk}"
TRH_BACKEND_PATH="${TRH_BACKEND_PATH:-../trh-backend}"
TRH_PLATFORM_UI_PATH="${TRH_PLATFORM_UI_PATH:-../trh-platform-ui}"

apply_patch_to_repo() {
  local repo="$1"
  local patch="$2"
  local label="$3"

  if [ ! -d "$repo/.git" ]; then
    echo "[fail] $label repository not found: $repo" >&2
    exit 1
  fi
  if [ ! -f "$patch" ]; then
    echo "[fail] missing patch: $patch" >&2
    exit 1
  fi
  git -C "$repo" apply --recount --check "$patch"
  git -C "$repo" apply --recount "$patch"
  echo "[ok] applied $label patch"
}

apply_patch_to_repo "$TRH_SDK_PATH" "$ROOT/deploy/trh/external-integration/trh-sdk-enshrined-vrf.patch" "trh-sdk"
apply_patch_to_repo "$TRH_BACKEND_PATH" "$ROOT/deploy/trh/external-integration/trh-backend-enshrined-vrf.patch" "trh-backend"
apply_patch_to_repo "$TRH_PLATFORM_UI_PATH" "$ROOT/deploy/trh/external-integration/trh-platform-ui-enshrined-vrf.patch" "trh-platform-ui"

echo "[external-patches] applied"
