# tokamak-thanos-stack Enshrined VRF Contract

The Thanos chart must expose the following values and render them into the
sequencer pod when `enshrinedVrf.enabled=true`.

## Values

```yaml
enshrinedVrf:
  enabled: true
  mode: tee
  teeEndpoint: unix:///var/run/vrf-enclave/vrf.sock
  publicKey: 0x03...
  predeploy: 0x42000000000000000000000000000000000000f0
  verifyPrecompile: 0x0000000000000000000000000000000000000101
  fork:
    enshrinedVrfTime: 0
    l2GenesisEnshrainedVRFTimeOffset: "0x0"
vrfEnclave:
  enabled: true
  image:
    repository: tokamaknetwork/vrf-enclave
    tag: v0.1.0
  socketPath: /var/run/vrf-enclave/vrf.sock
  sealedKeyMountPath: /secure/sealed
```

## Required Template Effects

- Add `--sequencer.vrf-mode=tee` to the op-node container args.
- Add `--sequencer.vrf-tee-endpoint=<enshrinedVrf.teeEndpoint>` to op-node.
- Mount a shared Unix socket volume at `/var/run/vrf-enclave`.
- Run the `vrf-enclave` workload as a sidecar or same-pod companion service.
- Mount sealed-key storage at `/secure/sealed`.
- Keep the TEE endpoint private to the sequencer pod.

## Local Reference Artifacts

- `deploy/trh/thanos-stack-vrf-values.example.yaml`
- `deploy/trh/kubernetes-vrf-sidecar.example.yaml`
- `scripts/trh-validate-k8s-vrf-sidecar.sh`
- `scripts/trh-check-external-integration.sh`
