#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TRH_SDK_PATH="${TRH_SDK_PATH:-../trh-sdk}"
TRH_BACKEND_PATH="${TRH_BACKEND_PATH:-../trh-backend}"
TRH_PLATFORM_UI_PATH="${TRH_PLATFORM_UI_PATH:-../trh-platform-ui}"
GOCACHE="${GOCACHE:-/private/tmp/enshrined-vrf-gocache}"

canonicalize_dir() {
  if [ -d "$1" ]; then
    (cd "$1" && pwd)
  else
    echo "$1"
  fi
}

TRH_SDK_PATH="$(canonicalize_dir "$TRH_SDK_PATH")"
TRH_BACKEND_PATH="$(canonicalize_dir "$TRH_BACKEND_PATH")"
TRH_PLATFORM_UI_PATH="$(canonicalize_dir "$TRH_PLATFORM_UI_PATH")"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[fail] missing command: $1" >&2
    exit 1
  fi
}

copy_repo() {
  local src="$1"
  local dst="$2"
  local label="$3"

  if [ ! -d "$src/.git" ]; then
    echo "[warn] $label repository not found: $src" >&2
    return 1
  fi
  mkdir -p "$dst"
  git -C "$src" ls-files -z | rsync -a --from0 --files-from=- "$src/" "$dst/"
}

require_cmd git
require_cmd go
require_cmd rsync

workdir="$(mktemp -d "${TMPDIR:-/private/tmp}/trh-vrf-external-compile.XXXXXX")"
if [ "${KEEP_TMP:-0}" != "1" ]; then
  trap 'rm -rf "$workdir"' EXIT
else
  echo "[info] keeping temp directory: $workdir"
fi

sdk_tmp="$workdir/trh-sdk"
backend_tmp="$workdir/trh-backend"
ui_tmp="$workdir/trh-platform-ui"

if copy_repo "$TRH_SDK_PATH" "$sdk_tmp" "trh-sdk"; then
  git -C "$sdk_tmp" apply "$ROOT/deploy/trh/external-integration/trh-sdk-enshrined-vrf.patch"
  cat >"$sdk_tmp/pkg/stacks/thanos/enshrined_vrf_external_test.go" <<'EOF'
package thanos

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/tokamak-network/trh-sdk/pkg/types"
)

const externalVrfPublicKey = "0x032c8c31fc9f990c6b55e3865a184a4ce50e09481f2eaeb3e60ec1cea13a6ae645"

func TestExternalEnshrinedVrfValuesSmoke(t *testing.T) {
	valuesFile := filepath.Join(t.TempDir(), "values.yaml")
	if err := os.WriteFile(valuesFile, []byte("opNode:\n  extraArgs: []\n"), 0o600); err != nil {
		t.Fatal(err)
	}

	stack := &ThanosStack{deployConfig: &types.Config{EnshrinedVrf: &types.EnshrinedVrfConfig{
		Enabled:           true,
		Mode:              "tee",
		TeeEndpoint:       "unix:///var/run/vrf-enclave/vrf.sock",
		PublicKey:         externalVrfPublicKey,
		SetL1VRFPublicKey: true,
	}}}
	if err := stack.applyEnshrinedVrfValues(valuesFile); err != nil {
		t.Fatal(err)
	}

	raw, err := os.ReadFile(valuesFile)
	if err != nil {
		t.Fatal(err)
	}
	rendered := string(raw)
	for _, want := range []string{
		"enshrinedVrf:",
		"teeEndpoint: unix:///var/run/vrf-enclave/vrf.sock",
		"--sequencer.vrf-mode=tee",
		"vrfEnclave:",
	} {
		if !strings.Contains(rendered, want) {
			t.Fatalf("rendered values missing %q:\n%s", want, rendered)
		}
	}
}
EOF
  GOCACHE="$GOCACHE" go -C "$sdk_tmp" test ./pkg/types ./pkg/stacks/thanos -run 'TestExternal'
  echo "[ok] trh-sdk patched packages compile"
fi

if copy_repo "$TRH_BACKEND_PATH" "$backend_tmp" "trh-backend"; then
  if [ ! -d "$sdk_tmp" ]; then
    echo "[fail] trh-backend compile check requires patched trh-sdk temp copy" >&2
    exit 1
  fi
  git -C "$backend_tmp" apply "$ROOT/deploy/trh/external-integration/trh-backend-enshrined-vrf.patch"
  cat >"$backend_tmp/pkg/api/dtos/enshrined_vrf_external_test.go" <<'EOF'
package dtos

import "testing"

const externalVrfPublicKey = "0x032c8c31fc9f990c6b55e3865a184a4ce50e09481f2eaeb3e60ec1cea13a6ae645"

func TestExternalEnshrinedVrfRequestSmoke(t *testing.T) {
	req := &EnshrinedVrfRequest{
		Enabled:           true,
		Mode:              "tee",
		TeeEndpoint:       "unix:///var/run/vrf-enclave/vrf.sock",
		PublicKey:         externalVrfPublicKey,
		SetL1VRFPublicKey: true,
	}
	if err := req.Validate(); err != nil {
		t.Fatal(err)
	}
	cfg := req.ToSDKConfig()
	if cfg == nil || cfg.Mode != "tee" || cfg.TeeEndpoint != req.TeeEndpoint || cfg.PublicKey != req.PublicKey {
		t.Fatalf("unexpected sdk config: %#v", cfg)
	}

	req.TeeEndpoint = ""
	if err := req.Validate(); err == nil {
		t.Fatal("expected missing teeEndpoint to fail")
	}
}
EOF
  go -C "$backend_tmp" mod edit -replace "github.com/tokamak-network/trh-sdk=$sdk_tmp"
  cat "$sdk_tmp/go.sum" >>"$backend_tmp/go.sum"
  sort -u "$backend_tmp/go.sum" -o "$backend_tmp/go.sum"
  GOSUMDB=off GOCACHE="$GOCACHE" go -C "$backend_tmp" test -mod=mod ./pkg/api/dtos ./pkg/stacks/thanos ./pkg/services/thanos -run 'TestExternal'
  echo "[ok] trh-backend patched packages compile"
fi

if copy_repo "$TRH_PLATFORM_UI_PATH" "$ui_tmp" "trh-platform-ui"; then
  git -C "$ui_tmp" apply "$ROOT/deploy/trh/external-integration/trh-platform-ui-enshrined-vrf.patch"
  if [ -d "$TRH_PLATFORM_UI_PATH/node_modules" ]; then
    ln -s "$TRH_PLATFORM_UI_PATH/node_modules" "$ui_tmp/node_modules"
    "$ui_tmp/node_modules/.bin/tsc" -p "$ui_tmp/tsconfig.json" --noEmit --pretty false
    echo "[ok] trh-platform-ui patched TypeScript check passes"
  else
    echo "[warn] skipping trh-platform-ui TypeScript check because node_modules is missing" >&2
  fi
fi

echo "[external-patches-compile] ok"
