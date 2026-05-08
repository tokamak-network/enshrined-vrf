#!/usr/bin/env bash
set -euo pipefail

MANIFEST_FILE="${1:-deploy/trh/kubernetes-vrf-sidecar.example.yaml}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ ! -f "$MANIFEST_FILE" ]; then
  if [ -f "$ROOT/$MANIFEST_FILE" ]; then
    MANIFEST_FILE="$ROOT/$MANIFEST_FILE"
  else
    echo "kubernetes manifest file not found: $MANIFEST_FILE" >&2
    exit 1
  fi
fi

ruby -ryaml -e '
  path = ARGV.fetch(0)
  docs = YAML.load_stream(File.read(path))
  deployment = docs.find { |doc| doc.is_a?(Hash) && doc["kind"] == "Deployment" }
  abort "missing Deployment" unless deployment

  containers = deployment.dig("spec", "template", "spec", "containers") || []
  op_node = containers.find { |container| container["name"] == "op-node" }
  enclave = containers.find { |container| container["name"] == "vrf-enclave" }
  abort "missing op-node container" unless op_node
  abort "missing vrf-enclave container" unless enclave

  op_args = op_node["args"] || []
  enclave_args = enclave["args"] || []
  abort "op-node missing --sequencer.vrf-mode=tee" unless op_args.include?("--sequencer.vrf-mode=tee")
  abort "op-node missing unix TEE endpoint" unless op_args.include?("--sequencer.vrf-tee-endpoint=unix:///var/run/vrf-enclave/vrf.sock")
  abort "vrf-enclave missing listen arg" unless enclave_args.include?("--listen") && enclave_args.include?("unix:///var/run/vrf-enclave/vrf.sock")
  abort "vrf-enclave missing seal dir" unless enclave_args.include?("--seal-dir") && enclave_args.include?("/secure/sealed")

  op_mounts = op_node["volumeMounts"] || []
  enclave_mounts = enclave["volumeMounts"] || []
  abort "op-node missing socket mount" unless op_mounts.any? { |mount| mount["name"] == "vrf-enclave-socket" && mount["mountPath"] == "/var/run/vrf-enclave" }
  abort "vrf-enclave missing socket mount" unless enclave_mounts.any? { |mount| mount["name"] == "vrf-enclave-socket" && mount["mountPath"] == "/var/run/vrf-enclave" }
  abort "vrf-enclave missing sealed storage mount" unless enclave_mounts.any? { |mount| mount["name"] == "vrf-enclave-sealed" && mount["mountPath"] == "/secure/sealed" }
  abort "vrf-enclave missing seal key mount" unless enclave_mounts.any? { |mount| mount["name"] == "vrf-enclave-seal-key" && mount["readOnly"] == true }

  volumes = deployment.dig("spec", "template", "spec", "volumes") || []
  abort "missing socket emptyDir volume" unless volumes.any? { |volume| volume["name"] == "vrf-enclave-socket" && volume.key?("emptyDir") }
  abort "missing sealed PVC volume" unless volumes.any? { |volume| volume["name"] == "vrf-enclave-sealed" && volume.dig("persistentVolumeClaim", "claimName") == "vrf-enclave-sealed" }
  abort "missing seal-key secret volume" unless volumes.any? { |volume| volume["name"] == "vrf-enclave-seal-key" && volume.dig("secret", "secretName") == "vrf-enclave-seal-key" }

  secret = docs.find { |doc| doc.is_a?(Hash) && doc["kind"] == "Secret" && doc.dig("metadata", "name") == "vrf-enclave-seal-key" }
  pvc = docs.find { |doc| doc.is_a?(Hash) && doc["kind"] == "PersistentVolumeClaim" && doc.dig("metadata", "name") == "vrf-enclave-sealed" }
  abort "missing seal-key Secret" unless secret
  abort "missing sealed-storage PVC" unless pvc
' "$MANIFEST_FILE"

echo "[k8s-vrf-sidecar] ok: $MANIFEST_FILE"
