#!/usr/bin/env bash
set -euo pipefail

MANIFEST_FILE="${1:-deploy/trh/kubernetes-vrf-sidecar.example.yaml}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Variant selector. Defaults to "auto" — picks the variant by manifest
# filename when -nitro is in the path. Operators can also force the
# variant via env: VARIANT=unix | nitro.
VARIANT="${VARIANT:-auto}"

if [ ! -f "$MANIFEST_FILE" ]; then
  if [ -f "$ROOT/$MANIFEST_FILE" ]; then
    MANIFEST_FILE="$ROOT/$MANIFEST_FILE"
  else
    echo "kubernetes manifest file not found: $MANIFEST_FILE" >&2
    exit 1
  fi
fi

if [ "$VARIANT" = "auto" ]; then
  case "$MANIFEST_FILE" in
    *nitro*) VARIANT=nitro ;;
    *)       VARIANT=unix  ;;
  esac
fi

case "$VARIANT" in
  unix|nitro) ;;
  *) echo "VARIANT must be unix | nitro (got $VARIANT)" >&2; exit 1 ;;
esac

VARIANT="$VARIANT" ruby -ryaml -e '
  variant = ENV.fetch("VARIANT")
  path = ARGV.fetch(0)
  docs = YAML.load_stream(File.read(path))
  deployment = docs.find { |doc| doc.is_a?(Hash) && doc["kind"] == "Deployment" }
  abort "missing Deployment" unless deployment

  containers = deployment.dig("spec", "template", "spec", "containers") || []
  op_node = containers.find { |container| container["name"] == "op-node" }
  abort "missing op-node container" unless op_node

  op_args = op_node["args"] || []
  abort "op-node missing --sequencer.vrf-mode=tee" unless op_args.include?("--sequencer.vrf-mode=tee")
  abort "op-node missing unix TEE endpoint" unless op_args.include?("--sequencer.vrf-tee-endpoint=unix:///var/run/vrf-enclave/vrf.sock")

  op_mounts = op_node["volumeMounts"] || []
  abort "op-node missing socket mount" unless op_mounts.any? { |mount| mount["name"] == "vrf-enclave-socket" && mount["mountPath"] == "/var/run/vrf-enclave" }

  volumes = deployment.dig("spec", "template", "spec", "volumes") || []
  abort "missing socket emptyDir volume" unless volumes.any? { |volume| volume["name"] == "vrf-enclave-socket" && volume.key?("emptyDir") }

  case variant
  when "unix"
    enclave = containers.find { |container| container["name"] == "vrf-enclave" }
    abort "missing vrf-enclave container (unix variant)" unless enclave

    enclave_args = enclave["args"] || []
    abort "vrf-enclave missing listen arg" unless enclave_args.include?("--listen") && enclave_args.include?("unix:///var/run/vrf-enclave/vrf.sock")
    abort "vrf-enclave missing seal dir" unless enclave_args.include?("--seal-dir") && enclave_args.include?("/secure/sealed")

    enclave_mounts = enclave["volumeMounts"] || []
    abort "vrf-enclave missing socket mount" unless enclave_mounts.any? { |mount| mount["name"] == "vrf-enclave-socket" && mount["mountPath"] == "/var/run/vrf-enclave" }
    abort "vrf-enclave missing sealed storage mount" unless enclave_mounts.any? { |mount| mount["name"] == "vrf-enclave-sealed" && mount["mountPath"] == "/secure/sealed" }
    abort "vrf-enclave missing seal key mount" unless enclave_mounts.any? { |mount| mount["name"] == "vrf-enclave-seal-key" && mount["readOnly"] == true }

    abort "missing sealed PVC volume" unless volumes.any? { |volume| volume["name"] == "vrf-enclave-sealed" && volume.dig("persistentVolumeClaim", "claimName") == "vrf-enclave-sealed" }
    abort "missing seal-key secret volume" unless volumes.any? { |volume| volume["name"] == "vrf-enclave-seal-key" && volume.dig("secret", "secretName") == "vrf-enclave-seal-key" }

    secret = docs.find { |doc| doc.is_a?(Hash) && doc["kind"] == "Secret" && doc.dig("metadata", "name") == "vrf-enclave-seal-key" }
    pvc = docs.find { |doc| doc.is_a?(Hash) && doc["kind"] == "PersistentVolumeClaim" && doc.dig("metadata", "name") == "vrf-enclave-sealed" }
    abort "missing seal-key Secret" unless secret
    abort "missing sealed-storage PVC" unless pvc

  when "nitro"
    bridge = containers.find { |container| container["name"] == "vrf-enclave-bridge" }
    abort "missing vrf-enclave-bridge container (nitro variant)" unless bridge

    bridge_args = bridge["args"] || []
    abort "bridge missing --listen-unix" unless bridge_args.include?("--listen-unix") && bridge_args.include?("/var/run/vrf-enclave/vrf.sock")
    abort "bridge missing --upstream-vsock-cid" unless bridge_args.include?("--upstream-vsock-cid")
    abort "bridge missing --upstream-vsock-port" unless bridge_args.include?("--upstream-vsock-port")

    bridge_mounts = bridge["volumeMounts"] || []
    abort "bridge missing socket mount" unless bridge_mounts.any? { |mount| mount["name"] == "vrf-enclave-socket" && mount["mountPath"] == "/var/run/vrf-enclave" }
    abort "bridge missing /dev/vsock host mount" unless bridge_mounts.any? { |mount| mount["mountPath"] == "/dev/vsock" }

    abort "pod missing nitro-enclaves node selector" unless (deployment.dig("spec", "template", "spec", "nodeSelector") || {})["aws.amazon.com/nitro-enclaves"] == "enabled"

    launcher = docs.find { |doc| doc.is_a?(Hash) && doc["kind"] == "DaemonSet" && doc.dig("metadata", "name") == "vrf-enclave-launcher" }
    abort "missing vrf-enclave-launcher DaemonSet" unless launcher
    launcher_containers = launcher.dig("spec", "template", "spec", "containers") || []
    launcher_main = launcher_containers.find { |container| container["name"] == "vrf-enclave-launcher" }
    abort "launcher container not found" unless launcher_main
    launcher_args = launcher_main["args"] || []
    abort "launcher missing --eif-path" unless launcher_args.include?("--eif-path")
    abort "launcher missing --enclave-cid" unless launcher_args.include?("--enclave-cid")
    abort "launcher missing privileged securityContext" unless launcher_main.dig("securityContext", "privileged")
    launcher_volumes = launcher.dig("spec", "template", "spec", "volumes") || []
    abort "launcher missing nitro_enclaves host device" unless launcher_volumes.any? { |volume| volume.dig("hostPath", "path") == "/dev/nitro_enclaves" }
  end
' "$MANIFEST_FILE"

echo "[k8s-vrf-sidecar] ok ($VARIANT): $MANIFEST_FILE"
