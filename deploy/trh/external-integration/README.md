# TRH External Integration Package

This directory contains repo-local artifacts for wiring Enshrained VRF into
the external Tokamak Rollup Hub repositories.

The current `enshrined-vrf` workspace can prepare and verify a TEE-backed
game L2. Production TRH support is complete only after the external
repositories consume these contracts:

- `trh-sdk`: persist VRF settings, write the `l2GenesisEnshrainedVRFTimeOffset`
  deploy-config field, and pass VRF values to the Thanos chart values file.
- `tokamak-thanos-stack`: render the `vrf-enclave` sidecar/service and wire
  `op-node` with `--sequencer.vrf-mode=tee` and the private TEE endpoint.
- `trh-backend` and `trh-platform-ui`: expose the feature flag and validate
  `teeEndpoint`, `publicKey`, image tag, and attestation policy fields.

## Apply Order

Before applying a patch, verify it against the target repository with
`git apply --check /path/to/patch`.

1. Apply `trh-sdk-enshrained-vrf.patch` in the `trh-sdk` repository.
2. Port the Kubernetes shape from `../kubernetes-vrf-sidecar.example.yaml`
   into `tokamak-thanos-stack/charts/thanos-stack`; the expected values and
   template effects are defined in
   `tokamak-thanos-stack-chart-contract.md`.
3. Reuse `../settings.schema.json` in backend/API validation and UI forms.
4. Apply `trh-backend-enshrined-vrf.patch` in the `trh-backend` repository.
5. Apply `trh-platform-ui-enshrined-vrf.patch` in the `trh-platform-ui`
   repository.
6. Run:

```bash
TRH_SDK_PATH=/path/to/trh-sdk \
TRH_BACKEND_PATH=/path/to/trh-backend \
TRH_PLATFORM_UI_PATH=/path/to/trh-platform-ui \
./scripts/trh-check-external-patches.sh

TRH_SDK_PATH=/path/to/trh-sdk \
TRH_BACKEND_PATH=/path/to/trh-backend \
TRH_PLATFORM_UI_PATH=/path/to/trh-platform-ui \
./scripts/trh-verify-external-patches-compile.sh

TRH_SDK_PATH=/path/to/trh-sdk \
TRH_BACKEND_PATH=/path/to/trh-backend \
TRH_PLATFORM_UI_PATH=/path/to/trh-platform-ui \
./scripts/trh-apply-external-patches.sh

TRH_THANOS_STACK_PATH=/path/to/tokamak-thanos-stack \
./scripts/trh-validate-thanos-stack-chart.sh

TRH_SDK_PATH=/path/to/trh-sdk \
TRH_THANOS_STACK_PATH=/path/to/tokamak-thanos-stack \
TRH_BACKEND_PATH=/path/to/trh-backend \
TRH_PLATFORM_UI_PATH=/path/to/trh-platform-ui \
./scripts/trh-check-external-integration.sh
```

The checker intentionally fails on an unpatched external tree.
