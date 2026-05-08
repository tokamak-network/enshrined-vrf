# TRH TEE Game L2 Completion Audit

Objective: when a game L2 chain is deployed through TRH, randomness can be
enabled as TEE-backed Enshrined VRF.

## Success Criteria

1. TRH deployment settings can express `enshrinedVrf.enabled=true`,
   `mode=tee`, a private TEE endpoint, VRF public key, fork offset, image tag,
   and attestation policy.
2. `trh-sdk` can persist those settings, write the Thanos deploy-config fork
   field, and inject op-node/enclave Helm values.
3. `tokamak-thanos-stack` can run the VRF enclave beside the sequencer and pass
   `--sequencer.vrf-mode=tee` plus the TEE endpoint to op-node.
4. `trh-backend` can accept, validate, persist, and forward `enshrinedVrf`
   settings to the SDK.
5. `trh-platform-ui` can expose a game-L2 randomness option and send the
   required TEE fields in the deployment request.
6. The deployed chain can prove that L1/L2 VRF public keys match, the
   EnshrinedVRF predeploy is live, proofs verify, and game contracts can
   consume randomness.
7. Production deployment is blocked unless TEE attestation, image tag,
   external audit ID, and policy checks are satisfied.

## Evidence

| Requirement | Evidence | Status |
| --- | --- | --- |
| Settings schema and renderer | `deploy/trh/settings.schema.json`, `deploy/trh/settings.example.json`, `scripts/trh-render-vrf-settings.sh`, `scripts/trh-validate-vrf-settings.sh`, `scripts/test-trh-render-vrf-settings.sh` | Covered locally |
| SDK integration | `deploy/trh/external-integration/trh-sdk-enshrined-vrf.patch`; `./scripts/trh-check-external-patches.sh`; `./scripts/trh-verify-external-patches-compile.sh` | Patch applies and compiles in temp copy; not applied to external repo |
| Backend integration | `deploy/trh/external-integration/trh-backend-enshrined-vrf.patch`; temp compile/smoke test in `scripts/trh-verify-external-patches-compile.sh` | Patch applies and compiles in temp copy; not applied to external repo |
| UI integration | `deploy/trh/external-integration/trh-platform-ui-enshrined-vrf.patch`; TypeScript check in `scripts/trh-verify-external-patches-compile.sh` | Patch applies and typechecks in temp copy; not applied to external repo |
| Thanos chart contract | `deploy/trh/thanos-stack-vrf-values.example.yaml`, `deploy/trh/kubernetes-vrf-sidecar.example.yaml`, `deploy/trh/external-integration/tokamak-thanos-stack-chart-contract.md`, `scripts/trh-validate-thanos-stack-chart.sh` | Contract documented and validator prepared; chart repo not present locally |
| TEE enclave preflight | `vrf-enclave/Dockerfile`, `scripts/trh-build-vrf-enclave-image.sh`, `scripts/trh-attest-vrf-enclave.sh` | Local build syntax and CLI paths covered; real platform attestation still required |
| Deployed-chain verification | `scripts/trh-verify-vrf-chain.sh`, `scripts/trh-verify-vrf-proof.sh`, `scripts/trh-export-vrf-metrics.sh`, `deploy/trh/prometheus-rules.example.yaml` | Tooling present; requires deployed chain to run end-to-end |
| Production gate | `scripts/trh-production-vrf-gate.sh`, `deploy/trh/attestation-policy.schema.json`, `scripts/trh-validate-attestation-policy.sh`, `scripts/test-trh-attestation-policy.sh` | Covered locally; production measurements/audit must replace examples |
| Game consumer example | `contracts/src/examples/TRHGameRandomness.sol`, `contracts/test/TRHGameRandomness.t.sol` | Local Foundry test covered |
| CI readiness | `.github/workflows/trh-vrf-readiness.yml` | Static gates present; Docker build depends on runner Docker availability |

## Verified Commands

```bash
./scripts/trh-check-external-patches.sh
./scripts/trh-verify-external-patches-compile.sh
./scripts/trh-validate-thanos-stack-chart.sh /path/to/tokamak-thanos-stack/charts/thanos-stack
REQUIRE_TEE=0 ./scripts/trh-tee-readiness.sh
./scripts/test-trh-render-vrf-settings.sh
./scripts/test-trh-attestation-policy.sh
./scripts/test-trh-export-vrf-metrics.sh
./scripts/trh-validate-k8s-vrf-sidecar.sh deploy/trh/kubernetes-vrf-sidecar.example.yaml
```

## Missing Before Completion

- Apply patches to the actual `trh-sdk`, `trh-backend`, and `trh-platform-ui`
  repositories.
- Implement the `tokamak-thanos-stack` chart changes and run
  `scripts/trh-check-external-integration.sh` against the patched chart repo.
- Build and publish a production VRF enclave image.
- Replace example attestation policy measurements with real SGX/TDX/SEV-SNP
  measurements and wire a production verifier.
- Deploy at least one TRH game L2 with TEE randomness enabled and run
  `scripts/trh-verify-vrf-chain.sh`, `scripts/trh-verify-vrf-proof.sh`, and
  game-consumer transaction checks against that chain.

Current audit result: not complete. The repo-local implementation and external
patch package are prepared and compile-verified, but the actual external TRH
repositories and live deployment path are not yet modified or verified.
