#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

tee_endpoint = ENV.fetch("VRF_TEE_ENDPOINT", "unix:///var/run/vrf-enclave/vrf.sock")
image = ENV["VRF_ENCLAVE_IMAGE"]
image ||= "#{ENV.fetch("VRF_ENCLAVE_IMAGE_REPOSITORY", "tokamaknetwork/vrf-enclave")}:#{ENV.fetch("VRF_ENCLAVE_IMAGE_TAG", "dev")}"
attestation = ENV.fetch("VRF_ATTESTATION_MODE", "dev")
sealed_pvc = ENV.fetch("VRF_ENCLAVE_SEALED_PVC", "vrf-enclave-sealed")
seal_key_secret = ENV.fetch("VRF_ENCLAVE_SEAL_KEY_SECRET", "vrf-enclave-seal-key")
seal_key_hex = ENV["VRF_ENCLAVE_SEAL_KEY_HEX"]
namespace = ENV["VRF_K8S_NAMESPACE"]

socket_volume = { "name" => "vrf-enclave-socket", "emptyDir" => {} }
sealed_volume = {
  "name" => "vrf-enclave-sealed",
  "persistentVolumeClaim" => { "claimName" => sealed_pvc }
}
seal_key_volume = {
  "name" => "vrf-enclave-seal-key",
  "secret" => { "secretName" => seal_key_secret }
}

def ensure_named(list, item)
  list << item unless list.any? { |existing| existing["name"] == item["name"] }
end

def ensure_arg(container, arg)
  container["args"] ||= []
  container["args"] << arg unless container["args"].include?(arg)
end

def op_node_container?(container)
  name = container["name"].to_s
  image = container["image"].to_s
  args = Array(container["args"]).join(" ")

  name == "op-node" || name.include?("op-node") || image.include?("op-node") || args.include?("op-node")
end

documents = YAML.load_stream($stdin.read).compact
modified_workloads = 0

documents.each do |doc|
  next unless doc.is_a?(Hash)

  kind = doc["kind"]
  next unless %w[Deployment StatefulSet DaemonSet].include?(kind)

  pod_spec = doc.dig("spec", "template", "spec")
  next unless pod_spec.is_a?(Hash)

  containers = pod_spec["containers"]
  next unless containers.is_a?(Array)

  op_node = containers.find { |container| op_node_container?(container) }
  next unless op_node

  ensure_arg(op_node, "--sequencer.vrf-mode=tee")
  ensure_arg(op_node, "--sequencer.vrf-tee-endpoint=#{tee_endpoint}")

  op_node["volumeMounts"] ||= []
  ensure_named(op_node["volumeMounts"], {
    "name" => "vrf-enclave-socket",
    "mountPath" => "/var/run/vrf-enclave"
  })

  unless containers.any? { |container| container["name"] == "vrf-enclave" }
    containers << {
      "name" => "vrf-enclave",
      "image" => image,
      "args" => [
        "--listen", tee_endpoint,
        "--seal-dir", "/secure/sealed",
        "--seal-key-file", "/secure/seal-key/key.hex",
        "--attestation", attestation
      ],
      "volumeMounts" => [
        { "name" => "vrf-enclave-socket", "mountPath" => "/var/run/vrf-enclave" },
        { "name" => "vrf-enclave-sealed", "mountPath" => "/secure/sealed" },
        { "name" => "vrf-enclave-seal-key", "mountPath" => "/secure/seal-key", "readOnly" => true }
      ],
      "securityContext" => {
        "allowPrivilegeEscalation" => false,
        "readOnlyRootFilesystem" => true,
        "runAsNonRoot" => true
      }
    }
  end

  pod_spec["volumes"] ||= []
  ensure_named(pod_spec["volumes"], socket_volume)
  ensure_named(pod_spec["volumes"], sealed_volume)
  ensure_named(pod_spec["volumes"], seal_key_volume)

  modified_workloads += 1
end

if ENV.fetch("VRF_ENCLAVE_GENERATE_PVC", "0") == "1"
  documents << {
    "apiVersion" => "v1",
    "kind" => "PersistentVolumeClaim",
    "metadata" => {
      "name" => sealed_pvc,
      "namespace" => namespace
    }.compact,
    "spec" => {
      "accessModes" => ["ReadWriteOnce"],
      "resources" => { "requests" => { "storage" => ENV.fetch("VRF_ENCLAVE_SEALED_STORAGE", "1Gi") } }
    }
  }
end

if seal_key_hex && !seal_key_hex.empty?
  documents << {
    "apiVersion" => "v1",
    "kind" => "Secret",
    "metadata" => {
      "name" => seal_key_secret,
      "namespace" => namespace
    }.compact,
    "type" => "Opaque",
    "stringData" => { "key.hex" => seal_key_hex }
  }
end

if modified_workloads.zero?
  warn "[trh-vrf-post-renderer] no op-node workload found"
  exit 1
end

puts documents.map(&:to_yaml).join("---\n")
