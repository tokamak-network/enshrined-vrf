#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v rg >/dev/null 2>&1; then
  echo "[skip] test-trh-validate-thanos-stack-chart: rg (ripgrep) not installed" >&2
  exit 0
fi

tmpdir="$(mktemp -d "${TMPDIR:-/private/tmp}/trh-chart-validator.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

chart="$tmpdir/charts/thanos-stack"
mkdir -p "$chart/templates"

cat >"$chart/Chart.yaml" <<'YAML'
apiVersion: v2
name: thanos-stack
version: 0.1.0
YAML

cat >"$chart/values.yaml" <<'YAML'
enshrinedVrf:
  enabled: true
  teeEndpoint: unix:///var/run/vrf-enclave/vrf.sock
  publicKey: 0x032c8c31fc9f990c6b55e3865a184a4ce50e09481f2eaeb3e60ec1cea13a6ae645
  fork:
    l2GenesisEnshrainedVRFTimeOffset: "0x0"
vrfEnclave:
  enabled: true
YAML

cat >"$chart/templates/op-node.yaml" <<'YAML'
args:
  - --sequencer.vrf-mode=tee
  - --sequencer.vrf-tee-endpoint={{ .Values.enshrinedVrf.teeEndpoint }}
containers:
  - name: vrf-enclave
    volumeMounts:
      - name: vrf-enclave-socket
        mountPath: /var/run/vrf-enclave
      - name: sealed-key
        mountPath: /secure/sealed
YAML

"$ROOT/scripts/trh-validate-thanos-stack-chart.sh" "$chart"

rm "$chart/templates/op-node.yaml"
cat >"$chart/templates/op-node.yaml" <<'YAML'
args:
  - --sequencer.enabled=true
YAML

set +e
"$ROOT/scripts/trh-validate-thanos-stack-chart.sh" "$chart" >/tmp/trh-chart-validator.out 2>/tmp/trh-chart-validator.err
status=$?
set -e

if [ "$status" -eq 0 ]; then
  echo "[fail] expected incomplete chart to fail" >&2
  exit 1
fi

echo "[test-trh-validate-thanos-stack-chart] ok"
